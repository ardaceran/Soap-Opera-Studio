# Soap Opera Studio — Flutter app prototype

Flutter mobile app. Sign-in/sign-up, series creation/listing and voting are connected to
Supabase; episode generation, the player and the cost screen still use sample (mock) data.

## Run

```bash
flutter create soap_opera_studio --platforms=android,ios
cd soap_opera_studio
# copy lib/ and pubspec.yaml from this repo over the generated ones
rm test/widget_test.dart      # Windows: del test\widget_test.dart
flutter pub get
flutter run
```

Requires Flutter 3.19 or newer (Dart >= 3.3).

## Supabase

1. Run `supabase/schema.sql` in the Supabase SQL Editor.
2. Run `supabase/002_delete_account.sql` (account deletion, KVKK right to erasure).
3. Point the URL and publishable key in `lib/config.dart` to your own project.
4. Authentication > Providers > Email: "Confirm email" can be turned off during development.

Never put the `service_role` / secret key in the app or in the repo.
`docs/dartpad_main.dart` is a browser (DartPad) version with fake data and no Supabase.

## Voting and sample data

1. Run `supabase/003_seed_demo.sql` in the Supabase SQL Editor (create an account in the app first).
2. A "Vote" banner appears on the Series tab; votes are written to the `votes` table and
   results refresh every 3 seconds.

## Screens

| Screen | File | What it shows in the demo |
| --- | --- | --- |
| Login | `login_screen.dart` | Email/password, KVKK consent (sign-up blocked without it), guest browsing |
| Series | `home_screen.dart` | Series cards, open-poll banner |
| Series detail | `series_detail_screen.dart` | Characters (character lock), season plan, episode statuses |
| Create | `create_series_screen.dart` | Genre, setting, choosing 2–4 characters |
| Generation status | `generation_status_screen.dart` | The 8-step pipeline from the architecture (simulated) |
| Episode player | `episode_player_screen.dart` | 9:16, Ken Burns, captions, AI label |
| Voting | `vote_sheet.dart` | One vote per user, live percentages (Supabase) |
| Cost | `cost_panel_screen.dart` | Budget slider + real 0-1 knapsack: which scenes become video (mock) |
| Profile | `profile_screen.dart` | Display name, KVKK consent date, sign out, delete account |

## Next steps (backend)

- Replace the remaining mock data with real episodes and scenes
- Generation status: Realtime on the `jobs` table
- Cost: `episode_costs` view
- Worker: Claude season plan and scripts, fal.ai images, ElevenLabs voice, FFmpeg assembly
