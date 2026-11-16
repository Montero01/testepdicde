# Desempenho · Op. de Caixa — PDI CDE

**Layout atualizado:** consulte LEIA-ME-LAYOUT.md e a pasta demonstracao. A nova interface usa laranja CDE, navegação por módulo e atalhos de período. Publique os três arquivos de interface juntos; os ganchos e permissões permanecem iguais.

Entrega de 16/11/2026, horário de Manaus. Complementa o PCP e mantém seu dashboard e ranking. Não substitui os arquivos originais do PDI nem muda a pontuação de metas.

**Atualização:** gerência, Diretoria e Master têm somente dashboards nas abas de desempenho. A correção agora é exclusiva da supervisão do setor. Os logs continuam preservados. Veja LEIA-ME-ACESSOS.md.

## Instalação nesta versão

O banco e o bucket privado **já foram configurados no Supabase do PDI** (`whjyvphamkbjcrdzhzoc`). Os testes de produção foram desfeitos por rollback: nenhum fechamento, log, reserva ou PDF de teste permaneceu no projeto.

Se já instalou o módulo PCP, publique estes **três arquivos** na pasta do seu PDI, junto do `index.html`:

- Substituir `desempenho.js`.
- Substituir `desempenho.css`.
- Acrescentar `desempenho-caixa.js`.

O gancho existente `window.CDEDesempenho?.setSession(db, user, profile);` continua igual. O arquivo `desempenho-caixa.js` é carregado automaticamente ao abrir Caixa. Não exige uma segunda conexão ou chave Supabase. Recarregue a página após publicar; se necessário, use Ctrl+F5 para atualizar os arquivos em cache.

Para instalação inicial, siga `INTEGRACAO.html`/`LEIA-ME.md`: link do CSS, script `desempenho.js` antes de `app.js` (ou `bootstrap.js`) e o gancho após `currentProfile = profile;`. Não substitua seu `app.js` por uma versão antiga.

Em outro projeto Supabase, instale nesta ordem: `desempenho-pcp.sql`, `dashboard-pcp.sql`, `desempenho-caixa.sql`, `desempenho-acessos-consulta.sql`. O último script pressupõe os auxiliares e a proteção de acesso já presentes no primeiro. Esses SQLs são referência; não precisa executá-los novamente no projeto atual. A publicação do seu GitHub Pages deve receber os arquivos acima; não foi modificada por esta entrega.

## Quem vê a tela

- `profiles.position = 'Op. de Caixa'`: ao abrir Desempenho, recebe o formulário de Caixa. Também reconhece `Op de Caixa`, `Op. Caixa`, `Operador de Caixa`, `Operadora de Caixa` e `Caixa`, ignorando caixa, pontos e espaços.
- `position = PCP`: continua abrindo o formulário PCP.
- Supervisores, gerentes e Diretoria/Master: em **Desempenho**, escolhem **PCP** ou **Caixa**. Autoridade vem de `role`/`is_master`; cargo textual não promove ninguém a gestor.
- Outros colaboradores continuam com seu PDI sem os formulários desses cargos.

## Campos do fechamento

| Campo | Como preencher |
| --- | --- |
| Resultado do Dia (Total R$) | Total geral do fechamento. Deve conferir exatamente com a soma das cinco formas de pagamento. |
| Em dinheiro R$ | Total informado em dinheiro. |
| Crédito à vista R$ | Total de crédito em uma parcela. |
| Crédito parcelado | Uma ou mais linhas, cada uma com valor total, valor padrão da parcela e quantidade de parcelas. O total da forma é calculado pela soma dos valores totais dessas linhas. |
| Débito R$ | Total informado em débito. |
| Pix R$ | Total informado em Pix. |
| PDF do fechamento | Um anexo opcional de até 10 MB. |

Valores aceitam `1234,56`, `1.234,56` ou `1234.56`. A tela confere em centavos inteiros e o banco armazena centavos, evitando divergências de ponto flutuante. Sem valores negativos ou mais de duas casas decimais. Limite técnico por total/forma: R$ 999.999.999,99.

O fechamento pode ser zero se todas as formas também forem zero. Campos das formas vêm com `0,00`; o Resultado do Dia precisa ser preenchido. Não há cálculo de taxas de cartão, conciliação automática com banco/ERP, leitura do conteúdo do PDF ou inclusão de sangria/saldo inicial nesta etapa. Informe todos os valores na mesma base do relatório de fechamento.

O PDF é um comprovante: os valores continuam sendo digitados e conferidos pela operadora.

### Crédito parcelado

