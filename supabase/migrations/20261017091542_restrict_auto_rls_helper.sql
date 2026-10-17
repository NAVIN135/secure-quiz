-- Supabase may create this event-trigger helper when automatic RLS is enabled.
-- It is not a client RPC and does not need anon/authenticated execution.
do $$
begin
 if to_regprocedure('public.rls_auto_enable()') is not null then
  revoke execute on function public.rls_auto_enable() from public,anon,authenticated;
 end if;
end $$;
