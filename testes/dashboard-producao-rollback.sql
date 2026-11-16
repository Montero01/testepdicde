-- Conferência no projeto real, isolada em transação desfeita ao final.
begin;
do $$ declare p uuid; s uuid; g uuid; d date; sec text; begin
 select id,sector into p,sec from public.profiles where lower(trim(position))='pcp' and role in ('employee','colaborador') and not coalesce(is_master,false) limit 1;
 select id into s from public.profiles where role='supervisor' and sector=sec limit 1;
 select id into g from public.profiles where role='gerente' and sector=sec limit 1;
 select v::date into d from generate_series('2000-01-01'::date,'2000-01-31'::date,interval '1 day') v
   where not exists(select 1 from public.pdi_pcp_daily x where x.work_date=v::date) limit 1;
 if p is null or s is null or g is null or d is null then raise exception 'Condição de teste indisponível'; end if;
 perform set_config('cde_test.pcp',p::text,true); perform set_config('cde_test.sup',s::text,true); perform set_config('cde_test.ger',g::text,true); perform set_config('cde_test.day',d::text,true);
 insert into public.pdi_pcp_daily(pcp_id,work_date,m2_saved,order_numbers) values(p,d,1.234,array['000001']);
end $$;
set local role authenticated;
do $$ declare j jsonb; d date:=current_setting('cde_test.day')::date; p uuid:=current_setting('cde_test.pcp')::uuid; begin
 perform set_config('request.jwt.claim.sub',p::text,true);
 begin
   perform public.pdi_pcp_dashboard(d,d,p); raise exception 'PCP acessou dashboard gerencial';
 exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claim.sub',current_setting('cde_test.sup'),true);
 j:=public.pdi_pcp_dashboard(d,d,p);
 if (j->>'total_m2')::numeric<>1.234 or (j->>'entry_count')::integer<>1 or (j->'ranking'->0->>'place')::integer<>1 then raise exception 'Dashboard supervisor divergente'; end if;
 if exists(select 1 from public.pdi_performance_audit where pcp_id=p) then raise exception 'Supervisor lê logs'; end if;
 update public.pdi_pcp_daily set m2_saved=2.345,edit_reason='TESTE TRANSACIONAL DESFEITO AO FINAL' where pcp_id=p and work_date=d;
 j:=public.pdi_pcp_dashboard(d,d,p);
 if (j->>'total_m2')::numeric<>2.345 or (j->>'entry_count')::integer<>1 then raise exception 'Correção duplicou resultado'; end if;
 perform set_config('request.jwt.claim.sub',current_setting('cde_test.ger'),true);
 j:=public.pdi_pcp_dashboard(d,d,p);
 if (j->>'total_m2')::numeric<>2.345 or (j->'ranking'->0->>'share_percent')::numeric<>100 then raise exception 'Dashboard gerente divergente'; end if;
end $$;
rollback;
select 'dashboard_validado_com_rollback' as resultado,
 (select prosecdef from pg_proc where oid='public.pdi_pcp_dashboard(date,date,uuid)'::regprocedure) as executa_com_privilegios_do_dono;
