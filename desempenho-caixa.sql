-- PDI CDE / Op. de Caixa. Instalar após desempenho-pcp.sql.
-- Valores em centavos inteiros, calendário America/Manaus, PDFs privados imutáveis.
begin;
create or replace function pdi_performance_private.is_cash_position(value text)
returns boolean language sql immutable security invoker set search_path=pg_catalog
as $$ select lower(regexp_replace(btrim(coalesce(value,'')),'[.[:space:]]+','','g')) in ('opdecaixa','opcaixa','operadordecaixa','operadoradecaixa','caixa') $$;
revoke all on function pdi_performance_private.is_cash_position(text) from public;
grant execute on function pdi_performance_private.is_cash_position(text) to authenticated;

create table if not exists public.pdi_cash_files (
 id uuid primary key default gen_random_uuid(),
 entry_id uuid not null,
 cashier_id uuid not null references public.profiles(id) on delete restrict,
 sector_snapshot text,
 work_date date not null,
 uploaded_by uuid not null references public.profiles(id) on delete restrict,
 storage_path text not null unique,
 original_name text not null,
 size_bytes bigint not null check(size_bytes between 8 and 10485760),
 reserved_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default (clock_timestamp()+interval '24 hours'),
 attached_at timestamptz
);
create index if not exists pdi_cash_files_entry_idx on public.pdi_cash_files(entry_id);
create index if not exists pdi_cash_files_cashier_idx on public.pdi_cash_files(cashier_id);
create index if not exists pdi_cash_files_uploader_idx on public.pdi_cash_files(uploaded_by);
create table if not exists public.pdi_cash_daily (
 id uuid primary key default gen_random_uuid(),
 cashier_id uuid not null references public.profiles(id) on delete restrict,
 work_date date not null default (now() at time zone 'America/Manaus')::date,
 result_cents bigint not null check(result_cents between 0 and 99999999999),
 cash_cents bigint not null default 0 check(cash_cents between 0 and 99999999999),
 credit_cash_cents bigint not null default 0 check(credit_cash_cents between 0 and 99999999999),
 credit_installment_cents bigint not null default 0 check(credit_installment_cents between 0 and 99999999999),
 debit_cents bigint not null default 0 check(debit_cents between 0 and 99999999999),
 pix_cents bigint not null default 0 check(pix_cents between 0 and 99999999999),
 installment_plans jsonb not null default '[]',
 pdf_file_id uuid references public.pdi_cash_files(id) on delete restrict,
 pdf_name_snapshot text,
 cashier_name_snapshot text not null default '',
 sector_snapshot text,
 edit_reason text,
 revision integer not null default 1 check(revision>0),
 created_at timestamptz not null default now(),
 created_by uuid references public.profiles(id) on delete restrict,
 updated_at timestamptz not null default now(),
 updated_by uuid references public.profiles(id) on delete restrict,
 constraint pdi_cash_one_entry_per_day unique(cashier_id,work_date),
 constraint pdi_cash_result_matches_methods check(result_cents=cash_cents+credit_cash_cents+credit_installment_cents+debit_cents+pix_cents)
);
create index if not exists pdi_cash_scope_date_idx on public.pdi_cash_daily(sector_snapshot,work_date desc);
create index if not exists pdi_cash_pdf_idx on public.pdi_cash_daily(pdf_file_id);
create index if not exists pdi_cash_creator_idx on public.pdi_cash_daily(created_by);
create index if not exists pdi_cash_updater_idx on public.pdi_cash_daily(updated_by);
create table if not exists public.pdi_cash_audit (
 id uuid primary key default gen_random_uuid(),entry_id uuid not null,cashier_id uuid not null,
 sector_snapshot text,action text not null check(action in ('INSERT','UPDATE','DELETE')),
 actor_id uuid,actor_name text,actor_role text,database_actor text not null,
 occurred_at timestamptz not null default clock_timestamp(),reason text,before_data jsonb,after_data jsonb
);
create index if not exists pdi_cash_audit_scope_idx on public.pdi_cash_audit(sector_snapshot,occurred_at desc);
create index if not exists pdi_cash_audit_entry_idx on public.pdi_cash_audit(entry_id,occurred_at desc);
create index if not exists pdi_cash_audit_cashier_idx on public.pdi_cash_audit(cashier_id,occurred_at desc);
alter table public.pdi_cash_files enable row level security;
alter table public.pdi_cash_daily enable row level security;
alter table public.pdi_cash_audit enable row level security;
revoke all on public.pdi_cash_files,public.pdi_cash_daily,public.pdi_cash_audit from public,anon,authenticated;
grant select on public.pdi_cash_files,public.pdi_cash_audit to authenticated;
grant select(id,cashier_id,work_date,result_cents,cash_cents,credit_cash_cents,credit_installment_cents,debit_cents,pix_cents,installment_plans,pdf_file_id,pdf_name_snapshot,cashier_name_snapshot,sector_snapshot,revision,created_at,created_by,updated_at,updated_by) on public.pdi_cash_daily to authenticated;
grant insert,update on public.pdi_cash_daily to authenticated;
drop policy if exists pdi_cash_read on public.pdi_cash_daily;
create policy pdi_cash_read on public.pdi_cash_daily for select to authenticated using(cashier_id=(select auth.uid()) or pdi_performance_private.can_manage_sector(sector_snapshot,false));
drop policy if exists pdi_cash_insert on public.pdi_cash_daily;
create policy pdi_cash_insert on public.pdi_cash_daily for insert to authenticated with check(cashier_id=(select auth.uid()) and created_by=(select auth.uid()) and work_date=pdi_performance_private.today_manaus() and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and pdi_performance_private.is_cash_position(p.position)));
drop policy if exists pdi_cash_update on public.pdi_cash_daily;
create policy pdi_cash_update on public.pdi_cash_daily for update to authenticated using(pdi_performance_private.can_manage_sector(sector_snapshot,false)) with check(pdi_performance_private.can_manage_sector(sector_snapshot,false));
drop policy if exists pdi_cash_audit_read on public.pdi_cash_audit;
create policy pdi_cash_audit_read on public.pdi_cash_audit for select to authenticated using(pdi_performance_private.can_manage_sector(sector_snapshot,true));

