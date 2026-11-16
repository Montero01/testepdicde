# Desempenho PCP e Caixa — PDI CDE

**Layout atualizado:** consulte LEIA-ME-LAYOUT.md e a pasta demonstracao. A nova interface usa laranja CDE, navegação por módulo e atalhos de período. Publique os três arquivos de interface juntos; os ganchos e permissões permanecem iguais.

Módulos PCP e Op. de Caixa com dashboard gerencial, com integração por `profiles.position`. Mantém o visual atual e não substitui seu `app.js`, `index.html` ou `style.css` editados.

**Atualização de acesso:** gerência, Diretoria e Master agora veem somente filtros e dashboards. Coleta pelo colaborador e correção somente pela supervisão. Veja LEIA-ME-ACESSOS.md.

As regras específicas do Caixa, PDF, parcelamentos e seus testes estão em **LEIA-ME-CAIXA.md**. As seções de m² e ranking abaixo descrevem o PCP.

## Estado da entrega — 16/11/2026

- Dashboard por total de m² e ranking incluído para supervisão, gerência e Diretoria.
- Banco instalado no Supabase do PDI (`whjyvphamkbjcrdzhzoc`). Tabelas, regras de acesso e a função `pdi_pcp_dashboard` ativas.
- Testes com os papéis reais do projeto executados em transação e desfeitos. Zero lançamentos e logs de teste persistentes.
- Para o menu aparecer em seu PDI publicado, copie os três arquivos do módulo e aplique as três integrações abaixo. A publicação do seu GitHub Pages não foi alterada por esta entrega.
- Se já integrou o módulo anterior, substitua `desempenho.js` e `desempenho.css`, acrescente `desempenho-caixa.js` e recarregue o PDI. Os ganchos existentes continuam iguais.
- Os SQLs acompanham o pacote como referência para outra instalação: primeiro `desempenho-pcp.sql`, depois `dashboard-pcp.sql`, `desempenho-caixa.sql` e `desempenho-acessos-consulta.sql`. O projeto atual já recebeu todos.

## Integração no PDI atual

1. Copie `desempenho.js`, `desempenho.css` e `desempenho-caixa.js` para a mesma pasta do seu `index.html`.
2. No `index.html`, logo depois da referência ao `style.css`, acrescente:

```html
<link rel="stylesheet" href="desempenho.css">
```

3. Carregue o módulo ANTES de `app.js`. No HTML original, o fim do arquivo fica assim:

```html
<script src="desempenho.js"></script>
<script src="app.js"></script>
</body>
</html>
```

Se você usa a versão com `bootstrap.js`, mantenha o bootstrap e use:

```html
<script src="desempenho.js"></script>
<script src="bootstrap.js" defer></script>
```

4. No `app.js`, procure a atribuição `currentProfile = profile;`. Imediatamente depois dela, insira:

```js
window.CDEDesempenho?.setSession(db, user, profile);
```

O trecho completo será:

```js
currentProfile = profile;
window.CDEDesempenho?.setSession(db, user, profile);
document.getElementById('login-view').classList.add('hidden');
```

Referências dos arquivos recebidos: `index.html`, linha 7 (CSS) e linha 340 (script); `app.js`, linha 149 (perfil). Na versão com ajustes técnicos, `app.js`, linha 196; `index.html`, linha 332 (bootstrap). Procure os trechos, pois suas alterações anteriores mudam a numeração.

Se sua versão tem `function showLoginView()`, você também pode inserir na primeira linha da função:

```js
window.CDEDesempenho?.clear();
```

O próprio módulo já limpa sua área ao receber `SIGNED_OUT` do Supabase. Esse último gancho também cobre a volta ao login por outras rotas do seu app.

Publique os arquivos atualizados no mesmo endereço do PDI. Atualize a página após a publicação. O módulo usa a conexão Supabase já existente; nenhuma chave adicional é necessária.

## Regras do primeiro módulo

| Perfil | Permissões |
| --- | --- |
| Colaborador com `position = PCP` | Registrar os próprios m² e pedidos uma vez no dia; consultar seus lançamentos. |
| Supervisor | Dashboard e ranking do próprio setor; selecionar PCP do próprio setor, consultar e corrigir registros existentes com justificativa. |
| Gerente | Somente filtros, dashboard e ranking do próprio setor. Sem coleta, correção ou listas operacionais. |
| Diretoria / Master | Somente filtros, dashboard e ranking globais. Sem coleta ou correção, inclusive para Master. |
| Outros colaboradores | Continuam com seu PDI, sem formulário PCP. |

A posição aceita `PCP`, `pcp` e espaços nas pontas. Expressões diferentes, como `Auxiliar de PCP`, não são tratadas como PCP automaticamente. A autoridade gerencial vem de `role`/`is_master`, não de um texto como “Gerente” no cargo.

