-- Örnek veri: "Kırmızı Villa" dizisi, 2 yayınlanmış bölüm ve açık bir anket.
-- Supabase SQL Editor'da çalıştır. ÖNCE uygulamadan en az bir hesap oluşturmuş olmalısın
-- (dizi, ilk kayıtlı kullanıcıya bağlanır). Tekrar çalıştırırsan ikinci kopya oluşmaz.
do $$
declare
  uid uuid;
  sid uuid;
  eid uuid;
  pid uuid;
begin
  select id into uid from public.profiles order by created_at limit 1;
  if uid is null then
    raise exception 'Önce uygulamadan bir hesap oluştur, sonra bunu çalıştır.';
  end if;
  if exists (select 1 from public.series where title = 'Kırmızı Villa (örnek)') then
    raise notice 'Örnek veri zaten var.';
    return;
  end if;

  insert into public.series (owner_id, title, genre, setting)
  values (uid, 'Kırmızı Villa (örnek)', 'Dram', 'Boğaz''da eski bir yalı')
  returning id into sid;

  insert into public.characters (series_id, name, role) values
    (sid, 'Defne', 'Yalının varisi'),
    (sid, 'Kerem', 'Gizemli kâhya'),
    (sid, 'Nermin', 'Defne''nin teyzesi');

  insert into public.episodes (series_id, number, title, summary, status, published_at) values
    (sid, 1, 'Miras', 'Defne yalıya döner ve vasiyeti okunur.', 'published', now()),
    (sid, 2, 'Kilitli Oda', 'Kerem''in sakladığı oda ortaya çıkar.', 'published', now());

  select id into eid from public.episodes where series_id = sid and number = 2;

  insert into public.polls (episode_id, closes_at)
  values (eid, now() + interval '7 days') returning id into pid;

  insert into public.poll_options (poll_id, label) values
    (pid, 'Defne kilitli odayı açar'),
    (pid, 'Kerem sırrı itiraf eder'),
    (pid, 'Nermin vasiyeti yırtar');
end $$;
