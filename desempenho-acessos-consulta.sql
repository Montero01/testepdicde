-- Atualização aditiva: gestões com dashboards; coleta/edição operacional. Sem alterar registros.
begin;

-- Coleta por colaboradores/supervisão; Master, gerência e Diretoria somente leitura.
create or replace function pdi_performance_private.can_collect_performance()
returns boolean language sql stable security invoker set search_path=pg_catalog
as $$ select auth.uid() is not null and exists(select 1 from public.profiles a where a.id=auth.uid()
 and not coalesce(a.is_master,false) and lower(btrim(coalesce(a.role,''))) in ('employee','colaborador','supervisor')) $$;
revoke all on function pdi_performance_private.can_collect_performance() from public,anon;
grant execute on function pdi_performance_private.can_collect_performance() to authenticated;
create or replace function pdi_performance_private.can_correct_sector(target_sector text)
returns boolean language sql stable security invoker set search_path=pg_catalog
as $$ select auth.uid() is not null and exists(select 1 from public.profiles a where a.id=auth.uid()
 and not coalesce(a.is_master,false) and lower(btrim(coalesce(a.role,'')))='supervisor'
 and a.sector is not null and a.sector=target_sector) $$;
revoke all on function pdi_performance_private.can_correct_sector(text) from public,anon;
grant execute on function pdi_performance_private.can_correct_sector(text) to authenticated;

drop policy if exists pdi_pcp_collect_guard on public.pdi_pcp_daily;
create policy pdi_pcp_collect_guard on public.pdi_pcp_daily as restrictive for insert to authenticated with check(pdi_performance_private.can_collect_performance());
drop policy if exists pdi_pcp_correct_guard on public.pdi_pcp_daily;
create policy pdi_pcp_correct_guard on public.pdi_pcp_daily as restrictive for update to authenticated using(pdi_performance_private.can_correct_sector(sector_snapshot)) with check(pdi_performance_private.can_correct_sector(sector_snapshot));

create or replace function pdi_performance_private.guard_daily_entry()
returns trigger language plpgsql security invoker set search_path=pg_catalog
as $$
declare p public.profiles%rowtype; uid uuid:=auth.uid();
 caller_role text:=coalesce(current_setting('role',true),'none');
 trusted boolean; count_orders integer;
begin
 trusted:=caller_role='service_role' or (caller_role in ('none','postgres') and session_user in ('postgres','supabase_admin'));
 if tg_op='DELETE' then
   if not trusted then raise exception 'Lançamentos não podem ser excluídos pelo aplicativo.' using errcode='42501'; end if;
   return old;
 end if;
 if uid is null and not trusted then raise exception 'Autenticação necessária.' using errcode='42501'; end if;
 -- O tipo numeric do banco preserva milésimos de m². NaN/infinito são recusados explicitamente.
 if new.m2_saved is null or new.m2_saved::text in ('NaN','Infinity','-Infinity') or new.m2_saved<0 or new.m2_saved>=1000000000 or scale(new.m2_saved)>3 then
   raise exception 'Informe uma quantidade válida de m², com até 3 casas decimais.' using errcode='22023';
 end if;
 if new.order_numbers is null or array_ndims(new.order_numbers)>1 then
   raise exception 'Lista de pedidos inválida.' using errcode='22023';
 end if;
 count_orders:=cardinality(new.order_numbers);
 if count_orders>200 or exists(select 1 from unnest(new.order_numbers) o where o is null or o !~ '^[0-9]{1,20}$')
   or count_orders<>(select count(distinct o) from unnest(new.order_numbers) o) then
   raise exception 'Use até 200 números de pedidos distintos, somente dígitos, com até 20 caracteres cada.' using errcode='22023';
 end if;
 if new.m2_saved>0 and count_orders=0 then raise exception 'Informe os pedidos relacionados aos m² salvos.' using errcode='22023'; end if;
 if tg_op='INSERT' then
   select * into p from public.profiles where id=new.pcp_id;
   if p.id is null or lower(btrim(coalesce(p.position,'')))<>'pcp' then
     raise exception 'O colaborador precisa ter position PCP.' using errcode='42501'; end if;
   if not trusted and not pdi_performance_private.can_collect_performance() then raise exception 'Gerência e Diretoria possuem acesso somente de consulta.' using errcode='42501'; end if;
   if not trusted and (new.pcp_id<>uid or new.work_date is distinct from pdi_performance_private.today_manaus()) then
     raise exception 'O PCP registra somente o próprio resultado de hoje.' using errcode='42501'; end if;
   new.pcp_name_snapshot:=coalesce(p.full_name,'PCP'); new.sector_snapshot:=p.sector;
   new.created_at:=clock_timestamp(); new.created_by:=uid;
   new.revision:=1; new.edit_reason:=null;
 else
   if new.id is distinct from old.id or new.pcp_id is distinct from old.pcp_id or new.work_date is distinct from old.work_date
     or new.created_at is distinct from old.created_at or new.created_by is distinct from old.created_by
     or new.pcp_name_snapshot is distinct from old.pcp_name_snapshot or new.sector_snapshot is distinct from old.sector_snapshot then
     raise exception 'A identidade, data e origem do lançamento não podem ser alteradas.' using errcode='22023'; end if;
   if not trusted and not pdi_performance_private.can_correct_sector(old.sector_snapshot) then
     raise exception 'Somente a supervisão do setor pode corrigir o lançamento.' using errcode='42501'; end if;
   if length(btrim(coalesce(new.edit_reason,'')))<10 or length(new.edit_reason)>300 then
     raise exception 'Informe uma justificativa de 10 a 300 caracteres.' using errcode='22023'; end if;
   if new.m2_saved=old.m2_saved and new.order_numbers=old.order_numbers then
     raise exception 'Não há alteração nos m² ou pedidos.' using errcode='22023'; end if;
   new.revision:=old.revision+1;
 end if;
 new.updated_at:=clock_timestamp(); new.updated_by:=uid;
 return new;