- **M² Salvo Dia**: quantidade de área salva no dia, informada pelo PCP. Aceita zero ou valor positivo com até três casas decimais. Use `12,350` ou `12.350`, sem separador de milhar. Limite técnico: menor que 1 bilhão de m².
- **Pedidos**: números separados por vírgula, espaço, ponto e vírgula ou linha. Até 200 números distintos, de 1 a 20 dígitos; zeros à esquerda são preservados. Valor positivo de m² exige ao menos um pedido. Com zero, a lista pode ficar vazia.
- Os pedidos servem como referência para auditoria. Esta versão não está conectada ao ERP para confirmar que existem e não calcula os m² a partir dos itens do pedido.
- Um registro por PCP por data, garantido por restrição única no banco. O calendário e o “hoje” vêm do servidor, em `America/Manaus` (UTC−4).
- O PCP não edita, exclui ou lança dias anteriores. O supervisor corrige um registro já criado; não cadastra em nome de outra pessoa nesta etapa.
- Correção: justificativa de 10 a 300 caracteres, preservação do cadastro original e nova revisão. Não permite salvar sem alteração dos m² ou pedidos.
- Se outra pessoa corrigir antes de você salvar, o aplicativo pede atualização. Não sobrescreve silenciosamente a revisão carregada.
- Histórico operacional começa recolhido, com 30 itens por página, para colaborador/supervisão. Gerência/Diretoria têm somente dashboards e filtros; logs permanecem preservados no banco.
- A auditoria usa o período da **data da alteração**, enquanto o histórico usa a **data do resultado diário**. Ex.: uma correção em dezembro de um resultado de novembro aparece no log de dezembro e no histórico de novembro.
- Esse campo não altera a pontuação, metas ou ranking do PDI. Caixa agora tem formulário próprio; suas regras estão em LEIA-ME-CAIXA.md. Outros cargos ficam para uma próxima etapa.

## Dashboard e ranking — supervisão para cima

Ao abrir **Desempenho**, gerência/Diretoria veem apenas filtros e dashboard. A supervisão também tem o histórico operacional recolhível. O período inicial é do primeiro dia do mês até hoje (Manaus). O filtro vale simultaneamente para indicadores, ranking e histórico. Os logs usam o mesmo filtro, pela data de alteração.

O dashboard mostra:

- **Total de m² salvos**: soma dos valores atuais de todos os lançamentos visíveis no período.
- **PCPs com registro**: quantidade de PCPs distintos que registraram algo no recorte, incluindo registro de 0 m². Não é uma medida de presença nem de todos os PCPs cadastrados.
- **Lançamentos no período**: número de resultados diários; revisões não aumentam essa quantidade.
- **Ranking**: total por PCP em ordem decrescente de m², com barras horizontais e participação percentual no total filtrado. Nomes vêm do cadastro diário mais recente do PCP dentro do recorte. Homônimos são agrupados por ID, não pelo nome.

Empates compartilham posição (1º, 1º, 2º). A ordem visual entre empatados usa nome e ID para estabilidade. PCP sem lançamento não entra no ranking; quem registrou zero entra com zero. Em período vazio, os cartões mostram zero e o ranking explica a ausência de registros.

**Cálculo:** `SUM(m2_saved)` agrupado por `pcp_id` na tabela diária, com datas inicial/final inclusivas. O log não participa da soma. Uma correção substitui o valor anterior; por exemplo, corrigir 10 m² para 12 m² faz o resultado passar a 12 m², não a 22 m². A participação é `total_PCP / total_filtrado × 100`, arredondada a duas casas. A barra compara cada PCP com o maior total do filtro; o percentual escrito compara com o total. Com total zero, os dois percentuais ficam em zero. Percentuais arredondados podem não somar exatamente 100%.

A agregação usa `numeric` no PostgreSQL e considera **todos** os registros autorizados no período, mesmo com histórico paginado ou mais de mil lançamentos. O ranking também é paginado, com 30 PCPs por página; o total não muda ao navegar. Selecionar um único PCP restringe também o ranking a ele; escolha “Todos os PCPs do meu acesso” para comparar a equipe.

Supervisor e gerente veem apenas registros do seu setor; Diretoria/Master veem todos os setores. A função consulta os dados com RLS e recusa colaboradores comuns, inclusive PCPs. Não usa privilégios do dono da função nem abre acesso aos logs para a supervisão.

Novos resultados entram ao abrir a aba, consultar filtros ou clicar em **Atualizar dados**. Após salvar uma correção nesta tela, o dashboard é recarregado automaticamente. Não há atualização por streaming em segundo plano. Se o dashboard falhar, mostra erro em vez de apresentar zero como resultado calculado.

## Auditoria e proteção

O banco registra cadastro, correção e exclusão administrativa: autor, papel, horário, valores/pedidos anteriores e posteriores, justificativa e identificação da operação no banco. Uma alteração que falha ou é desfeita não gera evento persistente.

PCP e supervisor não recebem o painel de logs e não podem ler a tabela de auditoria pela API. A justificativa também não tem permissão de leitura na tabela diária; só é enviada para corrigir e é consultada no log gerencial. Nenhum usuário do app, incluindo gerente/Diretoria, pode alterar ou apagar os logs pela API.

