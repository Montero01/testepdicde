-- Complemento do módulo PCP: dashboard exclusivo da supervisão e gestão.
-- Somente leitura. Instale depois de desempenho-pcp.sql.
begin;
create or replace function public.pdi_pcp_dashboard(p_start_date date,p_end_date date,p_pcp_id uuid default null)
returns jsonb language plpgsql stable security invoker set search_path=pg_catalog
as $$
declare a public.profiles%rowtype; global_access boolean; payload jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.' using errcode='42501'; end if;
 select * into a from public.profiles where id=auth.uid();
 global_access:=coalesce(a.is_master,false) or lower(btrim(coalesce(a.role,''))) in ('master','diretor','diretoria');
 if a.id is null or not (global_access or lower(btrim(coalesce(a.role,''))) in ('supervisor','gerente')) then
   raise exception 'Dashboard restrito à supervisão e gestão.' using errcode='42501';
 end if;
 if p_start_date is null or p_end_date is null or not isfinite(p_start_date) or not isfinite(p_end_date) or p_start_date>p_end_date then
   raise exception 'Selecione um período válido.' using errcode='22023';
 end if;
 -- RLS permanece ativa. O escopo explícito também evita que a exceção de
 -- leitura dos próprios registros inclua um setor antigo de um gestor-PCP.
 with filtered as materialized (
   select d.id,d.pcp_id,d.work_date,d.m2_saved,d.pcp_name_snapshot,d.updated_at
   from public.pdi_pcp_daily d
   where d.work_date between p_start_date and p_end_date
     and (p_pcp_id is null or d.pcp_id=p_pcp_id)
     and (global_access or (a.sector is not null and d.sector_snapshot=a.sector))
 ), grouped as (
   select f.pcp_id,sum(f.m2_saved) as total_m2,count(*) as entries,
     (array_agg(f.pcp_name_snapshot order by f.work_date desc,f.updated_at desc,f.id desc))[1] as name
   from filtered f group by f.pcp_id
 ), ranked as (
   select g.*,dense_rank() over(order by g.total_m2 desc) as place,
     coalesce(round(g.total_m2/nullif(sum(g.total_m2) over(),0)*100,2),0) as share_percent,
     coalesce(round(g.total_m2/nullif(max(g.total_m2) over(),0)*100,2),0) as bar_percent
   from grouped g
 )
 select jsonb_build_object(
   'start_date',p_start_date,'end_date',p_end_date,'pcp_id',p_pcp_id,'updated_at',statement_timestamp(),
   'total_m2',coalesce(sum(r.total_m2),0)::text,
   'pcp_count',count(*),'entry_count',coalesce(sum(r.entries),0),
   'ranking',coalesce(jsonb_agg(jsonb_build_object(
     'pcp_id',r.pcp_id,'name',r.name,'total_m2',r.total_m2::text,'entry_count',r.entries,
     'place',r.place,'share_percent',r.share_percent::text,'bar_percent',r.bar_percent::text
   ) order by r.total_m2 desc,r.name,r.pcp_id),'[]'::jsonb)
 ) into payload from ranked r;
 return payload;
end $$;
revoke all on function public.pdi_pcp_dashboard(date,date,uuid) from public,anon;
grant execute on function public.pdi_pcp_dashboard(date,date,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
