-- Soap Opera Studio: Supabase schema
-- Kapsam: ders slaytındaki Project 13 (Auth, hikaye ve oy verisi, medya depolama,
-- üretim kuyruğu, RAG için series bible). Supabase SQL Editor'da çalıştır.

create extension if not exists vector;

-- ---------------------------------------------------------------- tables

-- Kullanıcı profili (Supabase Auth'a bağlı). KVKK onay zamanı burada.
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  consent_at   timestamptz,
  created_at   timestamptz not null default now()
);

-- Dizi (slaytta "stories"): tür, mekân, sezon planı
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
  description      text,          -- sabit görsel tarifi, her görsel isteğine eklenir
  voice_id         text,          -- ElevenLabs ses kimliği
  ref_image_paths  text[] not null default '{}',  -- Storage: character-refs
  created_at       timestamptz not null default now()
);

create table public.episodes (
  id           uuid primary key default gen_random_uuid(),
  series_id    uuid not null references public.series (id) on delete cascade,
  number       int  not null,
  title        text,
  script       jsonb,
  summary      text,              -- sonraki bölümler için RAG özeti
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
  is_key        boolean not null default false,   -- true: gerçek video, false: hareketli still
  image_path    text,
  video_path    text,
  audio_path    text,
  unique (episode_id, idx)
);

-- Series bible: RAG ile devamlılık (bölüm yazmadan önce buradan çekilir)
-- embedding boyutunu kullandığın embedding modeline göre ayarla.
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

-- Oylama: her bölümün sonunda bir anket
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

-- Bir kullanıcı bir ankette bir oy: birincil anahtar bunu garanti eder
create table public.votes (
  poll_id    uuid not null references public.polls (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  option_id  uuid not null references public.poll_options (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (poll_id, user_id)
);

-- Üretim kuyruğu. Maliyet de burada tutulur: bölüm maliyeti = işlerin toplamı.
create table public.jobs (
  id          uuid primary key default gen_random_uuid(),
  episode_id  uuid not null references public.episodes (id) on delete cascade,
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

-- ---------------------------------------------------------------- helpers

-- Yeni kullanıcı için profil satırı
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)));
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Worker bir sonraki işi güvenle alır (aynı işi iki worker almaz)
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

-- Demo Day c): bölüm başına maliyet
create or replace view public.episode_costs with (security_invoker = true) as
  select e.id as episode_id, e.series_id, e.number,
         coalesce(sum(j.cost_usd), 0) as cost_usd
    from public.episodes e
    left join public.jobs j on j.episode_id = e.id
   group by e.id;

-- Canlı oy sayıları (oy verenleri göstermeden). View sahibi olarak çalışır.
create or replace view public.poll_results as
  select o.poll_id, o.id as option_id, o.label, count(v.user_id) as votes
    from public.poll_options o
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

-- Not: service role (worker, Edge Functions) RLS'i atlar; üretim yazmaları onun işi.

-- profiles: herkes sadece kendi profilini görür ve günceller
create policy profiles_select_own on public.profiles for select using (id = auth.uid());
create policy profiles_update_own on public.profiles for update using (id = auth.uid());

-- series <-> episodes politikaları birbirine baktığı için sonsuz özyineleme olmasın diye
-- kontroller security definer fonksiyonlarda (RLS'i atlayarak) yapılır.
create or replace function public.is_series_owner(sid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.series s where s.id = sid and s.owner_id = auth.uid());
$$;

create or replace function public.series_has_published(sid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.episodes e where e.series_id = sid and e.status = 'published');
$$;

-- series: sahibi her şeyi yapar; yayınlanmış bölümü olan seri herkese görünür
create policy series_owner_all on public.series for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy series_read_published on public.series for select
  using (public.series_has_published(id));

-- characters: görünür seriye aittir; yazmayı yalnızca seri sahibi yapar
create policy characters_read on public.characters for select
  using (exists (select 1 from public.series s where s.id = series_id));
create policy characters_owner_write on public.characters for all
  using (exists (select 1 from public.series s where s.id = series_id and s.owner_id = auth.uid()))
  with check (exists (select 1 from public.series s where s.id = series_id and s.owner_id = auth.uid()));

-- episodes: yayınlanmışlar herkese, taslaklar sahibine. Yazma: service role
create policy episodes_read on public.episodes for select
  using (status = 'published' or public.is_series_owner(series_id));

-- scenes ve anketler: bölüm görünürse görünür
create policy scenes_read on public.scenes for select
  using (exists (select 1 from public.episodes e where e.id = episode_id));
create policy polls_read on public.polls for select
  using (exists (select 1 from public.episodes e where e.id = episode_id));
create policy poll_options_read on public.poll_options for select
  using (exists (select 1 from public.polls p where p.id = poll_id));

-- series_bible: sadece seri sahibi okur
create policy bible_owner_read on public.series_bible for select
  using (exists (select 1 from public.series s where s.id = series_id and s.owner_id = auth.uid()));

-- votes: giriş yapan kullanıcı, açık ankette, kendi adına bir oy atar
create policy votes_insert_own on public.votes for insert
  with check (user_id = auth.uid()
              and exists (select 1 from public.polls p
                           where p.id = poll_id and p.closes_at > now())
              and exists (select 1 from public.poll_options o
                           where o.id = option_id and o.poll_id = votes.poll_id));
create policy votes_select_own on public.votes for select using (user_id = auth.uid());

-- jobs: seri sahibi kendi bölümlerinin işlerini izleyebilir (Realtime durum ekranı)
create policy jobs_owner_read on public.jobs for select
  using (exists (select 1 from public.episodes e
                   join public.series s on s.id = e.series_id
                  where e.id = episode_id and s.owner_id = auth.uid()));

-- ---------------------------------------------------------------- storage
insert into storage.buckets (id, name, public) values
  ('character-refs', 'character-refs', false),
  ('scene-media',    'scene-media',    false),
  ('episodes',       'episodes',       true)
on conflict (id) do nothing;

-- character-refs: yol "<user_id>/..." ile başlar, yalnızca sahibi okur ve yazar
create policy refs_owner_all on storage.objects for all
  using (bucket_id = 'character-refs' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'character-refs' and (storage.foldername(name))[1] = auth.uid()::text);
-- scene-media ve episodes'e yazma: service role (worker). episodes herkese okunur.

-- ---------------------------------------------------------------- realtime
alter publication supabase_realtime add table public.jobs;
alter publication supabase_realtime add table public.votes;

-- Hesap silme fonksiyonu: ayrıca supabase/002_delete_account.sql içinde (mevcut projeye eklemek için).
