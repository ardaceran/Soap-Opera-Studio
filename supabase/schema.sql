-- Soap Opera Studio: Supabase schema
-- Scope: Project 13 from the course slides (Auth, story and vote data, media storage,
-- generation queue, series bible for RAG). Run in the Supabase SQL Editor.

create extension if not exists vector;

-- ---------------------------------------------------------------- tables

-- User profile (linked to Supabase Auth). KVKK consent time is stored here.
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  consent_at   timestamptz,
  created_at   timestamptz not null default now()
);

-- Series ("stories" on the slides): genre, setting, season plan
create table public.series (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  title       text not null,
  genre       text not null,
  setting     text not null,
  season_plan jsonb,
  created_at  timestamptz not null default now()
);

create table public.characters (
  id               uuid primary key default gen_random_uuid(),
  series_id        uuid not null references public.series (id) on delete cascade,
  name             text not null,
  role             text,
  description      text,          -- fixed visual description, added to every image request
  voice_id         text,          -- ElevenLabs voice id
  ref_image_paths  text[] not null default '{}',  -- Storage: character-refs
  created_at       timestamptz not null default now()
);

create table public.episodes (
  id           uuid primary key default gen_random_uuid(),
  series_id    uuid not null references public.series (id) on delete cascade,
  number       int  not null,
  title        text,
  script       jsonb,
  summary      text,              -- RAG summary for later episodes
  video_path   text,              -- Storage: episodes
  status       text not null default 'draft'
               check (status in ('draft', 'generating', 'published', 'failed')),
  published_at timestamptz,
  created_at   timestamptz not null default now(),
  unique (series_id, number)
);

create table public.scenes (
  id            uuid primary key default gen_random_uuid(),
  episode_id    uuid not null references public.episodes (id) on delete cascade,
  idx           int  not null,
  dialogue      text,
  visual_prompt text,
  is_key        boolean not null default false,   -- true: real video, false: animated still
  image_path    text,
  video_path    text,
  audio_path    text,
  unique (episode_id, idx)
);

-- Series bible: continuity via RAG (queried before writing an episode)
-- Adjust the embedding size to the embedding model you use.
create table public.series_bible (
  id         uuid primary key default gen_random_uuid(),
  series_id  uuid not null references public.series (id) on delete cascade,
  episode_id uuid references public.episodes (id) on delete set null,
  content    text not null,
  embedding  vector(1536),
  created_at timestamptz not null default now()
);
create index series_bible_embedding_idx
  on public.series_bible using hnsw (embedding vector_cosine_ops);

-- Voting: one poll at the end of each episode
create table public.polls (
  id                uuid primary key default gen_random_uuid(),
  episode_id        uuid not null unique references public.episodes (id) on delete cascade,
  closes_at         timestamptz not null,
  winner_option_id  uuid,
  created_at        timestamptz not null default now()
);

create table public.poll_options (
  id      uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls (id) on delete cascade,
  label   text not null
);

alter table public.polls
  add constraint polls_winner_fk
  foreign key (winner_option_id) references public.poll_options (id) on delete set null;

-- One vote per user per poll: the primary key guarantees it
create table public.votes (
  poll_id    uuid not null references public.polls (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  option_id  uuid not null references public.poll_options (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (poll_id, user_id)
);

-- Generation queue. Cost is stored here too: episode cost = sum of its jobs.
create table public.jobs (
  id          uuid primary key default gen_random_uuid(),
  series_id   uuid not null references public.series (id) on delete cascade,
  episode_id  uuid references public.episodes (id) on delete cascade,  -- null for season_plan
  scene_id    uuid references public.scenes (id) on delete cascade,
  type        text not null
              check (type in ('season_plan', 'script', 'moderation', 'image', 'video', 'voice', 'assemble')),
  status      text not null default 'queued'
              check (status in ('queued', 'running', 'done', 'failed')),
  attempts    int  not null default 0,
  error       text,
  provider    text,                       -- claude, fal, elevenlabs, ...
  cost_usd    numeric(10, 4) not null default 0,
  payload     jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index jobs_queue_idx on public.jobs (status, created_at);
create index jobs_series_idx on public.jobs (series_id);

-- ---------------------------------------------------------------- helpers

-- Profile row for a new user
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- KVKK consent comes from the sign-up metadata ({"kvkk_consent": true}).
  insert into public.profiles (id, display_name, consent_at)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)),
    case when (new.raw_user_meta_data ->> 'kvkk_consent') = 'true' then now() end
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- A worker safely claims the next job (two workers never take the same job)
create or replace function public.claim_next_job()
returns public.jobs language plpgsql security definer set search_path = public as $$
declare j public.jobs;
begin
  select * into j from public.jobs
   where status = 'queued'
   order by created_at
   for update skip locked
   limit 1;
  if not found then return null; end if;
  update public.jobs
     set status = 'running', attempts = attempts + 1, updated_at = now()
   where id = j.id
   returning * into j;
  return j;
end $$;
revoke all on function public.claim_next_job() from public, anon, authenticated;

-- Demo Day c): cost per episode
create or replace view public.episode_costs with (security_invoker = true) as
  select e.id as episode_id, e.series_id, e.number,
         coalesce(sum(j.cost_usd), 0) as cost_usd
    from public.episodes e
    left join public.jobs j on j.episode_id = e.id
   group by e.id;

