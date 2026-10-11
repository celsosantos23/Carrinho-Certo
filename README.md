# Carrinho Certo

App Android para fazer compras no supermercado sem passar do orçamento:
você define quanto pode gastar, registra cada item (por foto ou digitando) e vê o total
em tempo real, com barra verde, amarela e vermelha e alerta antes de estourar o limite.

## O que já funciona nesta versão

- Orçamento da compra e margem de segurança configurável (diferença entre etiqueta e caixa).
- Cadastro do item por **foto do rótulo** (nome) e **foto da etiqueta** (preço), lidas no
  próprio celular, sem internet. Você sempre confirma ou corrige antes de salvar.
- Quando a etiqueta tem mais de um preço, o app mostra as opções para você escolher.
- Quantidade ou peso em kg.
- Total em tempo real e barra de progresso: verde, amarela a partir de 80% e vermelha ao passar.
- Alerta ao adicionar um item que ultrapassa o limite ("Deixar na prateleira" ou "Levar mesmo assim").
- Editar (toque no item) e remover (arraste para a esquerda, com "Desfazer").
- Itens "Essencial" ou "Pode cortar" (toque no rótulo do item) e botão "O que retirar?"
  com sugestão de itens para voltar ao orçamento.
- Finalizar compra e histórico de compras.
- Tudo fica salvo só no celular. As fotos são apagadas logo depois da leitura.

Ainda não tem: lista prévia de compras, leitura de código de barras, carrinho compartilhado.

## Como gerar o APK (sem instalar nada no computador)

1. Crie uma conta gratuita em https://github.com e um repositório novo (pode ser privado),
   por exemplo `carrinho-certo`.
2. Envie o conteúdo desta pasta para o repositório. Na página do repositório, clique em
   **Add file > Upload files** e arraste **o conteúdo da pasta** (incluindo a pasta `.github`).
   Se a pasta `.github` não subir, use **Add file > Create new file**, digite
   `.github/workflows/build-apk.yml` como nome e cole o conteúdo do arquivo.
3. Abra a aba **Actions**. A compilação começa sozinha; se não começar, escolha
   **Gerar APK > Run workflow**.
4. Espere terminar (de 5 a 10 minutos). Abra a execução concluída e, no final da página,
   baixe o arquivo **carrinho-certo-apk** (vem em .zip).
5. Descompacte e envie o `app-release.apk` para o celular (WhatsApp, e-mail ou cabo).
6. No celular, abra o arquivo e permita a instalação de fontes desconhecidas quando
   o Android pedir. O app aparece como **Carrinho Certo**.

## Se a compilação falhar

Abra a execução com erro na aba Actions, copie as últimas linhas do log em vermelho e
envie para quem estiver ajudando você. Em geral é um ajuste pequeno de versão.

## Para quem for mexer no código

O código do app está em `lib/main.dart`. A parte Android (pasta `android/`) é gerada na
compilação pelo comando `flutter create`, por isso não está no repositório.
