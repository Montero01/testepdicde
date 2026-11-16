-- Projeto real: não altera perfis; lançamentos fictícios desfeitos ao final.
begin;
do $$ declare p uuid; c uuid; s uuid; gp uuid; gc uuid; x uuid:=gen_random_uuid(); y uuid:=gen_random_uuid(); d date; begin
 select id into p from public.profiles where lower(trim(position))='pcp' and role in ('employee','colaborador') limit 1;
 select id into c from public.profiles where pdi_performance_private.is_cash_position(position) and role in ('employee','colaborador') limit 1;
 select id into s from public.profiles where role='supervisor' and sector=(select sector from public.profiles where id=p) and not coalesce(is_master,false) limit 1;
 select id into gp from public.profiles where role='gerente' and sector=(select sector from public.profiles where id=p) limit 1;
 select id into gc from public.profiles where (role='gerente' and sector=(select sector from public.profiles where id=c)) or coalesce(is_master,false) limit 1;
 select v::date into d from generate_series('2000-01-01'::date,'2000-01-31'::date,interval '1 day') v where not exists(select 1 from public.pdi_pcp_daily where work_date=v::date) and not exists(select 1 from public.pdi_cash_daily where work_date=v::date) limit 1;
 if p is null or c is null or s is null or gp is null or gc is null or d is null then raise exception 'Perfis de teste indisponíveis'; end if;
 perform set_config('ro.pcp',p::text,true);perform set_config('ro.cash',c::text,true);perform set_config('ro.sup',s::text,true);perform set_config('ro.gp',gp::text,true);perform set_config('ro.gc',gc::text,true);perform set_config('ro.x',x::text,true);perform set_config('ro.y',y::text,true);perform set_config('ro.day',d::text,true);
 insert into public.pdi_pcp_daily(id,pcp_id,work_date,m2_saved,order_numbers) values(x,p,d,1,array['000001']);
 insert into public.pdi_cash_daily(id,cashier_id,work_date,result_cents,cash_cents) values(y,c,d,10000,10000);
end $$;
set local role authenticated;
do $$ declare n int; j jsonb; x uuid:=current_setting('ro.x')::uuid; y uuid:=current_setting('ro.y')::uuid; d date:=current_setting('ro.day')::date; begin
 perform set_config('request.jwt.claim.sub',current_setting('ro.gp'),true);
 j:=public.pdi_desempenho_context();
 if not (j->>'dashboard_only')::bool or (j->>'can_correct')::bool or (j->>'can_collect')::bool then raise exception 'Contexto gerencial PCP incorreto'; end if;
 update public.pdi_pcp_daily set m2_saved=9,edit_reason='TENTATIVA GERENCIAL BLOQUEADA' where id=x;
 get diagnostics n=row_count;if n<>0 then raise exception 'Gerente editou PCP'; end if;
 if (public.pdi_pcp_dashboard(d,d,current_setting('ro.pcp')::uuid)->>'total_m2')::numeric<>1 then raise exception 'Dashboard gerencial PCP indisponível'; end if;
 perform set_config('request.jwt.claim.sub',current_setting('ro.gc'),true);
 j:=public.pdi_cash_context();if not (j->>'dashboard_only')::bool or (j->>'can_correct')::bool or (j->>'can_collect')::bool then raise exception 'Contexto gerencial Caixa incorreto'; end if;
 update public.pdi_cash_daily set result_cents=20000,cash_cents=20000,edit_reason='TENTATIVA GERENCIAL BLOQUEADA' where id=y;
 get diagnostics n=row_count;if n<>0 then raise exception 'Gerência/Diretoria editou Caixa'; end if;
 begin
  perform public.pdi_cash_reserve_pdf(y,current_setting('ro.cash')::uuid,d,'teste.pdf',20);raise exception 'Gestão reservou PDF';
 exception when insufficient_privilege then null; end;
 if (public.pdi_cash_dashboard(d,d,current_setting('ro.cash')::uuid)->>'result_cents')::bigint<>10000 then raise exception 'Dashboard gerencial Caixa indisponível'; end if;
 select count(*) into n from public.pdi_cash_audit where entry_id=y;if n<>1 then raise exception 'Log alterado por tentativa bloqueada'; end if;
 perform set_config('request.jwt.claim.sub',current_setting('ro.sup'),true);
 if not (public.pdi_desempenho_context()->>'can_correct')::bool then raise exception 'Supervisão perdeu correção'; end if;
 update public.pdi_pcp_daily set m2_saved=2,edit_reason='TESTE DA SUPERVISÃO, DESFEITO AO FINAL' where id=x;
 get diagnostics n=row_count;if n<>1 then raise exception 'Supervisor não corrige'; end if;
 perform set_config('request.jwt.claim.sub',current_setting('ro.cash'),true);
 if not (public.pdi_cash_context()->>'can_collect')::bool then raise exception 'Operadora perdeu coleta'; end if;
 update public.pdi_cash_daily set result_cents=20000,cash_cents=20000,edit_reason='Tentativa da colaboradora' where id=y;
 get diagnostics n=row_count;if n<>0 then raise exception 'Operadora editou fechamento'; end if;
end $$;
rollback;
select 'consulta_gerencial_e_correcao_supervisao_validadas_com_rollback' as resultado;
