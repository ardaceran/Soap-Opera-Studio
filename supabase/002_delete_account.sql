-- Account deletion (KVKK right to erasure).
-- A security definer function so the app can delete its own account.
-- Deleting the auth.users row cascades to profiles, series, characters, votes...
-- Run once in the Supabase SQL Editor.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  delete from auth.users where id = auth.uid();
end $$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