-- Live vote counts (without revealing who voted), only for published episodes.
-- The view runs as its owner.
create or replace view public.poll_results as
  select o.poll_id, o.id as option_id, o.label, count(v.user_id) as votes
    from public.poll_options o
    join public.polls p    on p.id = o.poll_id
    join public.episodes e on e.id = p.episode_id and e.status = 'published'
    left join public.votes v on v.option_id = o.id
   group by o.id;
grant select on public.poll_results to anon, authenticated;

-- ---------------------------------------------------------------- RLS
alter table public.profiles     enable row level security;
alter table public.series       enable row level security;
alter table public.characters   enable row level security;
alter table public.episodes     enable row level security;
alter table public.scenes       enable row level security;
alter table public.series_bible enable row level security;
alter table public.polls        enable row level security;
alter table public.poll_options enable row level security;
alter table public.votes        enable row level security;
alter table public.jobs         enable row level security;

-- Note: the service role (worker, Edge Functions) bypasses RLS; generation writes are its job.

-- profiles: everyone sees and updates only their own profile
create policy profiles_select_own on public.profiles for select using (id = auth.uid());
create policy profiles_update_own on public.profiles for update using (id = auth.uid());

-- The series <-> episodes policies reference each other, so to avoid infinite recursion
-- the checks run in security definer functions (bypassing RLS).
create or replace function public.is_series_owner(sid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.series s where s.id = sid and s.owner_id = auth.uid());
$$;

create or replace function public.series_has_published(sid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.episodes e where e.series_id = sid and e.status = 'published');
$$;

-- series: the owner can do everything; a series with a published episode is visible to everyone
create policy series_owner_all on public.series for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy series_read_published on public.series for select
  using (public.series_has_published(id));

-- characters: belong to a visible series; only the series owner can write
create policy characters_read on public.characters for select
  using (exists (select 1 from public.series s where s.id = series_id));
create policy characters_owner_write on public.characters for all
  using (exists (select 1 from public.series s where s.id = series_id and s.owner_id = auth.uid()))
  with check (exists (select 1 from public.series s where s.id = series_id and s.owner_id = auth.uid()));

-- episodes: published ones are visible to everyone, drafts to the owner. Writes: service role
create policy episodes_read on public.episodes for select
  using (status = 'published' or public.is_series_owner(series_id));

-- scenes and polls: visible if the episode is visible
create policy scenes_read on public.scenes for select
  using (exists (select 1 from public.episodes e where e.id = episode_id));
create policy polls_read on public.polls for select
  using (exists (select 1 from public.episodes e where e.id = episode_id));
create policy poll_options_read on public.poll_options for select
  using (exists (select 1 from public.polls p where p.id = poll_id));

-- series_bible: only the series owner can read
create policy bible_owner_read on public.series_bible for select
  using (exists (select 1 from public.series s where s.id = series_id and s.owner_id = auth.uid()));

-- votes: a signed-in user casts one vote in their own name in an open poll
create policy votes_insert_own on public.votes for insert
  with check (user_id = auth.uid()
              and exists (select 1 from public.polls p
                           where p.id = poll_id and p.closes_at > now())
              and exists (select 1 from public.poll_options o
                           where o.id = option_id and o.poll_id = votes.poll_id));
create policy votes_select_own on public.votes for select using (user_id = auth.uid());

-- jobs: the series owner can watch the jobs of their own episodes (Realtime status screen)
create policy jobs_owner_read on public.jobs for select
  using (public.is_series_owner(series_id));

-- ---------------------------------------------------------------- storage
insert into storage.buckets (id, name, public) values
  ('character-refs', 'character-refs', false),
  ('scene-media',    'scene-media',    false),
  ('episodes',       'episodes',       true)
on conflict (id) do nothing;

-- character-refs: path starts with "<user_id>/..."; only the owner can read and write
create policy refs_owner_all on storage.objects for all
  using (bucket_id = 'character-refs' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'character-refs' and (storage.foldername(name))[1] = auth.uid()::text);
-- Writes to scene-media and episodes: service role (worker). episodes is publicly readable.

-- ---------------------------------------------------------------- realtime
alter publication supabase_realtime add table public.jobs;
alter publication supabase_realtime add table public.votes;

-- Account deletion function: run supabase/002_delete_account.sql after this file.

-- ---------------------------------------------------------------- rpc
Create a series, its characters and the first generation job in ONE
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

-- Owner adds an episode by hand (scenes + optional poll); the worker uses the same shape.
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
