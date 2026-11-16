do $$ begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if; end $$;
do $$ begin if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if; end $$;
do $$ begin if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if; end $$;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to anon,authenticated,service_role;
grant execute on function auth.uid() to anon,authenticated,service_role;
create table public.profiles(id uuid primary key,full_name text,email text,role text,sector text,position text,is_master boolean default false,is_professor boolean default false,avatar_url text,created_at timestamptz default now());
alter table public.profiles enable row level security;
create policy legacy_all on public.profiles for all to authenticated using(true) with check(true);
grant all on public.profiles to authenticated,anon,service_role;
insert into public.profiles(id,full_name,role,sector,position,is_master) values
('00000000-0000-0000-0000-000000000001','PCP A','employee','PRODUÇÃO','PCP',false),
('00000000-0000-0000-0000-000000000002','PCP B','employee','PRODUÇÃO',' pcp ',false),
('00000000-0000-0000-0000-000000000003','Supervisor','supervisor','PRODUÇÃO','Líder',false),
('00000000-0000-0000-0000-000000000004','Gerente','gerente','PRODUÇÃO','Gerente',false),
('00000000-0000-0000-0000-000000000005','Outra gerência','gerente','COMERCIAL','Gerente',false),
('00000000-0000-0000-0000-000000000006','Diretoria','diretoria','ADMINISTRATIVO','Diretor',false),
('00000000-0000-0000-0000-000000000007','Outro PCP','employee','COMERCIAL','PCP',false),
('00000000-0000-0000-0000-000000000008','Caixa','employee','ADMINISTRATIVO','Caixa',false),
('00000000-0000-0000-0000-000000000009','Master','gerente','ADMINISTRATIVO','Assessoria',true);
