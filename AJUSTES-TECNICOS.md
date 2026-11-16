# PDI CDE — ajustes técnicos nos arquivos originais

Base: os arquivos index.html, app.js, style.css e readme.md enviados pelo usuário. Não é a proposta visual demonstrativa. O CSS e o README permanecem idênticos aos arquivos recebidos; não foram criados novos temas, telas ou recursos de negócio.

## Instalação

1. Guarde uma cópia dos arquivos atuais do seu PDI.
2. Substitua index.html e app.js pelos arquivos deste pacote.
3. Coloque **bootstrap.js na mesma pasta do index.html**. Esse arquivo é necessário para a inicialização corrigida.
4. O style.css do pacote é o original, sem mudanças. Mantenha-o na mesma pasta.
5. Após publicar os arquivos na sua hospedagem habitual, atualize a página e teste com sua conta.

O readme.md original descreve a CDE Academy e foi preservado como recebido. Para esta entrega do PDI, use estas instruções de substituição.

## Correções

- Mensagens exibidas como texto, sem interpretar HTML vindo de erros ou nomes de arquivos; uma nova mensagem cancela o temporizador anterior.
- Entrada com Enter no campo de senha; e-mail sem espaços nas extremidades; senha preservada exatamente como digitada.
- Bloqueio contra login repetido enquanto a requisição está em andamento; botão restaurado após sucesso ou erro.
- Falhas de logout não recarregam a página como se o encerramento tivesse funcionado.
- Carregamento de perfil com requisições simultâneas compartilhadas; erros de conexão apresentados ao usuário.
- Eventos de autenticação carregam os dados fora do callback síncrono. Ao receber saída da sessão, as telas autenticadas e os modais são ocultados e o estado do usuário é limpo.
- A mesma versão original do SDK Supabase, **2.45.4**, é carregada com fallback entre os dois CDNs originais. O aplicativo inicia depois do SDK; falhas nos dois servidores, timeout, falha do app ou inicialização incompleta deixam um aviso visível, sem habilitar um login quebrado. Não há mais document.write. O caminho do segundo CDN foi corrigido: o arquivo .min.js original retornava HTTP 404; o caminho .js corrigido foi conferido e retorna HTTP 200.
- Pontuações de criação/edição/aprovação aceitam apenas inteiros seguros e não negativos, respeitando os limites já existentes. Valores como 1,5 não são silenciosamente truncados para 1.
- O primeiro comprovante obrigatório não pode ser substituído pelo segundo arquivo opcional. Extensão e MIME informado são conferidos conjuntamente; navegador sem MIME pode usar uma extensão válida. Mantidos PDF, PNG e JPG e o limite original de 10 MB por arquivo.
- Bloqueio contra reenvio simultâneo pelo mesmo formulário, com recuperação do botão após erros. Um erro de atualização da lista depois de um envio concluído é distinguido de falha no envio.
- A atualização de pontuação após o envio só ocorre quando o envio teve sucesso.
- O rótulo de aderência foi corrigido de “aprovados / enviados” para **“aprovados / analisados”**, pois a fórmula original já usava aprovados ÷ (aprovados + rejeitados). A fórmula foi preservada.
- A área de mensagens agora possui anúncio acessível. Campos de login possuem rótulos acessíveis e preenchimento automático adequado.

## Escopo preservado

Foram mantidos o visual original, os seletores e IDs existentes, metas, coeficiente, ranking, fluxos de aprovação, perfis, setores, upload e integração com a Academy. A configuração pública do cliente Supabase foi preservada. A chave foi verificada como chave pública de cliente; não há chave privilegiada adicionada.

Nenhuma tabela, política RLS, bucket ou dado do Supabase foi alterado por esta revisão. As validações no navegador não substituem as permissões do servidor. Não foram criadas novas regras de pontuação ou permissões.

## Validação

Com Node.js instalado, execute na pasta extraída:

```
node --check app.js
node --check bootstrap.js
node testes/ajustes.mjs
node testes/bootstrap.mjs
```

Passaram os testes de mensagens, pontuações inteiras, login, saída, Enter, validação/concorrência de envios, recuperação de erros, preservação do coeficiente, eventos de autenticação e carregamento do SDK/app. Os testes usam serviços simulados e não fazem requisições ao banco real.

Também foram conferidos IDs únicos e a identidade byte a byte do CSS original. Autenticação real, permissões de banco/Storage e aparência em navegador não foram validadas; exigem conferência na hospedagem e conta reais.

Se um upload terminar no Storage e uma etapa seguinte falhar, o tratamento original de arquivos já enviados é preservado; não foi implementada exclusão automática de arquivos nesta correção.
