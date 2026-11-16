# Atualização de acesso — somente dashboards para gestão

**Layout atualizado:** consulte LEIA-ME-LAYOUT.md e a pasta demonstracao. A nova interface usa laranja CDE, navegação por módulo e atalhos de período. Publique os três arquivos de interface juntos; os ganchos e permissões permanecem iguais.

Regra solicitada em 16/11/2026, aplicada às abas **Desempenho / PCP e Caixa**:

| Acesso | O que aparece | O que pode gravar |
| --- | --- | --- |
| Colaborador PCP/Caixa | Seu formulário e histórico | O próprio dia, uma vez; sem edição posterior. |
| Supervisor | Dashboard e operação do próprio setor | Corrigir lançamentos existentes do setor, com justificativa; no Caixa, substituir/retirar o PDF. Se tiver cargo PCP/Caixa, também pode registrar o próprio dia. |
| Gerente | Filtros e dashboards do setor | Nada nos módulos de desempenho. |
| Diretoria / Master | Filtros e dashboards globais | Nada nos módulos de desempenho. |

Nas telas da gerência, Diretoria e Master não aparecem formulários, listagens operacionais, correções nem painéis de logs. A interface desses perfis consulta somente a agregação dos dashboards e os nomes necessários aos filtros. Os logs e PDFs anteriores continuam preservados no banco, com a permissão de leitura de auditoria já restrita à gestão autorizada; não foram apagados nem tornados públicos.

Master é tratado como consulta, inclusive quando `profiles.role` for `supervisor` ou `employee`. Ter o cargo textual `PCP` ou `Op. de Caixa` não libera coleta para um gerente/diretor. As regras usam o papel e a flag de acesso, além do cargo do formulário.

O banco agora bloqueia INSERT/UPDATE pelos perfis de gestão, reserva/envio de PDF e uso de anexos pendentes por esses perfis. Não é somente uma mudança visual. Supervisores continuam limitados ao próprio setor; não cadastram resultados em nome de outro colaborador. Não há exclusão operacional.

A mudança é exclusiva do desempenho. Não altera as funções de gestão de perfis, metas ou outras partes do PDI/Academy.

## Instalar a interface

O Supabase do PDI já recebeu a atualização. Publique os arquivos atuais `desempenho.js`, `desempenho-caixa.js` e `desempenho.css` na pasta do PDI e recarregue a página. Não muda o gancho no `app.js`. Para uma instalação nova, siga o guia HTML do pacote.

O arquivo `desempenho-acessos-consulta.sql` é a atualização aditiva para bases que já possuem PCP e Caixa; não altera valores, perfis ou arquivos existentes. Em outro projeto novo, a ordem completa é `desempenho-pcp.sql`, `dashboard-pcp.sql`, `desempenho-caixa.sql`, `desempenho-acessos-consulta.sql`.

## Verificação desta atualização

- 84 verificações locais de acesso, incluindo gestores com cargo operacional, Master com papel de supervisor, coleta do colaborador, correção pela supervisão, bloqueio gerencial de PDF e manutenção dos dashboards.
- 53 verificações da interface PCP e 43 da interface Caixa: gestão sem coleta, histórico, logs ou consulta à lista operacional; supervisão com correções e colaboradores com formulário.
- No Supabase real, testes transacionais confirmaram o bloqueio gerencial, manutenção dos dashboards, coleta da operadora e correção pela supervisão. Todos os dados fictícios foram desfeitos por rollback.
- Reaplicação do patch testada localmente; nenhum novo aviso de segurança dos auxiliares na checagem Supabase.
- Sem teste visual em navegador/celular nesta sessão. Após publicar, confira os quatro acessos no PDI real.

Para reproduzir a matriz local, crie um contêiner `cde-consulta-qa` com PostgreSQL 17 e banco `pdiqa`; aplique `testes/fixture.sql`, `desempenho-pcp.sql`, `testes/caixa-storage-fixture.sql`, `desempenho-caixa.sql`, `dashboard-pcp.sql` e `desempenho-acessos-consulta.sql`; execute `python3 testes/acessos-consulta.py`. Não use fixtures no projeto real.
