"""Worker loop: claim a job, run it, mark it done or failed, repeat.

Run:  python -m sos_worker          (keeps running)
      python -m sos_worker --once   (handles queued jobs, then exits)
"""

import sys
import time
import traceback

from .config import Config
from .db import Db
from .llm import TransientLLMError, make_llm
from .media import make_media
from .pipeline import Pipeline


def log(msg: str) -> None:
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def main() -> None:
    once = "--once" in sys.argv
    cfg = Config.from_env()
    db = Db(cfg)
    llm = make_llm(cfg)
    images, voice = make_media(cfg)
    pipe = Pipeline(db, llm, cfg.poll_hours, images, voice,
                    cfg.video_height, cfg.max_scenes,
                    (cfg.claude_usd_in, cfg.claude_usd_out), cfg.poll_minutes)
    log(f"worker started · text model: {llm.name}"
        + (f" ({cfg.gemini_model})" if llm.name == "gemini" else "")
        + (f" ({cfg.claude_model})" if llm.name == "claude" else "")
        + f" · images: {images.name} · voice: {voice.name}"
        + f" · video {cfg.video_height}p"
        + (f" · first {cfg.max_scenes} scenes only" if cfg.max_scenes else "")
        + f" · votes last {cfg.poll_minutes or cfg.poll_hours * 60} min")

    last_poll_check = 0.0

    while True:
        # Close finished votes; each one queues the script of the next episode.
        if time.time() - last_poll_check >= cfg.poll_check_seconds:
            last_poll_check = time.time()
            try:
                for sid, nxt, label in pipe.close_due_polls():
                    log(f"vote closed · series {sid[:8]} · winner: {label} · "
                        + (f"queued episode {nxt}" if nxt else "season finished"))
            except Exception as e:
                log(f"could not close votes: {e}")

        try:
            job = db.claim_next_job()
        except Exception as e:  # network or Supabase down: wait and retry
            log(f"could not reach Supabase: {e}")
            time.sleep(cfg.idle_seconds * 3)
            continue

        if not job:
            if once:
                log("queue empty, exiting")
                return
            time.sleep(cfg.idle_seconds)
            continue

        label = f"{job['type']} · series {job['series_id'][:8]}"
        log(f"start  {label} (attempt {job.get('attempts')})")
        try:
            pipe.run(job)
            r = pipe.last
            db.finish_job(job["id"], r["provider"], r["cost"], r["episode_id"])
            log(f"done   {label} · ${r['cost']:.4f}")
        except Exception as e:
            attempts = int(job.get("attempts") or 1)
            busy = isinstance(e, TransientLLMError)
            # A busy provider gets many more tries than a real error.
            limit = cfg.max_attempts * 5 if busy else cfg.max_attempts
            retry = attempts < limit and not isinstance(e, NotImplementedError)
            db.fail_job(job["id"], f"{type(e).__name__}: {e}", retry)
            log(f"{'retry' if retry else 'FAILED'} {label}: {e}")
            if not busy and not isinstance(e, NotImplementedError):
                traceback.print_exc()
            # Back off longer when the provider is busy.
            time.sleep(60 if busy else cfg.idle_seconds)


if __name__ == "__main__":
    main()
