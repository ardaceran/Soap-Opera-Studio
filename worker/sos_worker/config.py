"""Settings read from environment variables (the .env file in the repo root).

Secrets never live in code: SUPABASE_SECRET_KEY and GEMINI_API_KEY come only
from the environment.
"""

import os
from dataclasses import dataclass


def _int(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    return int(raw) if raw else default


@dataclass(frozen=True)
class Config:
    supabase_url: str
    supabase_key: str
    llm_provider: str  # "auto", "gemini" or "fake"
    gemini_api_key: str
    gemini_model: str
    poll_hours: int
    idle_seconds: int
    max_attempts: int

    @staticmethod
    def from_env() -> "Config":
        url = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
        key = (
            os.environ.get("SUPABASE_SECRET_KEY", "")
            or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
        ).strip()
        if not url or not key:
            raise SystemExit(
                "SUPABASE_URL and SUPABASE_SECRET_KEY must be set (see .env.example)."
            )
        return Config(
            supabase_url=url,
            supabase_key=key,
            llm_provider=os.environ.get("LLM_PROVIDER", "auto").strip().lower(),
            gemini_api_key=os.environ.get("GEMINI_API_KEY", "").strip(),
            gemini_model=os.environ.get("GEMINI_MODEL", "gemini-3.8-flash").strip(),
            poll_hours=_int("POLL_HOURS", 24),
            idle_seconds=_int("WORKER_IDLE_SECONDS", 5),
            max_attempts=_int("WORKER_MAX_ATTEMPTS", 3),
        )
