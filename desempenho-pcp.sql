-- PDI CDE / PCP — dia de trabalho em America/Manaus. Sem alteração dos dados existentes.
begin;
create schema if not exists pdi_performance_private;
revoke all on schema pdi_performance_private from public;
grant usage on schema pdi_performance_private to authenticated;

create or replace function pdi_performance_private.today_manaus()
returns date language sql stable security invoker set search_path=pg_catalog
as $$ select (statement_timestamp() at time zone 'America/Manaus')::date $$;
revoke all on function pdi_performance_private.today_manaus() from public;
grant execute on function pdi_performance_private.today_manaus() to authenticated;

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

-- Impede que o usuário transforme seu próprio perfil em gerente/Master/PCP.
-- Diretoria/Master: administração. Gerentes: colaboradores do próprio setor.
create or replace function pdi_performance_private.guard_profile_authority()
returns trigger language plpgsql security definer set search_path=pg_catalog
as $$
declare a public.profiles%rowtype; uid uuid := auth.uid();
  privileged boolean; manager_employee boolean := false;
  caller_role text := coalesce(current_setting('role',true),'none');
begin
  if caller_role='service_role' or (caller_role in ('none','postgres','supabase_auth_admin') and session_user in ('postgres','supabase_admin','supabase_auth_admin')) then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  if uid is null then raise exception 'Autenticação necessária.' using errcode='42501'; end if;
  select * into a from public.profiles where id=uid;
  privileged := coalesce(a.is_master,false) or lower(btrim(coalesce(a.role,''))) in ('master','diretor','diretoria');
  if privileged then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  if tg_op='DELETE' then raise exception 'Somente a administração pode excluir perfis.' using errcode='42501'; end if;
  if lower(btrim(coalesce(a.role,'')))='gerente' then
    manager_employee := lower(btrim(coalesce(new.role,''))) in ('employee','colaborador')
      and not coalesce(new.is_master,false) and not coalesce(new.is_professor,false)
      and a.sector is not null and new.sector=a.sector;
    if tg_op='UPDATE' then
      manager_employee := manager_employee and old.sector=a.sector
        and lower(btrim(coalesce(old.role,''))) in ('employee','colaborador')
        and not coalesce(old.is_master,false) and not coalesce(old.is_professor,false)
        and new.id=old.id;
    end if;
  end if;
  if manager_employee then return new; end if;
  if tg_op='INSERT' then raise exception 'Cadastro de perfis restrito à gestão.' using errcode='42501'; end if;
  if old.id<>uid or new.id is distinct from old.id or new.role is distinct from old.role
    or new.is_master is distinct from old.is_master or new.is_professor is distinct from old.is_professor
    or new.position is distinct from old.position or new.sector is distinct from old.sector then
    raise exception 'Você pode atualizar seus dados pessoais, mas não os campos de acesso.' using errcode='42501';
  end if;
  return new;
end $$;
revoke all on function pdi_performance_private.guard_profile_authority() from public,anon,authenticated;
drop trigger if exists pdi_guard_profile_authority on public.profiles;
create trigger pdi_guard_profile_authority before insert or update or delete on public.profiles
for each row execute function pdi_performance_private.guard_profile_authority();

create or replace function pdi_performance_private.can_manage_sector(target_sector text, audit_only boolean default false)
returns boolean language sql stable security invoker set search_path=pg_catalog
as $$
 select auth.uid() is not null and exists (
   select 1 from public.profiles a where a.id=auth.uid() and (
     coalesce(a.is_master,false) or lower(btrim(coalesce(a.role,''))) in ('master','diretor','diretoria')
     or (lower(btrim(coalesce(a.role,''))) in ('gerente','supervisor')
       and (not audit_only or lower(btrim(coalesce(a.role,'')))='gerente')
       and a.sector is not null and a.sector=target_sector)
   )
 )
$$;
revoke all on function pdi_performance_private.can_manage_sector(text,boolean) from public;
grant execute on function pdi_performance_private.can_manage_sector(text,boolean) to authenticated;

