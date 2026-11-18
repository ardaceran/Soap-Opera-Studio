"""Supabase access for the worker, through the REST API with the secret key.

The secret (service role) key bypasses Row Level Security, so this code only
runs on our own machine/server, never in the app.
"""

from datetime import datetime, timezone

from . import http
from .config import Config


class Db:
    def __init__(self, cfg: Config):
        self.base = cfg.supabase_url + "/rest/v1"
        self.headers = {"apikey": cfg.supabase_key}
        # Legacy service_role keys are JWTs and also go in Authorization.
        # New sb_secret_ keys are sent only as apikey.
        if cfg.supabase_key.startswith("eyJ"):
            self.headers["Authorization"] = "Bearer " + cfg.supabase_key

    # ------------------------------------------------------------------ low level
    def _get(self, path: str):
        return http.request("GET", self.base + path, self.headers)

    def _rpc(self, fn: str, params: dict):
        return http.request("POST", f"{self.base}/rpc/{fn}", self.headers, params)

    def _insert(self, table: str, row: dict):
        h = dict(self.headers, Prefer="return=representation")
        rows = http.request("POST", f"{self.base}/{table}", h, row)
        return rows[0] if rows else None

    def _update(self, table: str, match: str, values: dict):
        h = dict(self.headers, Prefer="return=minimal")
        http.request("PATCH", f"{self.base}/{table}?{match}", h, values)

    # ------------------------------------------------------------------ jobs
    def claim_next_job(self):
        """Oldest queued job, marked running; None when the queue is empty."""
        job = self._rpc("claim_next_job", {})
        if isinstance(job, list):
            job = job[0] if job else None
        if not job or not job.get("id"):
            return None
        return job

    def finish_job(self, job_id: str, provider: str, cost_usd: float = 0.0):
        self._update(
            "jobs",
            f"id=eq.{job_id}",
            {"status": "done", "error": None, "provider": provider,
             "cost_usd": cost_usd, "updated_at": _now()},
        )

    def fail_job(self, job_id: str, error: str, retry: bool):
        self._update(
            "jobs",
            f"id=eq.{job_id}",
            {"status": "queued" if retry else "failed",
             "error": error[:1000], "updated_at": _now()},
        )

    def enqueue(self, series_id: str, job_type: str, payload: dict, episode_id=None):
        return self._insert(
            "jobs",
            {"series_id": series_id, "episode_id": episode_id,
             "type": job_type, "payload": payload},
        )

    # ------------------------------------------------------------------ story
    def get_series(self, series_id: str) -> dict:
        rows = self._get(
            f"/series?id=eq.{series_id}"
            "&select=id,title,genre,setting,season_plan,characters(name,role,description)"
        )
        if not rows:
            raise LookupError(f"series {series_id} not found")
        return rows[0]

    def save_season_plan(self, series_id: str, plan: dict):
        self._update("series", f"id=eq.{series_id}", {"season_plan": plan})

    def episode_summaries(self, series_id: str) -> list:
        rows = self._get(
            f"/episodes?series_id=eq.{series_id}&status=eq.published"
            "&select=number,title,summary&order=number"
        )
        return rows or []

    def poll_winner(self, series_id: str, episode_number: int):
        """Label of the winning option of an episode's poll, or None."""
        rows = self._get(
            f"/episodes?series_id=eq.{series_id}&number=eq.{episode_number}"
            "&select=polls(winner_option_id,"
            "poll_options!poll_options_poll_id_fkey(id,label))"
        )
        if not rows:
            return None
        polls = rows[0].get("polls")
        if isinstance(polls, list):
            polls = polls[0] if polls else None
        if not polls or not polls.get("winner_option_id"):
            return None
        for o in polls.get("poll_options") or []:
            if o["id"] == polls["winner_option_id"]:
                return o["label"]
        return None

    def publish_episode(self, series_id, number, title, summary, scenes,
                        poll_options, poll_hours) -> str:
        return self._rpc(
            "worker_publish_episode",
            {"p_series_id": series_id, "p_number": number, "p_title": title,
             "p_summary": summary, "p_scenes": scenes,
             "p_poll_options": poll_options, "p_poll_hours": poll_hours},
        )



def _now() -> str:
    return datetime.now(timezone.utc).isoformat()
