begin;
create or replace function public.club_summary() returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if private.current_role() not in ('admin','operator') or private.current_role() is null then raise insufficient_privilege; end if;
 return jsonb_build_object(
 'stations',(select count(*) from public.stations where deleted_at is null),
 'customers',(select count(*) from public.customers where deleted_at is null),
 'active_sessions',(select count(*) from public.sessions where deleted_at is null and finished_at is null),
 'revenue',(select coalesce(sum(amount),0) from public.payments where deleted_at is null and state='received'));
end $$;
notify pgrst,'reload schema';
commit;
