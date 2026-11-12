-- 007: demo scenario for presentations (hand-written, not AI-generated).
-- "The Red Villa (demo)": 3 characters, 2 published episodes with scenes,
-- episode 1's poll is closed and its winner drives episode 2, episode 2's poll
-- is open for 3 days, episode 3 is still a draft.
-- Attached to the first registered account. Safe to run more than once.
do $$
declare
  uid  uuid;
  sid  uuid;
  e1   uuid;
  e2   uuid;
  p1   uuid;
  p2   uuid;
  win  uuid;
begin
  select id into uid from public.profiles order by created_at limit 1;
  if uid is null then
    raise exception 'Create an account in the app first, then run this.';
  end if;
  if exists (select 1 from public.series where title = 'The Red Villa (demo)') then
    raise notice 'Demo scenario already exists.';
    return;
  end if;

  insert into public.series (owner_id, title, genre, setting)
  values (uid, 'The Red Villa (demo)', 'Drama', 'An old waterside mansion on the Bosphorus')
  returning id into sid;

  insert into public.characters (series_id, name, role) values
    (sid, 'Defne',  'Heir of the mansion'),
    (sid, 'Kerem',  'The family lawyer'),
    (sid, 'Nermin', 'Defne''s aunt');

  -- Episode 1 ---------------------------------------------------------------
  insert into public.episodes (series_id, number, title, summary, status, published_at)
  values (sid, 1, 'The Will',
          'Defne comes home for her father''s will and finds a door nobody will open.',
          'published', now() - interval '2 days')
  returning id into e1;

  insert into public.scenes (episode_id, idx, dialogue) values
    (e1,  1, 'Narrator: Twelve years after she left, Defne returns to the Red Villa.'),
    (e1,  2, 'Nermin: You came. I was starting to think you never would.'),
    (e1,  3, 'Defne: My father asked for me. I am here for him, not for the house.'),
    (e1,  4, 'Kerem: The will is short. Almost everything goes to Defne.'),
    (e1,  5, 'Nermin: Everything? After thirty years in this house?'),
    (e1,  6, 'Kerem: There is one condition. The east room stays locked for a year.'),
    (e1,  7, 'Defne: Locked? What is in the east room?'),
    (e1,  8, 'Kerem: He did not say. Only that you would understand.'),
    (e1,  9, 'Nermin: Your father was a sentimental old fool.'),
    (e1, 10, 'Narrator: That night, Defne finds a key taped under her father''s desk.'),
    (e1, 11, 'Defne: A key... and the east room is right down the hall.'),
    (e1, 12, 'Narrator: What should Defne do next?');

  insert into public.polls (episode_id, closes_at)
  values (e1, now() - interval '1 day')
  returning id into p1;

  insert into public.poll_options (poll_id, label) values
    (p1, 'Defne opens the locked room tonight'),
    (p1, 'Defne gives the key to Kerem'),
    (p1, 'Defne hides the key from Nermin');

  select id into win from public.poll_options
   where poll_id = p1 and label = 'Defne opens the locked room tonight';
  update public.polls set winner_option_id = win where id = p1;

  -- Episode 2 (follows the winning option) -----------------------------------
  insert into public.episodes (series_id, number, title, summary, status, published_at)
  values (sid, 2, 'The Locked Room',
          'Viewers chose: Defne opens the locked room. What she finds changes everything.',
          'published', now() - interval '1 hour')
  returning id into e2;

  insert into public.scenes (episode_id, idx, dialogue) values
    (e2,  1, 'Narrator: Viewers decided. At midnight, Defne turns the key.'),
    (e2,  2, 'Defne: Dust, old photographs... and a cradle?'),
    (e2,  3, 'Narrator: On the wall, a photo of her father holding a baby that is not Defne.'),
    (e2,  4, 'Kerem: You should not be in here. Not yet.'),
    (e2,  5, 'Defne: You knew. You knew about this room all along.'),
    (e2,  6, 'Kerem: Your father made me promise. I keep my promises.'),
    (e2,  7, 'Defne: Who is the child, Kerem?'),
    (e2,  8, 'Kerem: Someone who has a right to half of this house.'),
    (e2,  9, 'Narrator: Downstairs, a light goes out. Someone was listening.'),
    (e2, 10, 'Nermin: So the girl found the room. Good. Now it begins.'),
    (e2, 11, 'Defne: Tomorrow I want the whole truth. From everyone.'),
    (e2, 12, 'Narrator: Who will Defne turn to first?');

  insert into public.polls (episode_id, closes_at)
  values (e2, now() + interval '3 days')
  returning id into p2;

  insert into public.poll_options (poll_id, label) values
    (p2, 'Defne confronts Nermin at dinner'),
    (p2, 'Defne trusts Kerem and asks for the letters'),
    (p2, 'Defne searches for the missing child alone');

  -- Episode 3: waiting for the vote (draft, visible only to the owner) ------
  insert into public.episodes (series_id, number, title, summary, status)
  values (sid, 3, 'Confrontation',
          'Written after the episode 2 vote closes.', 'draft');
end $$;
