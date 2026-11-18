-- 008: database functions used by the generation worker (service role only).
-- Run once in the Supabase SQL Editor (schema.sql already contains it for new projects).

-- The worker claims jobs with the secret (service role) key.
grant execute on function public.claim_next_job() to service_role;

-- Publish one generated episode in ONE transaction: the episode (insert, or
-- overwrite a draft with the same number), its scenes, an optional poll for
-- the next episode, and a short summary in the series bible for continuity.
create or replace function public.worker_publish_episode(
  p_series_id    uuid,
  p_number       int,
  p_title        text,
  p_summary      text,
  p_scenes       jsonb,           -- [{"dialogue": "Defne: ...", "visual": "..."}]
  p_poll_options text[],          -- empty, or 2 to 4 options
  p_poll_hours   int default 24)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  eid uuid;
  pid uuid;
  n   int := jsonb_array_length(coalesce(p_scenes, '[]'::jsonb));
  k   int := coalesce(array_length(p_poll_options, 1), 0);
begin
  if n < 1 then
    raise exception 'An episode needs at least one scene';
  end if;
  if k not in (0, 2, 3, 4) then
    raise exception 'A poll needs 2 to 4 options';
  end if;

  insert into public.episodes (series_id, number, title, summary, status, published_at)
  values (p_series_id, p_number, p_title, p_summary, 'published', now())
  on conflict (series_id, number) do update
     set title = excluded.title, summary = excluded.summary,
         status = 'published', published_at = now()
  returning id into eid;

  delete from public.scenes where episode_id = eid;
  insert into public.scenes (episode_id, idx, dialogue, visual_prompt)
  select eid, s.ord::int, s.value ->> 'dialogue', s.value ->> 'visual'
    from jsonb_array_elements(p_scenes) with ordinality as s(value, ord);

  delete from public.polls where episode_id = eid;
  if k > 0 then
    insert into public.polls (episode_id, closes_at)
    values (eid, now() + make_interval(hours => p_poll_hours))
    returning id into pid;
    insert into public.poll_options (poll_id, label)
    select pid, trim(o) from unnest(p_poll_options) o;
  end if;

  if coalesce(trim(p_summary), '') <> '' then
    delete from public.series_bible where episode_id = eid;
    insert into public.series_bible (series_id, episode_id, content)
    values (p_series_id, eid, 'Episode ' || p_number || ': ' || p_summary);
  end if;

  return eid;
end $$;
revoke all on function public.worker_publish_episode(uuid, int, text, text, jsonb, text[], int)
  from public, anon, authenticated;
grant execute on function public.worker_publish_episode(uuid, int, text, text, jsonb, text[], int)
  to service_role;
