import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------

String money(double v) {
  final s = v.abs().toStringAsFixed(2);
  final parts = s.split('.');
  final inteiro = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => '.',
  );
  return '${v < 0 ? '-' : ''}R\$ $inteiro,${parts[1]}';
}

double? parseNumber(String text) {
  var t = text.trim();
  if (t.isEmpty) return null;
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(t);
}

String numText(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString().replaceAll('.', ',');
}

String dateText(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

// ---------------------------------------------------------------------------
// Leitura de foto (IA no aparelho, funciona sem internet)
// ---------------------------------------------------------------------------

Future<String?> readTextFromCamera() async {
  final photo = await ImagePicker().pickImage(
    source: ImageSource.camera,
    imageQuality: 85,
  );
  if (photo == null) return null;
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(
      InputImage.fromFilePath(photo.path),
    );
    return result.text;
  } finally {
    await recognizer.close();
    // A foto não fica guardada: é apagada logo após a leitura.
    try {
      await File(photo.path).delete();
    } catch (_) {}
  }
}

List<String> nameCandidates(String text) {
  final out = <String>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.length < 3 || line.length > 40) continue;
    final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(line).length;
    if (letters < 3 || letters / line.length < 0.6) continue;
    if (!out.contains(line)) out.add(line);
  }
  out.sort((a, b) => b.length.compareTo(a.length));
  return out.take(4).toList();
}

List<double> priceCandidates(String text) {
  final out = <double>[];
  final re = RegExp(r'(\d{1,3}(?:\.\d{3})+|\d+)[,.](\d{2})(?!\d)');
  for (final m in re.allMatches(text)) {
    final v = double.tryParse(
      '${m.group(1)!.replaceAll('.', '')}.${m.group(2)}',
    );
    if (v != null && v > 0 && v < 10000 && !out.contains(v)) out.add(v);
  }
  return out.take(6).toList();
}

Future<int?> pickOption(
  BuildContext context,
  String title,
  List<String> labels,
) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (var i = 0; i < labels.length; i++)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, i),
            child: Text(labels[i]),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

class Item {
  Item({
    required this.id,
    required this.name,
    required this.price,
    required this.qty,
    required this.essential,
  });

  final String id;
  final String name;
  final double price;
  final double qty;
  final bool essential;

  double get total => price * qty;

  Item copyWith({bool? essential}) => Item(
        id: id,
        name: name,
        price: price,
        qty: qty,
        essential: essential ?? this.essential,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'qty': qty,
        'essential': essential,
      };

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        name: j['name'] as String,
        price: (j['price'] as num).toDouble(),
        qty: (j['qty'] as num).toDouble(),
        essential: j['essential'] as bool,
      );
}

class Purchase {
  Purchase({
    required this.date,
    required this.budget,
    required this.total,
    required this.items,
  });