-- Estas funções privadas fazem a ponte controlada entre metadados e Storage.
-- Precisam ler metadados sem recursão de RLS. Nunca retornam conteúdo privilegiado.
create or replace function pdi_performance_private.cash_file_can_read(path text)
returns boolean language sql stable security definer set search_path=pg_catalog
as $$
 select auth.uid() is not null and exists(
   select 1 from public.pdi_cash_files f where f.storage_path=path and (
     (f.attached_at is null and f.uploaded_by=auth.uid() and f.expires_at>statement_timestamp()
       and (f.cashier_id=auth.uid() or pdi_performance_private.can_manage_sector(f.sector_snapshot,false)))
     or (exists(select 1 from public.pdi_cash_daily d where d.id=f.entry_id and d.pdf_file_id=f.id)
       and (f.cashier_id=auth.uid() or pdi_performance_private.can_manage_sector(f.sector_snapshot,false)))
     or (f.attached_at is not null and pdi_performance_private.can_manage_sector(f.sector_snapshot,true))
   )
 )
$$;
revoke all on function pdi_performance_private.cash_file_can_read(text) from public,anon;
grant execute on function pdi_performance_private.cash_file_can_read(text) to authenticated;
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
revoke all on function pdi_performance_private.cash_file_can_upload(text) from public,anon;
grant execute on function pdi_performance_private.cash_file_can_upload(text) to authenticated;
drop policy if exists pdi_cash_file_read on public.pdi_cash_files;
create policy pdi_cash_file_read on public.pdi_cash_files for select to authenticated using(pdi_performance_private.cash_file_can_read(storage_path));

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
revoke all on function pdi_performance_private.cash_reserve_pdf(uuid,uuid,date,text,bigint) from public,anon;
grant execute on function pdi_performance_private.cash_reserve_pdf(uuid,uuid,date,text,bigint) to authenticated;
create or replace function public.pdi_cash_reserve_pdf(p_entry_id uuid,p_cashier_id uuid,p_work_date date,p_original_name text,p_size_bytes bigint)
returns jsonb language sql security invoker set search_path=pg_catalog
as $$ select pdi_performance_private.cash_reserve_pdf(p_entry_id,p_cashier_id,p_work_date,p_original_name,p_size_bytes) $$;
revoke all on function public.pdi_cash_reserve_pdf(uuid,uuid,date,text,bigint) from public,anon;
grant execute on function public.pdi_cash_reserve_pdf(uuid,uuid,date,text,bigint) to authenticated;