end $$;

create or replace function public.pdi_desempenho_context()
returns jsonb language plpgsql stable security invoker set search_path=pg_catalog
as $$
declare a public.profiles%rowtype; global_access boolean; manage boolean; audit boolean; people jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.' using errcode='42501'; end if;
 select * into a from public.profiles where id=auth.uid();
 if a.id is null then raise exception 'Perfil não encontrado.' using errcode='42501'; end if;
 global_access:=coalesce(a.is_master,false) or lower(btrim(coalesce(a.role,''))) in ('master','diretor','diretoria');
 manage:=global_access or lower(btrim(coalesce(a.role,''))) in ('gerente','supervisor');
 audit:=global_access or lower(btrim(coalesce(a.role,'')))='gerente';
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(p.full_name,'PCP'),'sector',p.sector) order by p.full_name),'[]'::jsonb)
 into people from public.profiles p where lower(btrim(coalesce(p.position,'')))='pcp'
   and (p.id=a.id or (manage and (global_access or (a.sector is not null and p.sector=a.sector))));
 return jsonb_build_object('today',pdi_performance_private.today_manaus(),'is_pcp',lower(btrim(coalesce(a.position,'')))='pcp',
   'can_collect',pdi_performance_private.can_collect_performance() and lower(btrim(coalesce(a.position,'')))='pcp',
   'can_correct',pdi_performance_private.can_correct_sector(a.sector),
   'dashboard_only',manage and (global_access or lower(btrim(coalesce(a.role,'')))<>'supervisor'),
   'can_manage',manage,'can_view_logs',audit,'global_access',global_access,'pcps',people,'position',a.position);
end $$;

drop policy if exists pdi_cash_collect_guard on public.pdi_cash_daily;
create policy pdi_cash_collect_guard on public.pdi_cash_daily as restrictive for insert to authenticated with check(pdi_performance_private.can_collect_performance());
drop policy if exists pdi_cash_correct_guard on public.pdi_cash_daily;
create policy pdi_cash_correct_guard on public.pdi_cash_daily as restrictive for update to authenticated using(pdi_performance_private.can_correct_sector(sector_snapshot)) with check(pdi_performance_private.can_correct_sector(sector_snapshot));
drop policy if exists pdi_cash_pdf_collector_guard on storage.objects;
create policy pdi_cash_pdf_collector_guard on storage.objects as restrictive for insert to authenticated with check(bucket_id<>'pdi-cash-pdfs' or pdi_performance_private.can_collect_performance());

