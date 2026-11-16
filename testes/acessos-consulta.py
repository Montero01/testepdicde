"""Matriz de acesso: somente contêiner PostgreSQL local com fixtures."""
import subprocess,json
BASE=['docker','--host=unix:///var/run/docker.sock','exec','-i','cde-consulta-qa','psql','-U','postgres','-d','pdiqa','-X','-At','-v','ON_ERROR_STOP=1']
checks=0
def sql(q,uid=None,error=None,expect=None):
 global checks
 pre=f"begin;set local role authenticated;select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-{uid:012d}',true);" if uid else 'begin;'
 p=subprocess.run(BASE,input=pre+q+';commit;',text=True,capture_output=True)
 if error:assert p.returncode and error in p.stderr,(q,p.stdout,p.stderr)
 else:
  assert p.returncode==0,(q,p.stdout,p.stderr)
  if expect is not None:assert expect in p.stdout.splitlines(),(expect,p.stdout,p.stderr)
 checks+=1;return p.stdout
sql("""insert into public.profiles(id,full_name,role,sector,position,is_master) values
('00000000-0000-0000-0000-000000000024','Gerente PCP','gerente','PRODUÇÃO','PCP',false),
('00000000-0000-0000-0000-000000000025','Gerente Caixa','gerente','ADMINISTRATIVO','Op. de Caixa',false),
('00000000-0000-0000-0000-000000000026','Supervisor Master','supervisor','PRODUÇÃO','PCP',true),
('00000000-0000-0000-0000-000000000027','Diretor PCP','diretor','PRODUÇÃO','PCP',false),
('00000000-0000-0000-0000-000000000028','Master com cargo PCP','employee','PRODUÇÃO','PCP',true)""")
# Colaboradores continuam registrando o próprio dia.
sql("insert into public.pdi_pcp_daily(pcp_id,m2_saved,order_numbers) values(auth.uid(),1,array['001'])",1)
sql("insert into public.pdi_cash_daily(cashier_id,result_cents,cash_cents) values(auth.uid(),10000,10000)",20)
for uid in [4,6,9,24,25,26,27,28]:
 sql("select public.pdi_desempenho_context()->>'dashboard_only'",uid,expect='true')
 sql("select public.pdi_desempenho_context()->>'can_collect'",uid,expect='false')
 sql("select public.pdi_cash_context()->>'can_correct'",uid,expect='false')
 sql("select pdi_performance_private.can_collect_performance()",uid,expect='f')
 sql("update public.pdi_pcp_daily set m2_saved=9,edit_reason='Tentativa fora da supervisão' returning id",uid,expect='UPDATE 0')
 sql("update public.pdi_cash_daily set result_cents=20000,cash_cents=20000,edit_reason='Tentativa fora da supervisão' returning id",uid,expect='UPDATE 0')
 sql("select public.pdi_cash_reserve_pdf(gen_random_uuid(),'00000000-0000-0000-0000-000000000020',pdi_performance_private.today_manaus(),'teste.pdf',20)",uid,error='não podem enviar')
for uid in [24,26,27,28]:
 sql("insert into public.pdi_pcp_daily(pcp_id,m2_saved) values(auth.uid(),0)",uid,error='somente de consulta')
sql("insert into public.pdi_cash_daily(cashier_id,result_cents) values(auth.uid(),0)",25,error='somente de consulta')
sql("select public.pdi_desempenho_context()->>'can_correct'",3,expect='true')
sql("select public.pdi_desempenho_context()->>'dashboard_only'",3,expect='false')
sql("select public.pdi_cash_context()->>'can_correct'",22,expect='true')
sql("update public.pdi_pcp_daily set m2_saved=2,edit_reason='Conferência do supervisor' returning revision",3,expect='2')
sql("update public.pdi_cash_daily set result_cents=11000,cash_cents=11000,edit_reason='Conferência do supervisor' returning revision",22,expect='2')
sql("update public.pdi_cash_daily set result_cents=12000,cash_cents=12000,edit_reason='Supervisor de outro setor' returning id",3,expect='UPDATE 0')
sql("update public.pdi_pcp_daily set m2_saved=3,edit_reason='Colaborador tentando editar' returning id",1,expect='UPDATE 0')
sql("update public.pdi_cash_daily set result_cents=12000,cash_cents=12000,edit_reason='Colaborador tentando editar' returning id",20,expect='UPDATE 0')
sql("select public.pdi_pcp_dashboard(current_date-1,current_date+1)->>'total_m2'",4,expect='2')
sql("select public.pdi_cash_dashboard(current_date-1,current_date+1)->>'result_cents'",25,expect='11000')
sql("select public.pdi_cash_dashboard(current_date-1,current_date+1)->>'result_cents'",6,expect='11000')
sql("select count(*) from public.pdi_performance_audit",4,expect='2')
sql("select count(*) from public.pdi_cash_audit",25,expect='2')
sql("select count(*) from public.pdi_cash_audit",22,expect='0')
# Gerência não pode utilizar uma reserva feita pela supervisão.
out=sql("select public.pdi_cash_reserve_pdf((select id from public.pdi_cash_daily limit 1),'00000000-0000-0000-0000-000000000020',pdi_performance_private.today_manaus(),'teste.pdf',20)",22)
f=json.loads(next(s for s in out.splitlines() if s.startswith('{')))
sql(f"select pdi_performance_private.cash_file_can_upload('{f['path']}')",25,expect='f')
sql(f"insert into storage.objects(bucket_id,name,metadata) values('pdi-cash-pdfs','{f['path']}','{{\"size\":20,\"mimetype\":\"application/pdf\"}}')",25,error='row-level security')
sql(f"insert into storage.objects(bucket_id,name,metadata) values('pdi-cash-pdfs','{f['path']}','{{\"size\":20,\"mimetype\":\"application/pdf\"}}')",22)
sql(f"update public.pdi_cash_daily set pdf_file_id='{f['id']}',edit_reason='PDF conferido pela supervisão' returning revision",22,expect='3')
sql("select count(*) from public.pdi_cash_audit",25,expect='3')
print(f'{checks} verificações da matriz de acesso aprovadas.')
