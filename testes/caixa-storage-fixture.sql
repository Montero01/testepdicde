-- APENAS PostgreSQL local. Não imita um upload físico; testa as regras de metadados/RLS.
create schema storage;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),name text,metadata jsonb,owner_id text,unique(bucket_id,name));
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated,anon;
grant all on storage.objects to authenticated,anon;
-- Reproduz permissões globais antigas para testar o isolamento restritivo.
create policy legacy_select on storage.objects for select to public using(true);
create policy legacy_write on storage.objects for insert to public with check(true);
create policy legacy_update on storage.objects for update to public using(true) with check(true);
create policy legacy_delete on storage.objects for delete to public using(true);
insert into storage.buckets(id,name,public) values('avatars','avatars',true);
insert into storage.objects(bucket_id,name,metadata) values('avatars','public.png','{}');
insert into public.profiles(id,full_name,role,sector,position) values
('00000000-0000-0000-0000-000000000020','Caixa A','employee','ADMINISTRATIVO','Op. de Caixa'),
('00000000-0000-0000-0000-000000000021','Caixa B','employee','ADMINISTRATIVO','Operadora de Caixa'),
('00000000-0000-0000-0000-000000000022','Supervisão Caixa','supervisor','ADMINISTRATIVO','Supervisão'),
('00000000-0000-0000-0000-000000000023','Gerência Caixa','gerente','ADMINISTRATIVO','Gerente');
