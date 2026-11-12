-- Real scene dialogue and job costs for the sample series "Red Villa (sample)".
-- Run after 003_seed_demo.sql. Safe to run more than once.
do $$
declare
  eid uuid;
  n int;
begin
  for eid in
    select e.id from public.episodes e
      join public.series s on s.id = e.series_id
     where s.title = 'Red Villa (sample)'
  loop
    select count(*) into n from public.scenes where episode_id = eid;
    if n = 0 then
      insert into public.scenes (episode_id, idx, dialogue, visual_prompt, is_key) values
        (eid, 1, 'Defne: My father''s will will be read in this room.', 'Defne enters a grand waterside mansion hall', false),
        (eid, 2, 'Nermin: This house has been my home for years.', 'Nermin stands at the top of the stairs', false),
        (eid, 3, 'Kerem: Nobody was supposed to find the letter.', 'Kerem hides an envelope in his coat', true),
        (eid, 4, 'Defne: So you knew everything all along.', 'Close-up of Defne, tears in her eyes', false),
        (eid, 5, 'Nermin: Meet me in the garden at midnight.', 'Moonlit garden, two silhouettes', false),
        (eid, 6, 'Narrator: The door slowly opened...', 'A dark door opens onto light', true);
    end if;
    if not exists (select 1 from public.jobs where episode_id = eid) then
      insert into public.jobs (episode_id, type, status, provider, cost_usd) values
        (eid, 'script', 'done', 'claude', 0.0120),
        (eid, 'image', 'done', 'fal', 0.2400),
        (eid, 'video', 'done', 'fal', 0.9000),
        (eid, 'voice', 'done', 'elevenlabs', 0.1500);
    end if;
  end loop;
end $$;
