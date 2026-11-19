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
from .pipeline import Pipeline


def log(msg: str) -> None:
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def main() -> None:
    once = "--once" in sys.argv
    cfg = Config.from_env()
    db = Db(cfg)
    llm = make_llm(cfg)
    pipe = Pipeline(db, llm, cfg.poll_hours)
    log(f"worker started · text model: {llm.name}"
        + (f" ({cfg.gemini_model})" if llm.name == "gemini" else "")
        + (f" ({cfg.claude_model})" if llm.name == "claude" else ""))

    while True:
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
            db.finish_job(job["id"], llm.name)
            log(f"done   {label}")
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
