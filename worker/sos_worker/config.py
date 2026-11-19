"""Settings read from environment variables (the .env file in the repo root).

Secrets never live in code: SUPABASE_SECRET_KEY and the AI provider keys (ANTHROPIC, GEMINI, FAL,
ELEVENLABS) come only
from the environment.
"""

import os
from dataclasses import dataclass


def _int(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    return int(raw) if raw else default


def _float(name: str, default: float) -> float:
    raw = os.environ.get(name, "").strip()
    return float(raw) if raw else default


def _str(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip() or default


@dataclass(frozen=True)
class Config:
    supabase_url: str
    supabase_key: str
    llm_provider: str  # "auto", "claude", "gemini" or "fake"
    gemini_api_key: str
    gemini_model: str
    poll_hours: int
    idle_seconds: int
    max_attempts: int
    anthropic_api_key: str = ""
    claude_model: str = "claude-sonnet-5-5"
    claude_max_tokens: int = 8000
    # USD per million tokens, for the cost report. Check the Anthropic pricing page.
    claude_usd_in: float = 3.0
    claude_usd_out: float = 15.0
    # Images and voice: "auto" (real provider when its key is set), "real" or "fake".
    media_provider: str = "auto"
    fal_key: str = ""
    fal_ref_model: str = "fal-ai/flux/schnell"        # portraits, narrator shots
    fal_scene_model: str = "fal-ai/flux-pro/kontext"  # scenes that keep a face
    fal_usd_per_ref: float = 0.003     # schnell: $0.003 per megapixel (fal.ai)
    fal_usd_per_scene: float = 0.04    # Kontext [pro]: $0.04 per image (fal.ai)
    elevenlabs_key: str = ""
    elevenlabs_model: str = "eleven_multilingual_v2"
    elevenlabs_usd_per_char: float = 0.0003  # estimate; depends on your plan
    video_height: int = 1920           # 960 for cheap test runs
    max_scenes: int = 0                # 0 = all; e.g. 3 for short test runs
    # Vote length in minutes; overrides POLL_HOURS when set (e.g. 3 for a live demo).
    poll_minutes: int = 0
    poll_check_seconds: int = 30       # how often the worker looks for finished votes

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
            anthropic_api_key=os.environ.get("ANTHROPIC_API_KEY", "").strip(),
            claude_model=os.environ.get("CLAUDE_MODEL", "claude-sonnet-5-5").strip(),
            claude_max_tokens=_int("CLAUDE_MAX_TOKENS", 8000),
            claude_usd_in=_float("CLAUDE_USD_PER_MTOK_IN", 3.0),
            claude_usd_out=_float("CLAUDE_USD_PER_MTOK_OUT", 15.0),
            media_provider=_str("MEDIA_PROVIDER", "auto").lower(),
            fal_key=_str("FAL_KEY"),
            fal_ref_model=_str("FAL_REF_MODEL", "fal-ai/flux/schnell"),
            fal_scene_model=_str("FAL_SCENE_MODEL", "fal-ai/flux-pro/kontext"),
            fal_usd_per_ref=_float("FAL_USD_PER_REF", 0.003),
            fal_usd_per_scene=_float("FAL_USD_PER_SCENE", 0.04),
            elevenlabs_key=_str("ELEVENLABS_API_KEY"),
            elevenlabs_model=_str("ELEVENLABS_MODEL", "eleven_multilingual_v2"),
            elevenlabs_usd_per_char=_float("ELEVENLABS_USD_PER_CHAR", 0.0003),
            video_height=_int("VIDEO_HEIGHT", 1920),
            max_scenes=_int("MEDIA_MAX_SCENES", 0),
            poll_minutes=_int("POLL_MINUTES", 0),
            poll_check_seconds=_int("POLL_CHECK_SECONDS", 30),
        )
