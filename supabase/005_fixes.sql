-- 005: fixes found in the code review. Run once in the Supabase SQL Editor on an
-- existing project (schema.sql already contains all of this for new projects).
-- Safe to run more than once.

-- 1) Job queue: a season-plan job exists before any episode, so jobs belong to a
--    series and only optionally to an episode.
alter table public.jobs add column if not exists series_id uuid
  references public.series (id) on delete cascade;
update public.jobs j set series_id = e.series_id
  from public.episodes e
 where j.episode_id = e.id and j.series_id is null;
alter table public.jobs alter column series_id set not null;
alter table public.jobs alter column episode_id drop not null;
create index if not exists jobs_series_idx on public.jobs (series_id);

drop policy if exists jobs_owner_read on public.jobs;
create policy jobs_owner_read on public.jobs for select
  using (public.is_series_owner(series_id));

-- 2) Live vote counts only for polls on published episodes (drafts stay hidden).
create or replace view public.poll_results as
  select o.poll_id, o.id as option_id, o.label, count(v.user_id) as votes
    from public.poll_options o
    join public.polls p    on p.id = o.poll_id
    join public.episodes e on e.id = p.episode_id and e.status = 'published'
    left join public.votes v on v.option_id = o.id
   group by o.id;
grant select on public.poll_results to anon, authenticated;

-- 3) KVKK consent is written at sign-up, also when "Confirm email" is on.
--    The app sends {"kvkk_consent": true} as user metadata.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, consent_at)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)),
    case when (new.raw_user_meta_data ->> 'kvkk_consent') = 'true' then now() end
  );
  return new;
end $$;

-- 4) Create a series, its characters and the first generation job in ONE
--    transaction, so a failure never leaves a half-saved series.
create or replace function public.create_series(
  p_title text, p_genre text, p_setting text, p_characters jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  sid uuid;
  n   int := jsonb_array_length(coalesce(p_characters, '[]'::jsonb));
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  if coalesce(trim(p_title), '') = '' then
    raise exception 'A series title is required';
  end if;
  if n < 2 or n > 4 then
    raise exception 'A series needs 2 to 4 characters';
  end if;

  insert into public.series (owner_id, title, genre, setting)
  values (auth.uid(), trim(p_title), p_genre, p_setting)
  returning id into sid;

  insert into public.characters (series_id, name, role)
  select sid, trim(c ->> 'name'), c ->> 'role'
    from jsonb_array_elements(p_characters) c;

  -- The worker picks this up and writes the season plan.
  insert into public.jobs (series_id, type) values (sid, 'season_plan');

  return sid;
end $$;
revoke all on function public.create_series(text, text, text, jsonb) from public, anon;
grant execute on function public.create_series(text, text, text, jsonb) to authenticated;
