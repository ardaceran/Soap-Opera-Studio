# AI Soap Opera Studio

A mobile app where anyone can create a short vertical-video soap opera with AI, and the
audience votes on what happens in the next episode.

Course project 13 — EBGR 4451 (Gen-AI / Mechatronics Lab, Dr. Orkun Karabaşoğlu).
Team: Arda Ceran and Mert.

## What the app does

1. **Sign in** with email and password (KVKK consent is required at sign-up).
2. **Create a series:** pick a genre, a setting and 2–4 characters.
3. **Generate episodes:** Claude writes the season arc and scripts; images, voice and
   captions are generated and assembled into a 60–90 second 9:16 episode.
4. **Vote:** viewers vote on the next episode's direction; the winning option goes into
   the next script. Results update live.
5. **Cost:** the cost of each episode is measured and shown.
6. **Privacy:** users can edit their profile and permanently delete their account and data.

## Status

| Feature | Status |
| --- | --- |
| Sign-in / sign-up, KVKK consent, account deletion | Working (Supabase Auth) |
| Create and list series and characters | Working (Supabase) |
| Live voting, one vote per user | Working (Supabase) |
| Episode generation (Claude, images, voice, FFmpeg) | Planned — the app shows a simulated pipeline |
| Episode player with real video | Planned — the app plays a mock episode |
| Cost per episode | Planned — mock screen; data model is ready (`episode_costs` view) |

## Architecture

```
Flutter app ──► Supabase (Auth, Postgres + RLS, Storage, Realtime)
                    ▲
                    │ job queue (`jobs` table)
                    │
                Worker (Docker) ──► Claude (season arc, scripts, scene list)
                                ├─► fal.ai (Flux images, Kling/Veo key shots)
                                ├─► ElevenLabs (voice)
                                └─► FFmpeg (captions, 1080×1920 assembly)
```

- Series bible with `pgvector` (RAG) keeps continuity between episodes.
- Most scenes are animated stills; real video is used only for key moments.
- Row Level Security protects all data; the worker uses the service role on the server side only.

## Project layout

```
lib/                 Flutter app (screens, Supabase access in repository.dart)
supabase/            SQL: schema.sql, 002_delete_account.sql, 003_seed_demo.sql
docs/                DartPad single-file demo (mock data, no backend)
.env.example         Server-side keys (never commit a real .env)
```

## Setup

### 1. Flutter app

Requires Flutter 3.19+ (Dart 3.3+).

```bash
git clone https://github.com/ardaceran/Soap-Opera-Studio.git
cd Soap-Opera-Studio
flutter create . --platforms=android,ios,web   # generates the platform folders
rm test/widget_test.dart                       # Windows: del test\widget_test.dart
flutter pub get
flutter run                                    # or: flutter run -d chrome
```

Build an Android APK: `flutter build apk`.

### 2. Supabase

1. Create a project and run the SQL files in the SQL Editor, in order:
   `supabase/schema.sql`, `supabase/002_delete_account.sql`.
2. Authentication > Providers > Email: turn "Confirm email" off during development.
3. Put your project URL and **publishable** key in `lib/config.dart`.
4. Optional sample data: create an account in the app, then run `supabase/003_seed_demo.sql`.

### 3. Secrets

- The publishable key in `lib/config.dart` is safe to ship; security comes from RLS.
- Copy `.env.example` to `.env` for the worker. **Never commit `.env`**, and never put the
  `service_role` / secret key, the database password or any API key in the app or the repo.
- Set a spending limit on every paid API (Anthropic, fal.ai, ElevenLabs).

## Roadmap (Demo Day)

- [ ] A 3-episode mini series with consistent characters
- [ ] Live audience vote that changes the next episode
- [ ] Cost per episode measured and shown
- [ ] Public deployment, demo video, technical report, user guide

## Safety and privacy

- KVKK consent at sign-up and a delete-my-account option.
- Moderation on generated content; real faces only with explicit consent.
- AI-generated content is labeled in the player.
