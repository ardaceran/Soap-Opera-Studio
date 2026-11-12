-- Sample data: the "Red Villa" series, 2 published episodes and an open poll.
-- Run in the Supabase SQL Editor. You must have created at least one account in the app FIRST
-- (the series is attached to the first registered user). Running it again will not create a second copy.
do $$
declare
  uid uuid;
  sid uuid;
  eid uuid;
  pid uuid;
begin
  select id into uid from public.profiles order by created_at limit 1;
  if uid is null then
    raise exception 'Create an account in the app first, then run this.';
  end if;
  if exists (select 1 from public.series where title = 'Red Villa (sample)') then
    raise notice 'Sample data already exists.';
    return;
  end if;

  insert into public.series (owner_id, title, genre, setting)
  values (uid, 'Red Villa (sample)', 'Drama', 'An old waterside mansion on the Bosphorus')
  returning id into sid;

  insert into public.characters (series_id, name, role) values
    (sid, 'Defne', 'Heir of the mansion'),
    (sid, 'Kerem', 'Mysterious steward'),
    (sid, 'Nermin', 'Defne''s aunt');

  insert into public.episodes (series_id, number, title, summary, status, published_at) values
    (sid, 1, 'Inheritance', 'Defne returns to the mansion and the will is read.', 'published', now()),
    (sid, 2, 'The Locked Room', 'The room Kerem has been hiding is revealed.', 'published', now());

  select id into eid from public.episodes where series_id = sid and number = 2;

  insert into public.polls (episode_id, closes_at)
  values (eid, now() + interval '7 days') returning id into pid;

  insert into public.poll_options (poll_id, label) values
    (pid, 'Defne opens the locked room'),
    (pid, 'Kerem confesses the secret'),
    (pid, 'Nermin tears up the will');
end $$;
