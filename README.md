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
| Create and list series and characters | Working (one transaction via the `create_series` function; queues a season-plan job) |
| Add an episode by hand (owner): scenes + optional poll | Working (`add_episode` function) |
| Live voting, one vote per user | Working (Supabase) |
| Episode generation (Claude, images, voice, FFmpeg) | Planned — the status screen shows the real job queue, which waits for the worker |
| Episode player | Reads scenes from the database (animated stills + captions); real video planned |
| Cost per episode | Reads the `episode_costs` view (real data once the worker logs job costs) |

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
needed_files/        web/, pubspec.lock, test/ and config to copy into the project root
docs/                DartPad single-file demo (mock data, no backend)
.env.example         Server-side keys (never commit a real .env)
```

## Setup

Requires Flutter 3.19+ (Dart 3.3+).

```bash
git clone https://github.com/ardaceran/Soap-Opera-Studio.git
cd Soap-Opera-Studio
# copy the project files that live outside lib/ (web/, pubspec.lock, test/...)
cp -R needed_files/. .                         # Windows: Copy-Item -Recurse -Force needed_files\* .
flutter pub get
flutter run                                    # or: flutter run -d chrome
```

Build an Android APK: run `flutter create . --platforms=android,ios` once, then `flutter build apk`.
See `needed_files/README.md` for details.

## Roadmap (Demo Day)

- [ ] A 3-episode mini series with consistent characters
- [ ] Live audience vote that changes the next episode
- [ ] Cost per episode measured and shown
- [ ] Public deployment, demo video, technical report, user guide

## Safety and privacy

- KVKK consent at sign-up and a delete-my-account option.
- Moderation on generated content; real faces only with explicit consent.
- AI-generated content is labeled in the player.
