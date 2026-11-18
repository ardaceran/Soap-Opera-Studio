# Generation worker

Reads the `jobs` table in Supabase and writes the story:

| Job | What happens |
| --- | --- |
| `season_plan` | Created when a user creates a series. The text model writes a 5-episode plan, saved to `series.season_plan`, then a `script` job for episode 1 is queued. |
| `script` | The text model writes 12–15 scenes and 3 poll options, using the season plan, earlier episode summaries and the winning vote of the previous episode. The episode, scenes and poll are published in one transaction (`worker_publish_episode`). |

Text models: `gemini` (free tier, needs `GEMINI_API_KEY`) or `fake` (sample text, no key).
Not done yet: closing polls automatically, images, voice, video assembly.

## Run

1. Run `supabase/008_worker.sql` once in the Supabase SQL Editor.
2. Copy `.env.example` (repo root) to `.env` and fill in `SUPABASE_SECRET_KEY`
   (and `GEMINI_API_KEY` for real text).
3. In the repo root: `docker compose up --build`
4. Create a series in the app. The worker log shows `season_plan` then `script`;
   episode 1 appears in the app with its poll.

Without Docker: `cd worker` then `python -m sos_worker` (Python 3.10+, with the
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