create or replace function pdi_performance_private.cash_file_can_upload(path text)
returns boolean language sql stable security definer set search_path=pg_catalog
as $$
 select auth.uid() is not null and exists(
   select 1 from public.pdi_cash_files f where f.storage_path=path and f.uploaded_by=auth.uid()
    and f.attached_at is null and f.expires_at>statement_timestamp() and pdi_performance_private.can_collect_performance() and (
      exists(select 1 from public.pdi_cash_daily d where d.id=f.entry_id and d.cashier_id=f.cashier_id and pdi_performance_private.can_correct_sector(d.sector_snapshot))
      or (f.cashier_id=auth.uid() and f.work_date=pdi_performance_private.today_manaus()
        and exists(select 1 from public.profiles p where p.id=auth.uid() and pdi_performance_private.is_cash_position(p.position))
        and not exists(select 1 from public.pdi_cash_daily d where d.cashier_id=f.cashier_id and d.work_date=f.work_date))
    )
 )
$$;

create or replace function pdi_performance_private.cash_reserve_pdf(p_entry uuid,p_cashier uuid,p_day date,p_name text,p_size bigint)
returns jsonb language plpgsql security definer set search_path=pg_catalog
as $$
declare uid uuid:=auth.uid(); d public.pdi_cash_daily%rowtype; p public.profiles%rowtype; f public.pdi_cash_files%rowtype; clean_name text; sector text;
begin
 if uid is null then raise exception 'Autenticação necessária.' using errcode='42501'; end if;
 if not pdi_performance_private.can_collect_performance() then raise exception 'Gerência e Diretoria não podem enviar anexos ou corrigir fechamentos.' using errcode='42501'; end if;
 if p_entry is null or p_cashier is null or p_day is null then raise exception 'Identificação do fechamento inválida.' using errcode='22023'; end if;
 clean_name:=regexp_replace(btrim(coalesce(p_name,'')),'[[:cntrl:]/\\]','_','g');
 if length(clean_name)<5 or length(clean_name)>180 or clean_name !~* '\.pdf$' or p_size is null or p_size<8 or p_size>10485760 then
   raise exception 'Use um PDF de até 10 MB, com nome de até 180 caracteres.' using errcode='22023'; end if;
 select * into d from public.pdi_cash_daily where id=p_entry;
 if d.id is not null then
   if d.cashier_id<>p_cashier or d.work_date<>p_day or not pdi_performance_private.can_correct_sector(d.sector_snapshot) then
     raise exception 'Você não pode substituir o PDF deste fechamento.' using errcode='42501'; end if;
   sector:=d.sector_snapshot;
 else
   select * into p from public.profiles where id=p_cashier;
   if p_cashier<>uid or p_day<>pdi_performance_private.today_manaus() or not pdi_performance_private.is_cash_position(p.position)
     or exists(select 1 from public.pdi_cash_daily x where x.cashier_id=p_cashier and x.work_date=p_day) then
     raise exception 'Somente a operadora registra o próprio fechamento de hoje.' using errcode='42501'; end if;
   sector:=p.sector;
 end if;
 f.id:=gen_random_uuid();
 insert into public.pdi_cash_files(id,entry_id,cashier_id,work_date,sector_snapshot,uploaded_by,storage_path,original_name,size_bytes)
 values(f.id,p_entry,p_cashier,p_day,sector,uid,p_cashier::text||'/'||p_entry::text||'/'||f.id::text||'.pdf',clean_name,p_size) returning * into f;
 return jsonb_build_object('id',f.id,'path',f.storage_path,'name',f.original_name,'size',f.size_bytes);
end $$;

