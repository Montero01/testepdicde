-- Dados fictícios: executar somente no PostgreSQL local com fixture.sql.
begin;
insert into public.profiles(id,full_name,role,sector,position) values('00000000-0000-0000-0000-000000000011','PCP zero','employee','PRODUÇÃO','PCP');
insert into public.pdi_pcp_daily(pcp_id,work_date,m2_saved,order_numbers)
 select '00000000-0000-0000-0000-000000000001','2026-01-01'::date+i,1.001,array['000001'] from generate_series(0,39) i;
insert into public.pdi_pcp_daily(pcp_id,work_date,m2_saved,order_numbers)
 select '00000000-0000-0000-0000-000000000001','2020-01-01'::date+i,0.001,array['000002'] from generate_series(0,1100) i;
insert into public.pdi_pcp_daily(pcp_id,work_date,m2_saved,order_numbers) values
 ('00000000-0000-0000-0000-000000000002','2026-01-01',12.345,array['000003']),
 ('00000000-0000-0000-0000-000000000007','2026-01-01',1000.999,array['000004']),
 ('00000000-0000-0000-0000-000000000011','2026-01-02',0,'{}'),
 ('00000000-0000-0000-0000-000000000001','2030-01-01',500,array['000005']);
set local role authenticated;
do $$ declare j jsonb; begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 begin
   perform public.pdi_pcp_dashboard('2026-01-01','2026-02-28');
   raise exception 'PCP conseguiu consultar dashboard';
 exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
 j:=public.pdi_pcp_dashboard('2026-01-01','2026-02-28');
 if (j->>'total_m2')::numeric<>52.385 or (j->>'entry_count')::int<>42 or (j->>'pcp_count')::int<>3 then raise exception 'Soma decimal, contagem ou escopo divergente: %',j; end if;
 if j->'ranking'->0->>'pcp_id'<>'00000000-0000-0000-0000-000000000001' then raise exception 'Ordem do ranking divergente'; end if;
 if (j->'ranking'->2->>'total_m2')::numeric<>0 then raise exception 'PCP com registro zero ausente'; end if;
 if exists(select 1 from public.pdi_performance_audit) then raise exception 'Supervisor recebeu logs'; end if;
 j:=public.pdi_pcp_dashboard('2020-01-01','2026-02-28');
 if (j->>'total_m2')::numeric<>53.486 or (j->>'entry_count')::int<>1143 then raise exception 'Agregação truncada acima de 1000 linhas'; end if;
 j:=public.pdi_pcp_dashboard('2026-01-01','2026-02-28','00000000-0000-0000-0000-000000000002');
 if (j->>'total_m2')::numeric<>12.345 or (j->>'pcp_count')::int<>1 then raise exception 'Filtro PCP divergente'; end if;
 j:=public.pdi_pcp_dashboard('2026-01-01','2026-02-28','00000000-0000-0000-0000-000000000007');
 if (j->>'total_m2')::numeric<>0 or j->'ranking'<>'[]'::jsonb then raise exception 'PCP de outro setor exposto'; end if;
 j:=public.pdi_pcp_dashboard('2026-01-01','2026-01-01');
 if (j->>'total_m2')::numeric<>13.346 or (j->>'entry_count')::int<>2 then raise exception 'Intervalo de um dia divergente'; end if;
 j:=public.pdi_pcp_dashboard('2026-01-02','2026-01-02','00000000-0000-0000-0000-000000000011');
 if (j->'ranking'->0->>'bar_percent')::numeric<>0 or (j->'ranking'->0->>'share_percent')::numeric<>0 then raise exception 'Divisão por zero'; end if;
 j:=public.pdi_pcp_dashboard('2010-01-01','2010-01-31');
 if (j->>'total_m2')::numeric<>0 or (j->>'entry_count')::int<>0 or j->'ranking'<>'[]'::jsonb then raise exception 'Período vazio divergente'; end if;
 begin
   perform public.pdi_pcp_dashboard('2026-02-01','2026-01-01'); raise exception 'Datas invertidas aceitas';
 exception when invalid_parameter_value then null; end;
 begin
   perform public.pdi_pcp_dashboard(null,'2026-01-01'); raise exception 'Data vazia aceita';
 exception when invalid_parameter_value then null; end;
 begin
   perform public.pdi_pcp_dashboard('-infinity','infinity'); raise exception 'Data infinita aceita';
 exception when invalid_parameter_value then null; end;
 -- Correção substitui o valor, sem somar o evento da auditoria como resultado.
 update public.pdi_pcp_daily set m2_saved=40.040,edit_reason='Conferência dos pedidos confirmada' where pcp_id='00000000-0000-0000-0000-000000000002' and work_date='2026-01-01';
 j:=public.pdi_pcp_dashboard('2026-01-01','2026-02-28');
 if (j->>'total_m2')::numeric<>80.080 or (j->>'entry_count')::int<>42 then raise exception 'Correção duplicou contagem'; end if;
 if (j->'ranking'->0->>'place')::int<>1 or (j->'ranking'->1->>'place')::int<>1 or (j->'ranking'->2->>'place')::int<>2 then raise exception 'Empate divergente'; end if;
 if (j->'ranking'->0->>'share_percent')::numeric<>50 or (j->'ranking'->1->>'share_percent')::numeric<>50 then raise exception 'Participação percentual divergente'; end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',true);
 j:=public.pdi_pcp_dashboard('2026-01-01','2026-02-28');
 if (j->>'total_m2')::numeric<>80.080 then raise exception 'Escopo gerente divergente'; end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',true);
 j:=public.pdi_pcp_dashboard('2026-01-01','2026-02-28');
 if (j->>'total_m2')::numeric<>1000.999 then raise exception 'Gerente comercial não isolado'; end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000006',true);
 j:=public.pdi_pcp_dashboard('2026-01-01','2026-02-28');
 if (j->>'total_m2')::numeric<>1081.079 or (j->>'pcp_count')::int<>4 then raise exception 'Diretoria sem acesso global'; end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000009',true);
 j:=public.pdi_pcp_dashboard('2026-01-01','2026-02-28');
 if (j->>'total_m2')::numeric<>1081.079 then raise exception 'Master sem acesso global'; end if;
 perform set_config('request.jwt.claim.sub','',true);
 begin
   perform public.pdi_pcp_dashboard('2026-01-01','2026-02-28'); raise exception 'Sessão vazia aceita';
 exception when insufficient_privilege then null; end;
end $$;
set local role anon;
do $$ begin
 begin
   perform public.pdi_pcp_dashboard('2026-01-01','2026-02-28'); raise exception 'Anon executa dashboard';
 exception when insufficient_privilege then null; end;
end $$;
rollback;
select 'Dashboard aprovado: precisão decimal, mais de 1000 linhas, filtros, correção, empates, zeros e escopo por papel/setor.' as resultado;
