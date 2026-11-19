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
        self.storage = cfg.supabase_url + "/storage/v1"
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

    def finish_job(self, job_id: str, provider: str, cost_usd: float = 0.0,
                   episode_id: str = None):
        values = {"status": "done", "error": None, "provider": provider,
                  "cost_usd": round(cost_usd, 4), "updated_at": _now()}
        if episode_id:  # so the episode_costs view counts this job (e.g. the script)
            values["episode_id"] = episode_id
        self._update("jobs", f"id=eq.{job_id}", values)

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


    # ------------------------------------------------------------------ media
    def get_episode_for_render(self, episode_id: str) -> dict:
        rows = self._get(
            f"/episodes?id=eq.{episode_id}"
            "&select=id,series_id,number,title,"
            "scenes(id,idx,dialogue,visual_prompt),"
            "polls(poll_options!poll_options_poll_id_fkey(label)),"
            "series(id,owner_id,title,genre,setting,"
            "characters(id,name,role,description,voice_id,ref_image_paths))"
        )
        if not rows:
            raise LookupError(f"episode {episode_id} not found")
        ep = rows[0]
        polls = ep.get("polls")
        if isinstance(polls, list):
            polls = polls[0] if polls else None
        ep["poll_options"] = [o["label"] for o in (polls or {}).get("poll_options") or []]
        ep["scenes"] = sorted(ep.get("scenes") or [], key=lambda s: s["idx"])
        return ep

    def update_character(self, character_id: str, values: dict):
        self._update("characters", f"id=eq.{character_id}", values)

    def update_scene(self, scene_id: str, values: dict):
        self._update("scenes", f"id=eq.{scene_id}", values)

    def set_episode_video(self, episode_id: str, path: str):
        self._update("episodes", f"id=eq.{episode_id}", {"video_path": path})

    # ------------------------------------------------------------------ votes
    def due_polls(self, now_iso: str) -> list:
        """Polls whose time is up and that have no winner yet."""
        rows = self._get(
            f"/polls?closes_at=lte.{now_iso}&winner_option_id=is.null"
            "&select=id,episode_id,episodes(series_id,number),"
            "poll_options!poll_options_poll_id_fkey(id,label)"
        )
        return rows or []

    def vote_counts(self, poll_id: str) -> dict:
        """{option_id: number of votes}"""
        counts = {}
        for r in self._get(f"/votes?poll_id=eq.{poll_id}&select=option_id") or []:
            counts[r["option_id"]] = counts.get(r["option_id"], 0) + 1
        return counts

    def set_winner(self, poll_id: str, option_id: str) -> bool:
        """Writes the winner only if there is none yet. False: someone else closed it first."""
        h = dict(self.headers, Prefer="return=representation")
        rows = http.request(
            "PATCH", f"{self.base}/polls?id=eq.{poll_id}&winner_option_id=is.null",
            h, {"winner_option_id": option_id})
        return bool(rows)

    def set_poll_closes(self, episode_id: str, closes_iso: str):
        """Starts the vote clock again (when the episode video is ready)."""
        self._update("polls", f"episode_id=eq.{episode_id}&winner_option_id=is.null",
                     {"closes_at": closes_iso})

    def episode_exists(self, series_id: str, number: int) -> bool:
        rows = self._get(f"/episodes?series_id=eq.{series_id}&number=eq.{number}&select=id")
        return bool(rows)

    # ------------------------------------------------------------------ storage
    def upload(self, bucket: str, path: str, data: bytes, content_type: str) -> str:
        """Upload (or overwrite) a file in Supabase Storage; returns its path."""
        h = dict(self.headers, **{"x-upsert": "true"})
        http.raw("POST", f"{self.storage}/object/{bucket}/{path}", h, data,
                 content_type, timeout=300)
        return path

    def signed_url(self, bucket: str, path: str, seconds: int = 3600) -> str:
        """Temporary link to a private file (fal.ai reads the character portrait)."""
        res = http.request("POST", f"{self.storage}/object/sign/{bucket}/{path}",
                           self.headers, {"expiresIn": seconds})
        link = res.get("signedURL") or res.get("signedUrl")
        if not link:
            raise LookupError(f"no signed URL for {bucket}/{path}: {res}")
        return self.storage + link


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()