create or replace function pdi_performance_private.cash_pdf_ready(p_file_id uuid,p_entry_id uuid,p_cashier_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog
as $$
 select auth.uid() is not null and pdi_performance_private.can_collect_performance() and exists(
  select 1 from public.pdi_cash_files f join storage.objects o on o.bucket_id='pdi-cash-pdfs' and o.name=f.storage_path
  where f.id=p_file_id and f.entry_id=p_entry_id and f.cashier_id=p_cashier_id and f.uploaded_by=auth.uid()
   and f.attached_at is null and f.expires_at>statement_timestamp()
   and lower(o.metadata->>'mimetype')='application/pdf' and (o.metadata->>'size')::numeric=f.size_bytes
 )
$$;

create or replace function pdi_performance_private.guard_cash_daily()
returns trigger language plpgsql security invoker set search_path=pg_catalog
as $$
declare p public.profiles%rowtype; uid uuid:=auth.uid(); trusted boolean;
 caller text:=coalesce(current_setting('role',true),'none');
 plan jsonb; canonical jsonb:='[]'; total numeric; amount numeric; n numeric; last_amount numeric; installment_sum numeric:=0;
begin
 trusted:=caller='service_role' or (caller in ('none','postgres') and session_user in ('postgres','supabase_admin'));
 if tg_op='DELETE' then
   if not trusted then raise exception 'Fechamentos não podem ser excluídos pelo aplicativo.' using errcode='42501'; end if;
   return old;
 end if;
 if uid is null and not trusted then raise exception 'Autenticação necessária.' using errcode='42501'; end if;
 if tg_op='INSERT' then
   select * into p from public.profiles where id=new.cashier_id;
   if p.id is null or not pdi_performance_private.is_cash_position(p.position) then raise exception 'Colaborador sem cargo de Caixa.' using errcode='42501'; end if;
   if not trusted and not pdi_performance_private.can_collect_performance() then raise exception 'Gerência e Diretoria possuem acesso somente de consulta.' using errcode='42501'; end if;
   if not trusted and (new.cashier_id<>uid or new.work_date is distinct from pdi_performance_private.today_manaus()) then raise exception 'Registre somente o próprio fechamento de hoje.' using errcode='42501'; end if;
   new.cashier_name_snapshot:=coalesce(p.full_name,'Op. de Caixa'); new.sector_snapshot:=p.sector;
   new.created_at:=clock_timestamp(); new.created_by:=uid; new.revision:=1; new.edit_reason:=null;
 else
   if new.id is distinct from old.id or new.cashier_id is distinct from old.cashier_id or new.work_date is distinct from old.work_date
     or new.created_at is distinct from old.created_at or new.created_by is distinct from old.created_by
     or new.cashier_name_snapshot is distinct from old.cashier_name_snapshot or new.sector_snapshot is distinct from old.sector_snapshot then
     raise exception 'A identidade, data e origem do fechamento não podem ser alteradas.' using errcode='22023'; end if;
   if not trusted and not pdi_performance_private.can_correct_sector(old.sector_snapshot) then raise exception 'Correção restrita à supervisão do setor.' using errcode='42501'; end if;
   if length(btrim(coalesce(new.edit_reason,'')))<10 or length(new.edit_reason)>300 then raise exception 'Informe uma justificativa de 10 a 300 caracteres.' using errcode='22023'; end if;
 end if;
 if new.installment_plans is null or jsonb_typeof(new.installment_plans)<>'array' or jsonb_array_length(new.installment_plans)>200 then raise exception 'Lista de parcelamentos inválida (máximo 200).' using errcode='22023'; end if;
 for plan in select * from jsonb_array_elements(new.installment_plans) loop
   if jsonb_typeof(plan)<>'object' or jsonb_typeof(plan->'total_cents') is distinct from 'number'
     or jsonb_typeof(plan->'installment_cents') is distinct from 'number' or jsonb_typeof(plan->'count') is distinct from 'number' then
     raise exception 'Preencha total, valor da parcela e quantidade de cada parcelamento.' using errcode='22023'; end if;
   total:=(plan->>'total_cents')::numeric; amount:=(plan->>'installment_cents')::numeric; n:=(plan->>'count')::numeric;
   if total<>trunc(total) or amount<>trunc(amount) or n<>trunc(n) or total<=0 or total>99999999999 or amount<=0 or amount>99999999999 or n<2 or n>120 then
     raise exception 'Parcelamento inválido: valores em centavos e quantidade de 2 a 120.' using errcode='22023'; end if;
   last_amount:=total-amount*(n-1);
   if amount<floor(total/n) or amount>ceil(total/n) or last_amount<=0 then
     raise exception 'O valor das parcelas não corresponde ao total. Só são permitidos ajustes de centavos na última parcela.' using errcode='22023'; end if;
   installment_sum:=installment_sum+total;
   canonical:=canonical||jsonb_build_array(jsonb_build_object('total_cents',total::bigint,'installment_cents',amount::bigint,'count',n::integer,'last_installment_cents',last_amount::bigint));
 end loop;
 if installment_sum>99999999999 then raise exception 'Total parcelado excede o limite técnico.' using errcode='22023'; end if;
 new.installment_plans:=canonical; new.credit_installment_cents:=installment_sum::bigint;
 if new.result_cents is null or new.cash_cents is null or new.credit_cash_cents is null or new.debit_cents is null or new.pix_cents is null
   or least(new.result_cents,new.cash_cents,new.credit_cash_cents,new.debit_cents,new.pix_cents)<0
   or greatest(new.result_cents,new.cash_cents,new.credit_cash_cents,new.debit_cents,new.pix_cents)>99999999999
   or new.result_cents<>new.cash_cents+new.credit_cash_cents+new.credit_installment_cents+new.debit_cents+new.pix_cents then
   raise exception 'O Resultado do Dia precisa ser igual à soma de Dinheiro, Crédito à vista, Crédito parcelado, Débito e Pix.' using errcode='22023'; end if;
 if new.pdf_file_id is not null and (tg_op='INSERT' or new.pdf_file_id is distinct from old.pdf_file_id) then
   if not pdi_performance_private.cash_pdf_ready(new.pdf_file_id,new.id,new.cashier_id) then raise exception 'PDF não enviado, expirado ou não pertence a este fechamento.' using errcode='22023'; end if;
 end if;
 new.pdf_name_snapshot:=null;
 if new.pdf_file_id is not null then select f.original_name into new.pdf_name_snapshot from public.pdi_cash_files f where f.id=new.pdf_file_id; end if;
 if tg_op='UPDATE' then
   if row(new.result_cents,new.cash_cents,new.credit_cash_cents,new.credit_installment_cents,new.debit_cents,new.pix_cents,new.installment_plans,new.pdf_file_id)
     is not distinct from row(old.result_cents,old.cash_cents,old.credit_cash_cents,old.credit_installment_cents,old.debit_cents,old.pix_cents,old.installment_plans,old.pdf_file_id) then
     raise exception 'Não há alteração nos valores ou PDF.' using errcode='22023'; end if;
   new.revision:=old.revision+1;
 end if;
 new.updated_at:=clock_timestamp(); new.updated_by:=uid;
 return new;
end $$;

create or replace function public.pdi_cash_context()
returns jsonb language plpgsql stable security invoker set search_path=pg_catalog
as $$
declare a public.profiles%rowtype; global_access boolean; manage boolean; people jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.' using errcode='42501'; end if;
 select * into a from public.profiles where id=auth.uid();
 if a.id is null then raise exception 'Perfil não encontrado.' using errcode='42501'; end if;
 global_access:=coalesce(a.is_master,false) or lower(btrim(coalesce(a.role,''))) in ('master','diretor','diretoria');
 manage:=global_access or lower(btrim(coalesce(a.role,''))) in ('supervisor','gerente');
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(p.full_name,'Op. de Caixa'),'sector',p.sector) order by p.full_name),'[]') into people
 from public.profiles p where pdi_performance_private.is_cash_position(p.position) and (p.id=a.id or (manage and (global_access or (a.sector is not null and p.sector=a.sector))));
 return jsonb_build_object('can_collect',pdi_performance_private.can_collect_performance() and pdi_performance_private.is_cash_position(a.position),
 'can_correct',pdi_performance_private.can_correct_sector(a.sector),
 'dashboard_only',manage and (global_access or lower(btrim(coalesce(a.role,'')))<>'supervisor'),
 'today',pdi_performance_private.today_manaus(),'is_cashier',pdi_performance_private.is_cash_position(a.position),'can_manage',manage,
 'can_view_logs',global_access or lower(btrim(coalesce(a.role,'')))='gerente','cashiers',people);
end $$;

notify pgrst,'reload schema';
commit;
