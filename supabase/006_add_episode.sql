-- 006: let the series owner add an episode by hand (scenes + optional poll).
-- Later the generation worker will add episodes the same way.
-- Run once in the Supabase SQL Editor (schema.sql already contains it for new projects).

create or replace function public.add_episode(
  p_series_id    uuid,
  p_title        text,
  p_summary      text,
  p_lines        text[],          -- one dialogue line per scene, e.g. 'Defne: Hello'
  p_poll_options text[],          -- empty, or 2 to 4 options for the next episode
  p_poll_hours   int default 24)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  eid   uuid;
  pid   uuid;
  num   int;
  n     int := coalesce(array_length(p_lines, 1), 0);
  nopts int := coalesce(array_length(p_poll_options, 1), 0);
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  if not public.is_series_owner(p_series_id) then
    raise exception 'Only the owner of the series can add episodes';
  end if;
  if coalesce(trim(p_title), '') = '' then
    raise exception 'An episode title is required';
  end if;
  if n < 1 or n > 30 then
    raise exception 'An episode needs 1 to 30 scenes';
  end if;
  if nopts not in (0, 2, 3, 4) then
    raise exception 'A poll needs 2 to 4 options';
  end if;
  if p_poll_hours < 1 or p_poll_hours > 168 then
    raise exception 'Poll duration must be 1 to 168 hours';
  end if;

  select coalesce(max(number), 0) + 1 into num
    from public.episodes where series_id = p_series_id;

  insert into public.episodes (series_id, number, title, summary, status, published_at)
  values (p_series_id, num, trim(p_title), nullif(trim(p_summary), ''), 'published', now())
  returning id into eid;

  insert into public.scenes (episode_id, idx, dialogue)
  select eid, i, trim(p_lines[i])
    from generate_subscripts(p_lines, 1) i;

  if nopts > 0 then
    insert into public.polls (episode_id, closes_at)
    values (eid, now() + make_interval(hours => p_poll_hours))
    returning id into pid;

    insert into public.poll_options (poll_id, label)
    select pid, trim(o) from unnest(p_poll_options) o;
  end if;

  return eid;
end $$;
revoke all on function public.add_episode(uuid, text, text, text[], text[], int) from public, anon;
grant execute on function public.add_episode(uuid, text, text, text[], text[], int) to authenticated;