create table if not exists public.pdi_pcp_daily (
 id uuid primary key default gen_random_uuid(),
 pcp_id uuid not null references public.profiles(id) on delete restrict,
 work_date date not null default (now() at time zone 'America/Manaus')::date,
 m2_saved numeric not null check(m2_saved>=0 and m2_saved<1000000000 and scale(m2_saved)<=3),
 order_numbers text[] not null default '{}',
 pcp_name_snapshot text not null default '',
 sector_snapshot text,
 edit_reason text,
 revision integer not null default 1 check(revision>0),
 created_at timestamptz not null default now(),
 created_by uuid references public.profiles(id) on delete restrict,
 updated_at timestamptz not null default now(),
 updated_by uuid references public.profiles(id) on delete restrict,
 constraint pdi_pcp_one_entry_per_day unique(pcp_id,work_date)
);
create index if not exists pdi_pcp_scope_date_idx on public.pdi_pcp_daily(sector_snapshot,work_date desc);
create table if not exists public.pdi_performance_audit (
 id uuid primary key default gen_random_uuid(),
 entry_id uuid not null,
 pcp_id uuid not null,
 sector_snapshot text,
 module_key text not null default 'pcp_m2',
 action text not null check(action in ('INSERT','UPDATE','DELETE')),
 actor_id uuid,
 actor_name text,
 actor_role text,
 database_actor text not null,
 occurred_at timestamptz not null default clock_timestamp(),
 reason text,
 before_data jsonb,
 after_data jsonb
);
create index if not exists pdi_audit_scope_date_idx on public.pdi_performance_audit(sector_snapshot,occurred_at desc);
create index if not exists pdi_audit_entry_idx on public.pdi_performance_audit(entry_id,occurred_at desc);
alter table public.pdi_pcp_daily enable row level security;
alter table public.pdi_performance_audit enable row level security;
revoke all on public.pdi_pcp_daily,public.pdi_performance_audit from public,anon,authenticated;
-- A justificativa integra a auditoria. Não pode ser lida por PCP/supervisor
-- por meio da tabela diária. O app envia o campo somente nas correções.
grant select(id,pcp_id,work_date,m2_saved,order_numbers,pcp_name_snapshot,sector_snapshot,revision,created_at,created_by,updated_at,updated_by) on public.pdi_pcp_daily to authenticated;
grant insert,update on public.pdi_pcp_daily to authenticated;
grant select on public.pdi_performance_audit to authenticated;

drop policy if exists pdi_pcp_read on public.pdi_pcp_daily;
create policy pdi_pcp_read on public.pdi_pcp_daily for select to authenticated using (
 pcp_id=(select auth.uid()) or pdi_performance_private.can_manage_sector(sector_snapshot,false));
drop policy if exists pdi_pcp_insert on public.pdi_pcp_daily;
create policy pdi_pcp_insert on public.pdi_pcp_daily for insert to authenticated with check (
 pcp_id=(select auth.uid()) and created_by=(select auth.uid()) and work_date=pdi_performance_private.today_manaus()
 and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and lower(btrim(coalesce(p.position,'')))='pcp'));
drop policy if exists pdi_pcp_update on public.pdi_pcp_daily;
create policy pdi_pcp_update on public.pdi_pcp_daily for update to authenticated
 using(pdi_performance_private.can_manage_sector(sector_snapshot,false))
 with check(pdi_performance_private.can_manage_sector(sector_snapshot,false));
drop policy if exists pdi_audit_read on public.pdi_performance_audit;
create policy pdi_audit_read on public.pdi_performance_audit for select to authenticated
 using(pdi_performance_private.can_manage_sector(sector_snapshot,true));

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
revoke all on function pdi_performance_private.guard_daily_entry() from public,anon,authenticated;
drop trigger if exists pdi_guard_daily_entry on public.pdi_pcp_daily;
create trigger pdi_guard_daily_entry before insert or update or delete on public.pdi_pcp_daily
for each row execute function pdi_performance_private.guard_daily_entry();

create or replace function pdi_performance_private.audit_daily_entry()
returns trigger language plpgsql security definer set search_path=pg_catalog
as $$
declare row_data public.pdi_pcp_daily%rowtype; a public.profiles%rowtype;
begin
 if tg_op='DELETE' then row_data:=old; else row_data:=new; end if;
 select * into a from public.profiles where id=auth.uid();
 insert into public.pdi_performance_audit(entry_id,pcp_id,sector_snapshot,action,actor_id,actor_name,actor_role,database_actor,reason,before_data,after_data)
 values(row_data.id,row_data.pcp_id,row_data.sector_snapshot,tg_op,auth.uid(),coalesce(a.full_name,'Operação administrativa'),a.role,
   session_user||'/'||coalesce(current_setting('role',true),'none'),case when tg_op='UPDATE' then new.edit_reason else null end,
   case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
   case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end);
 if tg_op='DELETE' then return old; else return new; end if;
end $$;
revoke all on function pdi_performance_private.audit_daily_entry() from public,anon,authenticated;
drop trigger if exists pdi_audit_daily_entry on public.pdi_pcp_daily;
create trigger pdi_audit_daily_entry after insert or update or delete on public.pdi_pcp_daily
for each row execute function pdi_performance_private.audit_daily_entry();

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
revoke all on function public.pdi_desempenho_context() from public,anon;
grant execute on function public.pdi_desempenho_context() to authenticated;
drop policy if exists pdi_pcp_collect_guard on public.pdi_pcp_daily;
create policy pdi_pcp_collect_guard on public.pdi_pcp_daily as restrictive for insert to authenticated with check(pdi_performance_private.can_collect_performance());
drop policy if exists pdi_pcp_correct_guard on public.pdi_pcp_daily;
create policy pdi_pcp_correct_guard on public.pdi_pcp_daily as restrictive for update to authenticated using(pdi_performance_private.can_correct_sector(sector_snapshot)) with check(pdi_performance_private.can_correct_sector(sector_snapshot));
notify pgrst,'reload schema';
commit;
