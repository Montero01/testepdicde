# CDE Academy — ícones padronizados

Esta versão 2 aplica o padrão de ícones de traço laranja à navegação, aos botões, aos títulos de sistema e aos indicadores internos do Academy. O app.js e o style.css enviados foram preservados byte a byte. Não foram alteradas regras, dados, permissões, autenticação, cursos ou certificados.

## Arquivos

- `index.html`: original com duas inclusões, descritas abaixo.
- `app.js` e `style.css`: originais, sem alterações.
- `icones-cde.js`: substituição local dos ícones estáticos e dinâmicos.
- `icones-cde.css`: cor, dimensão, contraste contextual e tamanho para toque.

## Aplicação

Faça um backup e coloque `icones-cde.js` e `icones-cde.css` na mesma pasta do Academy.

No index.html original, após a linha 15:

```html
<link rel="stylesheet" href="style.css">
<link rel="stylesheet" href="icones-cde.css?v=2">
```

No fim do index.html original, após o script de app.js (aproximadamente linha 700):

```html
<script src="app.js"></script>
<script src="icones-cde.js?v=2"></script>
```

O index.html deste pacote já inclui essas linhas. Se seu arquivo publicado tiver outras alterações posteriores, acrescente somente as duas tags; não substitua o arquivo inteiro para não perder suas edições. Os números de linha referem-se ao arquivo enviado antes das inclusões.

Não é necessário colar código no app.js nem substituir funções.

## Comportamento

- Navegação: início, empresa, prêmios, cursos, catálogo, biblioteca, desempenho, certificados, analytics, dashboard, administração, logs e pontos.
- Ações: adicionar, editar, excluir, baixar, matrículas, questionário, visualizar, voltar, avançar, concluir, fechar, menu, notificações e tema.
- Ícones em laranja nos controles neutros; variação mais clara no tema escuro.
- Botões de fundo colorido e navegação selecionada mantêm a cor do texto no ícone, preservando o padrão de contraste do controle original.
- O ícone sol/lua é atualizado junto com o tema; o código original que troca o tema permanece intacto.
- O observador acompanha botões adicionados/atualizados depois do carregamento e se desconecta durante suas próprias substituições, evitando ciclos.
- Os elementos de botão, seus eventos, atributos, IDs, campos e contadores são preservados. Botões só com ícone recebem nome acessível quando não têm um nome definido.
- Em telas de até 600 px, os ícones usam 18 px e os controles com ícone têm altura mínima de 44 px.
- Não são carregadas bibliotecas, fontes de ícones ou imagens remotas adicionais.

## Novidades da versão 2 — páginas internas

Substitua os dois arquivos `icones-cde.js` e `icones-cde.css` anteriores pelos desta versão. Não deixe duas cópias do script carregadas. As tags com `?v=2` no index.html evitam reutilizar a versão anterior do cache; os nomes dos arquivos no disco continuam iguais.

Também são padronizados os títulos e ícones dos indicadores de Gerenciar Pontos, Log da Biblioteca, Gerenciar Cursos, Dashboard Executivo, Analytics e Meu Desempenho. Isso inclui comparativos de setores, alertas, histórico, rankings, calendário do período e ícones das linhas do log.

As medalhas do dashboard mantêm a informação visível de 1º, 2º e 3º lugar, com o desenho em traço. As opções do filtro nativo de ações do log ficam com texto simples, pois SVG não é confiável dentro de opções de select; os valores internos das opções e a seleção não são alterados.

Os ícones dos indicadores usam 28 px no desktop e 24 px no celular. Títulos e ações usam tamanhos menores compatíveis com o layout existente. Os ícones do cabeçalho colorido do Dashboard acompanham o texto branco. Os fundos dos pequenos marcadores de setor/alerta usam um tom suave de laranja.

O módulo só reescreve títulos de sistema explicitamente conhecidos. Nomes de cursos/livros/prêmios, textos de alunos, valores numéricos, fórmulas, cores de indicadores e gráficos são preservados. Não houve alteração de cálculo ou de dados.

## Ajuste de cor

No início de icones-cde.css:

```css
:root { --cde-academy-icon: #C05A12; }
[data-theme="dark"] { --cde-academy-icon: #FFAA66; }
```

Os fundos, cores de texto e demais estilos dos botões continuam os originais.

## Validação

Testado em DOM simulado com a estrutura real enviada: 13 itens de navegação, troca sol/lua, novos botões após renderização, alterações de texto, edição/exclusão/download, setas, sinal de mais, nomes acessíveis, preservação de onclick/listeners/campos/conteúdo/contador de notificações, inicialização repetida e estabilidade do observador. O JavaScript passou na verificação de sintaxe. Confirmada a identidade dos originais app.js e style.css.

Não foram executados login, ações de banco ou modificações no Supabase. Na versão 2, também passaram testes de títulos/KPIs, renderização original de Meu Desempenho com dados simulados, calendário e badges, identidade do canvas e dos seus dados, setores, alertas, posições das medalhas, linhas do log e valores das opções nativas. Verificados ainda a preservação dos textos de cursos/livros, números e cores inline dos indicadores, além da estabilidade do observador após as substituições.

Não houve conferência visual em navegador real nesta entrega.

## Reversão

Remova as duas tags novas do index.html. Como o app.js e o style.css originais não foram alterados, eles continuam funcionando sem o módulo de ícones.