-- Valida arquivo realmente enviado pela API de Storage, vinculado ao mesmo fechamento.
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
revoke all on function pdi_performance_private.cash_pdf_ready(uuid,uuid,uuid) from public,anon;
grant execute on function pdi_performance_private.cash_pdf_ready(uuid,uuid,uuid) to authenticated;

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
revoke all on function pdi_performance_private.guard_cash_daily() from public,anon,authenticated;
drop trigger if exists pdi_guard_cash_daily on public.pdi_cash_daily;
create trigger pdi_guard_cash_daily before insert or update or delete on public.pdi_cash_daily for each row execute function pdi_performance_private.guard_cash_daily();
create or replace function pdi_performance_private.audit_cash_daily()
returns trigger language plpgsql security definer set search_path=pg_catalog
as $$
declare d public.pdi_cash_daily%rowtype; a public.profiles%rowtype;
begin
 if tg_op='DELETE' then d:=old; else d:=new; end if;
 select * into a from public.profiles where id=auth.uid();
 if tg_op<>'DELETE' and new.pdf_file_id is not null then update public.pdi_cash_files set attached_at=coalesce(attached_at,clock_timestamp()) where id=new.pdf_file_id; end if;
 insert into public.pdi_cash_audit(entry_id,cashier_id,sector_snapshot,action,actor_id,actor_name,actor_role,database_actor,reason,before_data,after_data)
 values(d.id,d.cashier_id,d.sector_snapshot,tg_op,auth.uid(),coalesce(a.full_name,'Operação administrativa'),a.role,session_user||'/'||coalesce(current_setting('role',true),'none'),
   case when tg_op='UPDATE' then new.edit_reason else null end,
   case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
   case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end);
 if tg_op='DELETE' then return old; else return new; end if;
end $$;
revoke all on function pdi_performance_private.audit_cash_daily() from public,anon,authenticated;
drop trigger if exists pdi_audit_cash_daily on public.pdi_cash_daily;
create trigger pdi_audit_cash_daily after insert or update or delete on public.pdi_cash_daily for each row execute function pdi_performance_private.audit_cash_daily();

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
revoke all on function public.pdi_cash_context() from public,anon;
grant execute on function public.pdi_cash_context() to authenticated;
create or replace function public.pdi_cash_dashboard(p_start_date date,p_end_date date,p_cashier_id uuid default null)
returns jsonb language plpgsql stable security invoker set search_path=pg_catalog
as $$
declare a public.profiles%rowtype; g boolean; result jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.' using errcode='42501'; end if;
 select * into a from public.profiles where id=auth.uid();
 g:=coalesce(a.is_master,false) or lower(btrim(coalesce(a.role,''))) in ('master','diretor','diretoria');
 if a.id is null or not(g or lower(btrim(coalesce(a.role,''))) in ('supervisor','gerente')) then raise exception 'Dashboard restrito à gestão.' using errcode='42501'; end if;
 if p_start_date is null or p_end_date is null or not isfinite(p_start_date) or not isfinite(p_end_date) or p_start_date>p_end_date then raise exception 'Período inválido.' using errcode='22023'; end if;
 select jsonb_build_object('result_cents',coalesce(sum(d.result_cents),0)::text,'cash_cents',coalesce(sum(d.cash_cents),0)::text,'credit_cash_cents',coalesce(sum(d.credit_cash_cents),0)::text,
 'credit_installment_cents',coalesce(sum(d.credit_installment_cents),0)::text,'debit_cents',coalesce(sum(d.debit_cents),0)::text,'pix_cents',coalesce(sum(d.pix_cents),0)::text,
 'entry_count',count(*),'cashier_count',count(distinct d.cashier_id),'updated_at',statement_timestamp()) into result
 from public.pdi_cash_daily d where d.work_date between p_start_date and p_end_date and (p_cashier_id is null or d.cashier_id=p_cashier_id)
 and (g or (a.sector is not null and d.sector_snapshot=a.sector));
 return result;