Use **Adicionar parcelamento** para vendas com condições diferentes. Não se exige que todas as vendas parceladas do dia tenham a mesma quantidade de parcelas.

Cada linha aceita de 2 a 120 parcelas e até 200 linhas por fechamento. O valor padrão precisa corresponder ao total dividido pela quantidade, arredondado para centavos. A última parcela é calculada para fechar exatamente com o total.

Exemplo: **R$ 100,00 em 3 parcelas**, com parcela padrão **R$ 33,33** → duas parcelas de R$ 33,33 e última de **R$ 33,34**. A tela mostra o ajuste antes de registrar, e o banco o valida e grava. Se a parcela padrão não corresponder ao total, o fechamento é recusado.

O Resultado do Dia e o dashboard incluem o **valor total** do crédito parcelado, e não somente uma parcela. Não se trata de uma previsão das datas em que a adquirente depositará cada valor.

## Mesma regra de cadastro e correção do PCP

- Um fechamento por operadora por dia, garantido por restrição única no banco.
- “Hoje” é a data do servidor em `America/Manaus`, não o relógio do celular.
- A operadora registra somente o próprio dia atual. Depois de salvar, não altera valores, parcelamentos ou PDF e não exclui o fechamento.
- Somente supervisor do próprio setor pode selecionar a operadora e corrigir um fechamento existente. Nesta etapa, não cadastra em nome de outra pessoa.
- Gerência/Diretoria/Master não coletam, não corrigem e não enviam PDFs; veem somente dashboards, ainda que tenham um cargo operacional.
- Toda correção exige justificativa de 10 a 300 caracteres. Salvar sem alteração é recusado.
- Data, identidade e origem do fechamento permanecem preservadas.
- Se outro supervisor corrigir o registro antes de você salvar, a revisão carregada não é sobrescrita. Atualize os dados e confira a correção.
- Remover um anexo, substituí-lo ou corrigir apenas os parcelamentos também gera revisão e log.

A operadora cadastrada no projeto está no setor **ADMINISTRATIVO**. Um supervisor de PRODUÇÃO não recebe acesso ao Caixa administrativo por ser supervisor: é a mesma separação por setor usada no PCP. Gerência administrativa e Diretoria/Master mantêm seu alcance de consulta aos dashboards. Nenhum perfil ou setor foi alterado nesta entrega.

## PDFs e versões

Bucket `pdi-cash-pdfs`, privado, limitado a `application/pdf` e 10 MB. O navegador verifica a extensão e o cabeçalho `%PDF-` antes de enviar. A extensão/MIME não substituem antivírus; não há OCR ou análise do documento nesta versão.

Antes do envio, o banco reserva um identificador vinculado à operadora, ao dia e ao UUID do fechamento. O upload usa um caminho próprio e `upsert: false`. Para anexar, o banco confirma que o objeto foi enviado ao bucket correto, com o MIME/tamanho esperados e pertencendo à mesma reserva/operadora/fechamento. Um PDF inexistente ou vinculado a outro fechamento é recusado.

A reserva dura 24 horas. Se o envio terminar mas o fechamento falhar, a tela reaproveita o PDF enviado ao tentar salvar novamente, enquanto a mesma edição continuar aberta. Uma nova sessão pode exigir selecionar/enviar novamente. Reservas/arquivos pendentes de tentativas abandonadas não entram nos valores do dia nem no histórico; a limpeza administrativa deve ser feita pela API de Storage, após confirmar que não foram anexados. Não há rotina automática de limpeza neste MVP.

A aplicação não sobrescreve nem apaga PDFs. Ao corrigir:

- Deixar o arquivo vazio mantém o PDF atual.
- Escolher outro PDF cria uma nova versão.
- Marcar “Retirar o PDF atual” remove o vínculo atual; mantém a versão antiga para o log.

Operadora e supervisor consultam o PDF **atual** de um fechamento que podem acessar. PDFs antigos ficam acessíveis apenas à gerência do setor e à Diretoria/Master na auditoria. O download usa a sessão autenticada e um Blob local; não publica URLs permanentes nem usa bucket público.

As políticas restritivas do novo bucket neutralizam as permissões antigas globais de Storage para esses PDFs. Não mudam o acesso aos buckets de certificados, Academy, avatares ou logos. Usuários comuns não podem alterar o próprio nível de acesso, proteção já instalada no módulo PCP.

## Log e dashboard

