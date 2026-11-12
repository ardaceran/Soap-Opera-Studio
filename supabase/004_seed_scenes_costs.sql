-- Sample scene dialogue and placeholder job costs for "Red Villa (sample)".
-- Run after 003_seed_demo.sql and 005_fixes.sql. Safe to run more than once.
-- The costs are placeholder demo numbers, not measured costs.
do $$
declare
  eid uuid;
  sid uuid;
  n int;
begin
  for eid, sid in
    select e.id, e.series_id from public.episodes e
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
      insert into public.jobs (series_id, episode_id, type, status, provider, cost_usd) values
        (sid, eid, 'script', 'done', 'claude', 0.0120),
        (sid, eid, 'image', 'done', 'fal', 0.2400),
        (sid, eid, 'video', 'done', 'fal', 0.9000),
        (sid, eid, 'voice', 'done', 'elevenlabs', 0.1500);
    end if;
  end loop;
end $$;
