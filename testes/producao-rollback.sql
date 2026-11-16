-- Verificação transacional. Nenhum lançamento de teste permanece no projeto.
begin;
do $$ declare p public.profiles%rowtype; s uuid; g uuid; begin
 select * into p from public.profiles where lower(trim(position))='pcp' and role in ('employee','colaborador') and not coalesce(is_master,false) limit 1;
 if p.id is null then raise exception 'PCP de teste indisponível'; end if;
 select id into s from public.profiles where role='supervisor' and sector=p.sector limit 1;
 select id into g from public.profiles where role='gerente' and sector=p.sector limit 1;
 if s is null or g is null then raise exception 'Gestão do setor indisponível'; end if;
 perform set_config('cde_test.pcp',p.id::text,true);
 perform set_config('cde_test.sup',s::text,true);
 perform set_config('cde_test.ger',g::text,true);
end $$;
set local role authenticated;
do $$ declare v uuid; n integer; before_value numeric; begin
 perform set_config('request.jwt.claim.sub',current_setting('cde_test.pcp'),true);
 if not (public.pdi_desempenho_context()->>'is_pcp')::boolean then raise exception 'Contexto PCP incorreto'; end if;
 insert into public.pdi_pcp_daily(pcp_id,m2_saved,order_numbers) values(auth.uid(),1.234,array['000001']) returning id into v;
 perform set_config('cde_test.entry',v::text,true);
 begin
   insert into public.pdi_pcp_daily(pcp_id,m2_saved) values(auth.uid(),0);
   raise exception 'Falha: duplicidade permitida';
 exception when unique_violation then null; end;
 begin
   update public.profiles set is_master=true where id=auth.uid();
   raise exception 'Falha: elevação de acesso permitida';
 exception when insufficient_privilege then null; end;
 if exists(select 1 from public.pdi_performance_audit) then raise exception 'Falha: PCP lê logs'; end if;
 begin
   perform edit_reason from public.pdi_pcp_daily;
   raise exception 'Falha: justificativa exposta ao PCP';
 exception when insufficient_privilege then null; end;
 update public.pdi_pcp_daily set m2_saved=9,edit_reason='Tentativa indevida' where id=v;
 get diagnostics n=row_count;
 if n<>0 then raise exception 'Falha: PCP altera registro'; end if;
 perform set_config('request.jwt.claim.sub',current_setting('cde_test.sup'),true);
 if (public.pdi_desempenho_context()->>'can_view_logs')::boolean then raise exception 'Falha: supervisor vê auditoria'; end if;
 update public.pdi_pcp_daily set m2_saved=2.345,edit_reason='TESTE TRANSACIONAL, SEM DADOS REAIS' where id=v and revision=1;
 get diagnostics n=row_count;
 if n<>1 then raise exception 'Falha: supervisor não corrige'; end if;
 if exists(select 1 from public.pdi_performance_audit) then raise exception 'Falha: supervisor lê logs'; end if;
 perform set_config('request.jwt.claim.sub',current_setting('cde_test.ger'),true);
 if not (public.pdi_desempenho_context()->>'can_view_logs')::boolean then raise exception 'Falha: gerente sem auditoria'; end if;
 select count(*) into n from public.pdi_performance_audit where entry_id=v;
 if n<>2 then raise exception 'Falha: eventos de auditoria incompletos'; end if;
 select (before_data->>'m2_saved')::numeric into before_value from public.pdi_performance_audit where entry_id=v and action='UPDATE';
 if before_value is distinct from 1.234 then raise exception 'Falha: valor anterior divergente'; end if;
 begin
   delete from public.pdi_performance_audit where entry_id=v;
   raise exception 'Falha: exclusão de logs permitida';
 exception when insufficient_privilege then null; end;
end $$;
rollback;
select 'verificacoes_transacionais_aprovadas' as resultado,
 (select count(*) from public.pdi_pcp_daily) as lancamentos_persistentes,
 (select count(*) from public.pdi_performance_audit) as logs_persistentes;