end $$;
revoke all on function public.pdi_cash_dashboard(date,date,uuid) from public,anon;
grant execute on function public.pdi_cash_dashboard(date,date,uuid) to authenticated;

-- Bucket exclusivo: não modifica outros buckets nem os seus arquivos.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('pdi-cash-pdfs','pdi-cash-pdfs',false,10485760,array['application/pdf'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=array['application/pdf'];
-- Há políticas permissivas legadas globais. As RESTRITIVAS abaixo impedem
-- que essas políticas concedam acesso aos PDFs financeiros deste bucket.
drop policy if exists pdi_cash_pdf_select_guard on storage.objects;
create policy pdi_cash_pdf_select_guard on storage.objects as restrictive for select to authenticated using(bucket_id<>'pdi-cash-pdfs' or (auth.uid() is not null and pdi_performance_private.cash_file_can_read(name)));
drop policy if exists pdi_cash_pdf_insert_guard on storage.objects;
create policy pdi_cash_pdf_insert_guard on storage.objects as restrictive for insert to authenticated with check(bucket_id<>'pdi-cash-pdfs' or (auth.uid() is not null and pdi_performance_private.cash_file_can_upload(name)));
drop policy if exists pdi_cash_pdf_update_guard on storage.objects;
create policy pdi_cash_pdf_update_guard on storage.objects as restrictive for update to authenticated using(bucket_id<>'pdi-cash-pdfs') with check(bucket_id<>'pdi-cash-pdfs');
drop policy if exists pdi_cash_pdf_delete_guard on storage.objects;
create policy pdi_cash_pdf_delete_guard on storage.objects as restrictive for delete to authenticated using(bucket_id<>'pdi-cash-pdfs');
drop policy if exists pdi_cash_pdf_select on storage.objects;
create policy pdi_cash_pdf_select on storage.objects for select to authenticated using(bucket_id='pdi-cash-pdfs' and pdi_performance_private.cash_file_can_read(name));
drop policy if exists pdi_cash_pdf_insert on storage.objects;
create policy pdi_cash_pdf_insert on storage.objects for insert to authenticated with check(bucket_id='pdi-cash-pdfs' and pdi_performance_private.cash_file_can_upload(name));
drop policy if exists pdi_cash_pdf_anon_guard on storage.objects;
create policy pdi_cash_pdf_anon_guard on storage.objects as restrictive for all to anon using(bucket_id<>'pdi-cash-pdfs') with check(bucket_id<>'pdi-cash-pdfs');
drop policy if exists pdi_cash_collect_guard on public.pdi_cash_daily;
create policy pdi_cash_collect_guard on public.pdi_cash_daily as restrictive for insert to authenticated with check(pdi_performance_private.can_collect_performance());
drop policy if exists pdi_cash_correct_guard on public.pdi_cash_daily;
create policy pdi_cash_correct_guard on public.pdi_cash_daily as restrictive for update to authenticated using(pdi_performance_private.can_correct_sector(sector_snapshot)) with check(pdi_performance_private.can_correct_sector(sector_snapshot));
drop policy if exists pdi_cash_pdf_collector_guard on storage.objects;
create policy pdi_cash_pdf_collector_guard on storage.objects as restrictive for insert to authenticated with check(bucket_id<>'pdi-cash-pdfs' or pdi_performance_private.can_collect_performance());
notify pgrst,'reload schema';
commit;