Foram encontradas permissões antigas que permitiam a qualquer autenticado atualizar campos de acesso em `profiles`. O novo gatilho impede autoatribuição de `role`, `is_master`, `is_professor`, `position`, `sector` e troca de identidade. O usuário mantém a edição dos próprios dados pessoais. Gerentes podem cadastrar/editar colaboradores comuns do próprio setor sem promovê-los a gestores ou professores; Diretoria/Master e os serviços administrativos mantêm a administração. Nenhum perfil existente foi reclassificado.

A regra vale também para outros aplicativos que usam a mesma tabela `profiles`, como o Academy. Rotas antigas que tentem alterar acesso com conta comum devem usar uma conta gestora autorizada. Credenciais privilegiadas do banco/serviço continuam sendo administrativas e nunca devem ser entregues ao navegador.

PCP, data, nome e setor de origem ficam preservados no registro. A auditoria e a supervisão respeitam esse setor histórico e o setor atual do gestor. Um gestor de outro setor não recebe esses registros. Não há exclusão de lançamentos no aplicativo.

Objetos criados:

- `public.pdi_pcp_daily`: resultados diários e revisões.
- `public.pdi_performance_audit`: histórico de alterações, com acesso por RLS.
- `public.pdi_pcp_dashboard(date,date,uuid)`: agregação e ranking somente para supervisão/gestão, com escopo por setor e filtros.
- `public.pdi_desempenho_context()`: data e permissões do usuário autenticado.
- `pdi_performance_private`: funções auxiliares e gatilhos sem exposição pública de execução.
- `pdi_guard_profile_authority`: proteção dos campos de autoridade em `profiles`.

O SQL é transacional e pode ser reaplicado nesta versão. Não o use como migração automática para futuras versões com estrutura diferente. Para retirar apenas a interface, remova os ganchos e referências ao módulo; mantenha o banco para preservar o histórico. Não apague as tabelas para “desinstalar”.

## Validação

- 56 verificações em PostgreSQL 17 local com dados fictícios: duplicidade, papéis, setores, alteração de acesso, valores, pedidos, auditoria e concorrência.
- 53 verificações da interface em DOM simulado: entrada decimal, duplicidade de envio, pedidos, correção, logs, escape de nomes, logout, paginação e falha de conexão.
- Dashboard verificado com mais de 1.000 linhas, casas decimais, filtros, setores, empates, zeros, correções e permissões em PostgreSQL local.
- Instalação e dashboard verificados no Supabase real por testes transacionais com rollback.
- Reaplicação do SQL testada no banco local.
- JS e CSS verificados sintaticamente; formulários usam colunas flexíveis e se reorganizam nos pontos de 760 px e 480 px, sem tabelas largas.
- Não foi possível testar visualmente em navegador/celular nesta sessão. O login completo e o comportamento visual no PDI publicado precisam da conferência após a integração. Nenhuma senha real de usuário foi usada nos testes.

A checagem de segurança do Supabase após a instalação não apontou novos avisos nos objetos do módulo. Permanecem avisos anteriores sobre funções legadas (`recalculate_supervisor_goals`, `get_goal_assignees`, `handle_new_user`, `is_supervisor`) e proteção de senhas vazadas; não foram modificadas nesta entrega. Referências: [search_path](https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable), [funções públicas](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [senhas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

### Reproduzir os testes em ambiente local

Não execute o fixture em produção. Ele contém perfis fictícios e permissões antigas para reproduzir a proteção.

```sh
docker run --rm -d --name cde-pcp-qa --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17
docker exec cde-pcp-qa createdb -U postgres pdiqa
docker exec -i cde-pcp-qa psql -U postgres -d pdiqa -v ON_ERROR_STOP=1 < testes/fixture.sql
docker exec -i cde-pcp-qa psql -U postgres -d pdiqa -v ON_ERROR_STOP=1 < desempenho-pcp.sql
docker exec -i cde-pcp-qa psql -U postgres -d pdiqa -v ON_ERROR_STOP=1 < dashboard-pcp.sql
docker exec -i cde-pcp-qa psql -U postgres -d pdiqa -v ON_ERROR_STOP=1 < testes/dashboard.sql
python3 testes/banco.py
```

Para o DOM simulado, instale `linkedom@0.18.12` somente no ambiente de desenvolvimento e execute `node testes/interface.mjs`. Também aceita `CDE_LINKEDOM_MODULE` apontando para o módulo ESM instalado. O PDI em produção não usa essa dependência.

Após a integração, confira com PCP: cadastro de hoje, segunda tentativa bloqueada e consulta do resultado. Com supervisor: total e ranking de seu setor, filtros, correção atualizando o dashboard e ausência de log. Com gerente/Diretoria: somente filtros e dashboards, sem formulário, correção ou listagem operacional. Confira a tela em 320, 375, 768 e 1280 px e por teclado.
