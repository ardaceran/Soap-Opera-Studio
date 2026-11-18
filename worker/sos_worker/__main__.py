"""Worker loop: claim a job, run it, mark it done or failed, repeat.

Run:  python -m sos_worker          (keeps running)
      python -m sos_worker --once   (handles queued jobs, then exits)
"""

import sys
import time
import traceback

from .config import Config
from .db import Db
from .llm import make_llm
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
        + (f" ({cfg.gemini_model})" if llm.name == "gemini" else ""))

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
            retry = int(job.get("attempts") or 1) < cfg.max_attempts \
                and not isinstance(e, NotImplementedError)
            db.fail_job(job["id"], f"{type(e).__name__}: {e}", retry)
            log(f"{'retry' if retry else 'FAILED'} {label}: {e}")
            if not isinstance(e, NotImplementedError):
                traceback.print_exc()
            time.sleep(cfg.idle_seconds)


if __name__ == "__main__":
    main()
