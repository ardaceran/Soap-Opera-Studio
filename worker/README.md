# Generation worker

Reads the `jobs` table in Supabase and writes the story:

| Job | What happens |
| --- | --- |
| `season_plan` | Created when a user creates a series. The text model writes a 5-episode plan, saved to `series.season_plan`, then a `script` job for episode 1 is queued. |
| `script` | The text model writes 12–15 scenes and 3 poll options, using the season plan, earlier episode summaries and the winning vote of the previous episode. The episode, scenes and poll are published in one transaction (`worker_publish_episode`), then an `assemble` job is queued. |
| `assemble` | Makes the episode video (below) and saves it to Storage `episodes/<series>/<episode>.mp4`; `episodes.video_path` points to it. The vote clock starts now (`POLL_HOURS`, or `POLL_MINUTES` for a live demo). |

### Votes close by themselves

Every `POLL_CHECK_SECONDS` (30) the worker looks for votes whose time is up and that have
no winner. The option with the most votes wins (a tie, or no votes, goes to the option
listed first), and a `script` job for the next episode is queued with it, until the
season plan's last episode. The winner is written only if the poll has none yet, so two
workers never close the same vote twice.

### How an episode video is made

1. **Characters:** each character gets one fixed ElevenLabs voice and one reference
   portrait (fal.ai FLUX schnell), saved once in `characters.voice_id` / `ref_image_paths`
   and reused in every episode.
2. **Scenes:** a still per scene. If a character speaks, FLUX Kontext redraws them from
   their portrait so the face stays the same; narrator shots use the cheap model.
3. **Voice:** each line is spoken with the speaker's voice.
4. **FFmpeg:** slow zoom on each still (Ken Burns), captions with the speaker's name,
   an "AI-generated" label, a title card and a "what happens next?" vote card, joined
   into one 9:16 MP4 (H.264/AAC).
5. **Cost:** every call's cost is written to `jobs.cost_usd` with the episode id, so
   the `episode_costs` view shows the real cost per episode (Demo Day c).

Without `FAL_KEY` / `ELEVENLABS_API_KEY` the worker uses free placeholder cards and quiet
audio, so the whole flow can be tested at no cost.

Text models (`LLM_PROVIDER`): `claude` (needs `ANTHROPIC_API_KEY`, the default in `auto`
mode as the course brief asks for scripts by Claude), `gemini` (free tier, needs
`GEMINI_API_KEY`, development fallback) or `fake` (sample text, no key).
Not done yet: real video clips (Kling/Veo) for key scenes.

## Run

1. Run `supabase/008_worker.sql` once in the Supabase SQL Editor.
2. Copy `.env.example` (repo root) to `.env` and fill in `SUPABASE_SECRET_KEY`
   (and `ANTHROPIC_API_KEY`, or `GEMINI_API_KEY`, for real text; `FAL_KEY` and
   `ELEVENLABS_API_KEY` for real images and voice).
3. In the repo root: `docker compose up --build`
4. Create a series in the app. The worker log shows `season_plan` then `script`;
   episode 1 appears in the app with its poll.

On GitHub (no Docker needed): add the keys as repository secrets (Settings → Secrets
and variables → Actions: `SUPABASE_URL`, `SUPABASE_SECRET_KEY`, and optionally
`ANTHROPIC_API_KEY`, `FAL_KEY`, `ELEVENLABS_API_KEY`), then Actions → **Run worker** →
Run workflow. It runs for the chosen minutes (max 300).

Without Docker: `cd worker` then `python -m sos_worker` (Python 3.10+ and FFmpeg, with the
variables from `.env` set in the shell). `--once` handles the queue and exits.

## Tests

```bash
cd worker
python -m unittest discover -s tests
```

## Safety

- The secret key bypasses Row Level Security: keep it only in `.env` on your own machine.
- The prompt asks for family-friendly content; model output is trimmed and checked
  (known speakers, 8–20 scenes, 2–4 poll options) before it is published.
- If a free-tier model name stops working, change `GEMINI_MODEL` (see AI Studio).
