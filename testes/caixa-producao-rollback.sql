-- Projeto real: testes transacionais desfeitos. Não escreve storage.objects.
begin;
do $$ declare c uuid; g uuid; x uuid; begin
 select id into c from public.profiles where pdi_performance_private.is_cash_position(position) and role in ('employee','colaborador') and not coalesce(is_master,false) limit 1;
 select p.id into g from public.profiles p join public.profiles caixa on caixa.id=c where (p.role='gerente' and p.sector=caixa.sector) or p.role in ('diretor','diretoria','master') or p.is_master=true order by (p.role='gerente') desc limit 1;
 if c is null or g is null then raise exception 'Perfil de teste indisponível'; end if;
 x:=gen_random_uuid();perform set_config('cash_test.uid',c::text,true);perform set_config('cash_test.manager',g::text,true);perform set_config('cash_test.entry',x::text,true);
end $$;
set local role authenticated;
do $$ declare c uuid:=current_setting('cash_test.uid')::uuid; x uuid:=current_setting('cash_test.entry')::uuid; f jsonb; j jsonb; n integer; today date; begin
 perform set_config('request.jwt.claim.sub',c::text,true);today:=pdi_performance_private.today_manaus();
 if not (public.pdi_cash_context()->>'is_cashier')::boolean then raise exception 'Contexto de Caixa incorreto'; end if;
 -- Reserva somente metadados de teste, sem enviar arquivo. O registro não pode anexar PDF inexistente.
 f:=public.pdi_cash_reserve_pdf(x,c,today,'teste-transacional.pdf',100);
 if not pdi_performance_private.cash_file_can_upload(f->>'path') then raise exception 'Reserva não autoriza upload'; end if;
 if pdi_performance_private.cash_pdf_ready((f->>'id')::uuid,x,c) then raise exception 'PDF inexistente aceito'; end if;
 begin
  insert into public.pdi_cash_daily(id,cashier_id,result_cents,pdf_file_id) values(x,c,0,(f->>'id')::uuid);
  raise exception 'PDF inexistente foi anexado';
 exception when invalid_parameter_value then null; end;
 insert into public.pdi_cash_daily(id,cashier_id,result_cents,cash_cents,installment_plans)
 values(x,c,20000,10000,'[{"total_cents":10000,"installment_cents":3333,"count":3}]');
 begin
  insert into public.pdi_cash_daily(cashier_id,result_cents) values(c,0);raise exception 'Registro diário duplicado';
 exception when unique_violation then null; end;
 if exists(select 1 from public.pdi_cash_audit) then raise exception 'Operadora lê logs'; end if;
 update public.pdi_cash_daily set result_cents=21000,cash_cents=11000,edit_reason='Tentativa de alteração pela operadora' where id=x;
 get diagnostics n=row_count;if n<>0 then raise exception 'Operadora conseguiu editar'; end if;
 perform set_config('request.jwt.claim.sub',current_setting('cash_test.manager'),true);
 update public.pdi_cash_daily set result_cents=21000,cash_cents=11000,edit_reason='TESTE TRANSACIONAL DESFEITO AO FINAL' where id=x and revision=1;
 get diagnostics n=row_count;if n<>0 then raise exception 'Gestão não deveria corrigir'; end if;
 select count(*) into n from public.pdi_cash_audit where entry_id=x;
 if n<>1 then raise exception 'Tentativa gerencial não deve gerar alteração'; end if;
 j:=public.pdi_cash_dashboard(today,today,c);
 if (j->>'result_cents')::bigint<>20000 or (j->>'entry_count')::int<>1 then raise exception 'Dashboard gerencial divergente'; end if;
end $$;
rollback;
select jsonb_build_object('resultado','caixa_validado_com_rollback','bucket_privado',(select not public from storage.buckets where id='pdi-cash-pdfs'),
 'limite_pdf_bytes',(select file_size_limit from storage.buckets where id='pdi-cash-pdfs'),
 'fechamentos_persistentes',(select count(*) from public.pdi_cash_daily),'logs_persistentes',(select count(*) from public.pdi_cash_audit),
 'reservas_persistentes',(select count(*) from public.pdi_cash_files)) as verificacao;
