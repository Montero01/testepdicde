# Redesenho de Desempenho — CDE

Atualização de interface de 16/11/2026. Mantém PCP, Caixa, registros, cálculos e a matriz de acesso definida: gerência/Diretoria/Master somente com dashboards, colaboradores com o próprio cadastro e supervisão com correções do setor.

## O que mudou

- Laranja oficial **#E87722**, com texto escuro **#202831**. Removidos os tons marrons dos botões e de seus estados de interação. Desabilitados ficam neutros, sem um laranja escurecido por transparência.
- Cabeçalho compacto, identificação do acesso e uma ação de atualizar os dados.
- Navegação PCP/Caixa com ícones de traço e estado ativo claro.
- Filtros com atalhos **Hoje**, **Este mês** e **Mês anterior**, mantendo a seleção de colaborador. Os atalhos usam o “hoje” informado pelo servidor e respeitam mudanças de mês e anos bissextos.
- Totais maiores e neutros, com laranja pontual; ranking de PCP em um painel próprio.
- Caixa com total do dia destacado, pagamentos agrupados, parcelamentos em uma seção e comprovante PDF em outra.
- Dashboard do Caixa com barras por forma de pagamento, além dos valores.
- Menos textos repetidos e blocos soltos. Os campos e validações necessários ao registro continuam disponíveis.
- Reorganização fluida em 760, 600 e 480 px; números e nomes podem quebrar linha sem impor larguras fixas ao módulo.

A alteração é restrita ao módulo Desempenho. O restante do PDI mantém seu visual. A prévia demonstra o módulo em um ambiente isolado com fundo neutro.

## Aplicar no PDI

Publique, na mesma pasta do seu `index.html`:

1. `desempenho.js`
2. `desempenho-caixa.js`
3. `desempenho.css`

Os três arquivos precisam ser atualizados juntos. O gancho em `app.js` e a referência de CSS/script no HTML continuam iguais aos da instalação anterior. Recarregue a página após publicar, usando Ctrl+F5 se houver cache da versão antiga.

Esta entrega modifica a interface. O banco já está configurado; os SQLs que acompanham o pacote são a referência de instalação e não precisam ser reaplicados para este redesenho.

## Experimentar antes de aplicar

Prévia publicada: https://pdi-cde-conceito.gabrielmacedomonte9.chatgpt.site/desempenho-preview.html

Na prévia, alterne **Visualizar como** entre Diretoria, Gerência, Supervisão, Colaborador PCP e Op. de Caixa. É possível usar filtros e simular um registro ou uma correção. Os dados são fictícios; nenhum cliente Supabase é criado. Alterações e PDFs selecionados ficam somente na memória desta aba e desaparecem ao recarregar. A prévia não demonstra armazenamento real nem substitui um fechamento oficial.

A pasta `demonstracao` contém o mesmo exemplo para inspeção. Os arquivos de interface nela são cópias exatas da versão de produção. Para instalar no PDI, use os três arquivos da raiz do pacote, sem substituir o HTML do seu sistema pelo HTML da demonstração.

## Verificação

- 58 verificações da interface PCP e 45 da interface Caixa, com DOM/API simulados: permissões, cadastro, correção, moeda/parcelas/PDF e os novos atalhos de período.
- 10 verificações da demonstração: troca de perfil, dados fictícios, registros simulados e atualização dos dashboards.
- Checagem da cascata junto ao CSS original recebido: botão principal e aba Desempenho ativos continuam laranja; botões secundários são neutros e o estado desabilitado não escurece a marca.
- Contraste calculado do texto dos botões: **5,03:1** entre #202831 e #E87722, acima de 4,5:1 para texto normal.
- Sintaxe do JS e CSS, inclusive regras para telas menores, verificada.
- Nenhuma alteração de banco nesta entrega; a matriz de acesso anterior continua aplicada no Supabase.

**Limite:** não havia navegador disponível para conferência visual nesta sessão. As verificações de DOM, CSS e contraste não medem a renderização real nem confirmam ausência de rolagem horizontal em cada aparelho. Confira a prévia e, após publicar, seu PDI em celular e computador.

Para reproduzir os testes de interface, use `linkedom@0.18.12` no ambiente de desenvolvimento e execute `node testes/interface.mjs`, `node testes/interface-caixa.mjs` e `node testes/demonstracao.mjs`. Para a checagem de cascata, use Python com `tinycss2`, `cssselect2` e `lxml` e execute `python3 testes/layout.py`. Essas dependências são apenas de teste, sem inclusão no site em produção.