**Logs:** continuam preservados para auditoria autorizada por gerente do setor e Diretoria/Master, mas não aparecem no modo de dashboards dessas abas. Operadora e supervisor não recebem o painel, não consultam a API da auditoria nem leem a justificativa pela tabela diária. O banco registra autor, papel, horário, antes/depois, justificativa e versões do PDF. Nem gestores apagam ou editam os logs pela API do aplicativo. Operações administrativas no banco continuam sendo privilegiadas e registradas pelo gatilho quando não forem desfeitas.

**Dashboard gerencial:** total do período, quantidade de fechamentos, caixas com registro e totais por forma de pagamento. Os filtros por período/operadora valem para dashboard e histórico. Agrega todos os registros autorizados no banco; não fica limitado à página atual do histórico. Correções substituem valores anteriores e não criam contagens duplicadas.

O histórico operacional começa recolhido, com 30 itens, para colaborador/supervisão. Gerência/Diretoria não recebem histórico operacional nem painel de logs na aba. O histórico filtra a data do fechamento; o log filtra a data da alteração. Os dados atualizam ao abrir, consultar filtros, salvar uma correção ou usar **Atualizar dados**; não há streaming em segundo plano.

## Objetos acrescentados

- `pdi_cash_daily`: fechamentos, centavos, parcelamentos e vínculo do PDF atual.
- `pdi_cash_audit`: logs imutáveis pela API do app.
- `pdi_cash_files`: reservas e metadados privados das versões de PDF.
- RPCs `pdi_cash_context`, `pdi_cash_reserve_pdf`, `pdi_cash_dashboard`.
- Funções internas no schema privado existente e políticas específicas de Storage.

Os objetos e logs PCP foram mantidos separados dos de Caixa. Ao retirar a interface, remova seus ganchos/arquivos; mantenha as tabelas e os PDFs para preservar a auditoria. Não apague objetos diretamente em `storage.objects` para limpar arquivos: use a API de Storage.

## Verificação e limites desta sessão

- **71 verificações de banco/RLS do Caixa**, com dados fictícios em PostgreSQL 17: moeda, parcelas, unicidade, papéis/setores, logs, reservas, vínculo de anexos, versões antigas e bloqueio de sobrescrita/exclusão.
- **43 verificações da interface Caixa**, com DOM/APIs simulados: validação, arredondamento, PDF inválido, falha de upload, reaproveitamento do upload, envio repetido, correção, concorrência, dashboard e seleção PCP/Caixa.
- **53 verificações da interface PCP** passaram novamente.
- Testes transacionais no Supabase real confirmaram cargo, registro diário, bloqueio de edição pela operadora, bloqueio de correção pela gestão, log preservado, dashboard e recusa de PDF ainda não enviado. Tudo foi desfeito; zero dados de teste persistentes.
- Bucket real confirmado privado, com MIME/tamanho e regras instaladas. A checagem de segurança não trouxe novos avisos dos objetos Caixa; os avisos anteriores estão descritos no LEIA-ME do PCP.
- JS e CSS verificados. Grids se reorganizam em 760 e 480 px, com campos sem larguras fixas e botões acessíveis ao toque.
- **Não houve teste visual em navegador/celular nem envio/download físico de PDF com uma sessão real de usuário nesta sessão.** As regras de anexos foram testadas com metadados fictícios apenas no banco local; o projeto real não recebeu PDFs de teste. Após publicar os três arquivos, confira um fechamento autorizado com PDF, o download e uma substituição pela supervisão.

### Reproduzir os testes do Caixa localmente

Não execute fixtures no projeto real. Docker sem portas públicas e somente dados fictícios:

```sh
docker run --rm -d --name cde-caixa-qa --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17
docker exec cde-caixa-qa createdb -U postgres pdiqa
docker exec -i cde-caixa-qa psql -U postgres -d pdiqa -v ON_ERROR_STOP=1 < testes/fixture.sql
docker exec -i cde-caixa-qa psql -U postgres -d pdiqa -v ON_ERROR_STOP=1 < desempenho-pcp.sql
docker exec -i cde-caixa-qa psql -U postgres -d pdiqa -v ON_ERROR_STOP=1 < testes/caixa-storage-fixture.sql
docker exec -i cde-caixa-qa psql -U postgres -d pdiqa -v ON_ERROR_STOP=1 < desempenho-caixa.sql
python3 testes/banco-caixa.py
```

Para os testes de interface, instale `linkedom@0.18.12` somente no ambiente de desenvolvimento e rode `node testes/interface-caixa.mjs`. Também aceita `CDE_LINKEDOM_MODULE` apontando ao ESM instalado. O site em produção não usa LinkeDOM.
