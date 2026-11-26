-- 010: what is being generated right now for a series, for everyone who can see it.
-- Viewers cannot read the jobs table (it holds errors and costs); this function only
-- tells them which step is running and for which episode.
-- Run once in the Supabase SQL Editor (schema.sql already contains it for new projects).

create or replace function public.series_progress(p_series_id uuid)
returns table (type text, status text, episode int)
language sql stable security definer set search_path = public as $$
  select j.type, j.status, coalesce(e.number, (j.payload ->> 'episode')::int)
    from public.jobs j
    left join public.episodes e on e.id = j.episode_id
   where j.series_id = p_series_id
     and j.status in ('queued', 'running')
     and (public.is_series_owner(p_series_id) or public.series_has_published(p_series_id))
   order by j.created_at;
$$;
revoke all on function public.series_progress(uuid) from public;
grant execute on function public.series_progress(uuid) to anon, authenticated;
