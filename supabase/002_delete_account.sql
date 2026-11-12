-- Hesabı silme (KVKK silme hakkı).
-- Uygulama kendi hesabını silebilsin diye security definer fonksiyonu.
-- auth.users satırı silinince profiles, series, characters, votes... cascade ile silinir.
-- Supabase SQL Editor'da bir kez çalıştır.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Giriş yapılmamış';
  end if;
  delete from auth.users where id = auth.uid();
end $$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