  final DateTime date;
  final double budget;
  final double total;
  final List<Item> items;

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'budget': budget,
        'total': total,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory Purchase.fromJson(Map<String, dynamic> j) => Purchase(
        date: DateTime.parse(j['date'] as String),
        budget: (j['budget'] as num).toDouble(),
        total: (j['total'] as num).toDouble(),
        items: (j['items'] as List)
            .map((e) => Item.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ---------------------------------------------------------------------------
// Estado do app (tudo salvo no próprio celular)
// ---------------------------------------------------------------------------

class AppState extends ChangeNotifier {
  AppState(this._prefs);

  final SharedPreferences _prefs;

  double budget = 0;
  double margin = 0; // margem de segurança em %
  List<Item> items = [];
  List<Purchase> history = [];

  static Future<AppState> load() async {
    final p = await SharedPreferences.getInstance();
    final s = AppState(p);
    s.budget = p.getDouble('budget') ?? 0;
    s.margin = p.getDouble('margin') ?? 0;
    try {
      final i = p.getString('items');
      if (i != null) {
        s.items = (jsonDecode(i) as List)
            .map((e) => Item.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      final h = p.getString('history');
      if (h != null) {
        s.history = (jsonDecode(h) as List)
            .map((e) => Purchase.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // dados antigos ou corrompidos: começa vazio
    }
    return s;
  }

  Future<void> _save() async {
    await _prefs.setDouble('budget', budget);
    await _prefs.setDouble('margin', margin);
    await _prefs.setString(
      'items',
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
    await _prefs.setString(
      'history',
      jsonEncode(history.map((e) => e.toJson()).toList()),
    );
  }

  void _commit() {
    notifyListeners();
    _save();
  }

  double get subtotal => items.fold<double>(0, (a, b) => a + b.total);
  double get estimated => subtotal * (1 + margin / 100);
  double get remaining => budget - estimated;
  double get ratio => budget <= 0 ? 0 : estimated / budget;

  void setBudget(double b, double m) {
    budget = b;
    margin = m;
    _commit();
  }

  void addItem(Item it) {
    items.add(it);
    _commit();
  }

  void insertItem(int index, Item it) {
    final i = index > items.length ? items.length : index;
    items.insert(i, it);
    _commit();
  }

  void replaceItem(Item it) {
    final i = items.indexWhere((e) => e.id == it.id);
    if (i >= 0) items[i] = it;
    _commit();
  }

  void removeItem(String id) {
    items.removeWhere((e) => e.id == id);
    _commit();
  }

  void removeMany(Iterable<String> ids) {
    final set = ids.toSet();
    items.removeWhere((e) => set.contains(e.id));
    _commit();
  }

  void toggleEssential(String id) {
    final i = items.indexWhere((e) => e.id == id);
    if (i >= 0) items[i] = items[i].copyWith(essential: !items[i].essential);
    _commit();
  }

  void finish() {
    if (items.isEmpty) return;
    history.insert(
      0,
      Purchase(
        date: DateTime.now(),
        budget: budget,
        total: subtotal,
        items: List<Item>.of(items),
      ),
    );
    items = [];
    _commit();
  }

  /// Itens "pode cortar" a retirar para voltar ao orçamento.
  List<Item> cutSuggestion() {
    var excess = estimated - budget;
    final result = <Item>[];
    if (budget <= 0 || excess <= 0) return result;
    final factor = 1 + margin / 100;
    final candidates = items.where((e) => !e.essential).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    // Se um único item resolve, sugere o menor que resolve.
    final covering =
        candidates.where((e) => e.total * factor >= excess).toList();
    if (covering.isNotEmpty) return [covering.last];
    for (final it in candidates) {
      if (excess <= 0) break;
      result.add(it);
      excess -= it.total * factor;
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.load();
  runApp(CarrinhoApp(state: state));
}

class CarrinhoApp extends StatelessWidget {
  const CarrinhoApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carrinho Certo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B8A5A)),
        useMaterial3: true,
      ),
      home: HomePage(state: state),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Carrinho Certo'),
            actions: [
              IconButton(
                tooltip: 'Histórico',
                icon: const Icon(Icons.history),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => HistoryPage(state: state),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Orçamento',
                icon: const Icon(Icons.tune),
                onPressed: () => _settings(context),
              ),
            ],
          ),
          body: Column(
            children: [
              SummaryCard(
                state: state,
                onCut: () => _showCut(context),
                onSet: () => _settings(context),
              ),
              Expanded(
                child: state.items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Seu carrinho está vazio.\n'
                            'Toque em "Adicionar item" e fotografe a etiqueta '
                            'ou digite o preço.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: state.items.length,
                        itemBuilder: (context, i) => _tile(context, i),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addOrEdit(context),
            icon: const Icon(Icons.add_a_photo),
            label: const Text('Adicionar item'),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: OutlinedButton.icon(
                onPressed: () => _finish(context),
                icon: const Icon(Icons.check),
                label: const Text('Finalizar compra'),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, int i) {
    final it = state.items[i];
    return Dismissible(
      key: ValueKey(it.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        state.removeItem(it.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${it.name} removido'),
            action: SnackBarAction(
              label: 'Desfazer',
              onPressed: () => state.insertItem(i, it),
            ),
          ),
        );
      },
      child: ListTile(
        onTap: () => _addOrEdit(context, item: it),
        title: Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('${numText(it.qty)} × ${money(it.price)}'),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              money(it.total),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => state.toggleEssential(it.id),
              child: Text(
                it.essential ? 'Essencial' : 'Pode cortar',
                style: TextStyle(
                  fontSize: 12,
                  color: it.essential
                      ? Colors.green.shade800
                      : Colors.orange.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _settings(BuildContext context) async {
    final r = await showDialog<List<double>>(
      context: context,
      builder: (_) => SettingsDialog(budget: state.budget, margin: state.margin),
    );
    if (r != null) state.setBudget(r[0], r[1]);
  }

  Future<void> _addOrEdit(BuildContext context, {Item? item}) async {
    final result = await showModalBottomSheet<Item>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ItemSheet(initial: item),
    );
    if (result == null || !context.mounted) return;

    final oldTotal = item?.total ?? 0.0;
    final factor = 1 + state.margin / 100;
    final newEstimated = (state.subtotal - oldTotal + result.total) * factor;

    // Alerta ANTES de estourar: o produto ainda está na mão.
    if (state.budget > 0 &&
        newEstimated > state.budget &&
        result.total > oldTotal) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.red,
            size: 36,
          ),
          title: const Text('Passa do orçamento'),
          content: Text(
            'Com "${result.name}", o total vai para ${money(newEstimated)} '
            'e passa ${money(newEstimated - state.budget)} do seu limite.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Deixar na prateleira'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Levar mesmo assim'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }

    if (item == null) {
      state.addItem(result);
    } else {
      state.replaceItem(result);
    }
  }

  Future<void> _showCut(BuildContext context) async {
    final sug = state.cutSuggestion();
    final factor = 1 + state.margin / 100;
    final excess = state.estimated - state.budget;

    if (sug.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nenhum item marcado como "Pode cortar"'),
          content: Text(
            'O total passa ${money(excess)} do orçamento. Toque em '
            '"Essencial" ao lado de um item para mudar para "Pode cortar" '
            'e eu sugiro o que retirar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Ok'),
            ),
          ],
        ),
      );
      return;
    }

    final saved = sug.fold<double>(0, (a, b) => a + b.total * factor);
    final still = excess - saved;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sugestão de itens para retirar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final it in sug) Text('• ${it.name} (${money(it.total)})'),
            const SizedBox(height: 12),
            Text(
              still > 0.005
                  ? 'Mesmo retirando estes, ainda passa ${money(still)}.'
                  : 'Retirando estes, você volta para dentro do orçamento.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Manter'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirar'),
          ),
        ],
      ),
    );
    if (ok == true) state.removeMany(sug.map((e) => e.id));
  }

  Future<void> _finish(BuildContext context) async {
    if (state.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione itens antes de finalizar.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar compra?'),
        content: Text(
          'Total de ${money(state.subtotal)} em ${state.items.length} itens. '
          'A compra será salva no histórico e o carrinho ficará vazio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (ok == true) state.finish();
  }
}

// ---------------------------------------------------------------------------
// Resumo com barra de progresso colorida
// ---------------------------------------------------------------------------

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.state,
    required this.onCut,
    required this.onSet,
  });

  final AppState state;
  final VoidCallback onCut;
  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s.budget <= 0) {
      return Card(
        margin: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('Defina quanto você pode gastar nesta compra.'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: onSet,
                child: const Text('Definir orçamento'),
              ),
            ],
          ),
        ),
      );
    }

    final ratio = s.ratio;
    final Color color = ratio > 1
        ? Colors.red.shade600
        : ratio >= 0.8
            ? Colors.amber.shade700
            : Colors.green.shade600;
    final over = s.estimated > s.budget;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Orçamento ${money(s.budget)}'),
                Text('${s.items.length} itens'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              money(s.estimated),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (s.margin > 0)
              Text(
                'Inclui margem de segurança de ${numText(s.margin)}%',
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio > 1 ? 1.0 : ratio,
                minHeight: 14,
                color: color,
                backgroundColor: color.withOpacity(0.15),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              over
                  ? 'Passou ${money(s.estimated - s.budget)} do orçamento'
                  : 'Ainda restam ${money(s.remaining)}',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            if (over)
              TextButton.icon(
                onPressed: onCut,
                icon: const Icon(Icons.content_cut),
                label: const Text('O que retirar?'),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Configuração do orçamento e da margem
// ---------------------------------------------------------------------------

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.budget, required this.margin});

  final double budget;
  final double margin;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController budget = TextEditingController(
    text: widget.budget > 0
        ? widget.budget.toStringAsFixed(2).replaceAll('.', ',')
        : '',
  );
  late final TextEditingController margin = TextEditingController(
    text: widget.margin > 0 ? numText(widget.margin) : '',
  );

  @override
  void dispose() {
    budget.dispose();
    margin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Orçamento da compra'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: budget,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quanto posso gastar',
                prefixText: 'R\$ ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: margin,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Margem de segurança (%)',
                helperText: 'Cobre diferenças entre etiqueta e caixa. Ex.: 5',
                helperMaxLines: 2,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final b = parseNumber(budget.text) ?? 0;
            final m = parseNumber(margin.text) ?? 0;
            Navigator.pop(context, <double>[b < 0 ? 0.0 : b, m < 0 ? 0.0 : m]);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cadastro / edição de item (com leitura por foto)
// ---------------------------------------------------------------------------

class ItemSheet extends StatefulWidget {
  const ItemSheet({super.key, this.initial});

  final Item? initial;

  @override
  State<ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<ItemSheet> {
  late final TextEditingController name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController price = TextEditingController(
    text: widget.initial == null
        ? ''
        : widget.initial!.price.toStringAsFixed(2).replaceAll('.', ','),
  );
  late final TextEditingController qty = TextEditingController(
    text: widget.initial == null ? '1' : numText(widget.initial!.qty),
  );
  late bool essential = widget.initial?.essential ?? true;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    qty.dispose();
    super.dispose();
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _scan(bool forName) async {
    setState(() => busy = true);
    try {
      final text = await readTextFromCamera();
      if (text == null || !mounted) return;

      if (forName) {
        final c = nameCandidates(text);
        if (c.isEmpty) {
          _msg('Não encontrei um nome na foto. Digite o nome.');
          return;
        }
        final idx = c.length == 1
            ? 0
            : await pickOption(context, 'Qual é o nome do produto?', c);
        if (idx != null && mounted) setState(() => name.text = c[idx]);
      } else {
        final c = priceCandidates(text);
        if (c.isEmpty) {
          _msg('Não encontrei um preço na foto. Digite o valor.');
          return;
        }
        final idx = c.length == 1
            ? 0
            : await pickOption(
                context,
                'Qual é o preço?',
                c.map(money).toList(),
              );
        if (idx != null && mounted) {
          setState(() => price.text = c[idx].toStringAsFixed(2).replaceAll('.', ','));
        }
      }
    } catch (_) {
      if (mounted) _msg('Não consegui ler a foto. Digite manualmente.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _save() {
    final n = name.text.trim();
    final p = parseNumber(price.text);
    final q = parseNumber(qty.text);
    if (n.isEmpty) {
      setState(() => error = 'Informe o nome do produto.');
      return;
    }
    if (p == null || p <= 0) {
      setState(() => error = 'Informe o preço.');
      return;
    }
    if (q == null || q <= 0) {
      setState(() => error = 'Informe a quantidade (ou o peso em kg).');
      return;
    }
    Navigator.pop(
      context,
      Item(
        id: widget.initial?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: n,
        price: p,
        qty: q,
        essential: essential,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? 'Novo item' : 'Editar item',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => _scan(true),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text(
                      'Foto rótulo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => _scan(false),
                    icon: const Icon(Icons.sell),
                    label: const Text(
                      'Foto etiqueta',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome do produto',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Preço',
                      prefixText: 'R\$ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: qty,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Quantidade ou kg',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text('Essencial')),
                ButtonSegment<bool>(value: false, label: Text('Pode cortar')),
              ],
              selected: <bool>{essential},
              onSelectionChanged: (v) => setState(() => essential = v.first),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Salvar')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Histórico de compras
// ---------------------------------------------------------------------------

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final list = state.history;
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de compras')),
      body: list.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhuma compra finalizada ainda.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final p = list[i];
                return ExpansionTile(
                  title: Text('${money(p.total)} · ${dateText(p.date)}'),
                  subtitle: Text(
                    'Orçamento ${money(p.budget)} · ${p.items.length} itens',
                  ),
                  children: [
                    for (final it in p.items)
                      ListTile(
                        dense: true,
                        title: Text(it.name),
                        subtitle: Text('${numText(it.qty)} × ${money(it.price)}'),
                        trailing: Text(money(it.total)),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
