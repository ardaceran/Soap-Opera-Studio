"""Text model providers. Every provider returns parsed JSON for a prompt.

- FakeLLM: no key, no network, deterministic sample text (for development).
- ClaudeLLM: Anthropic Messages API (key from console.anthropic.com). The course
  brief asks for season plans and scripts by Claude, so this is the default when
  ANTHROPIC_API_KEY is set.
- GeminiLLM: Google Gemini API free tier (key from aistudio.google.com), a free
  fallback during development.

New providers only need a `generate_json` method.
"""

import json
import re
import time
import urllib.error

from . import http
from .config import Config


class LLMError(Exception):
    pass


class TransientLLMError(LLMError):
    """The provider is busy or rate-limited; trying again later usually works."""


TRANSIENT_STATUS = (429, 500, 502, 503, 504)

# Text models can take minutes for a long JSON answer; wait longer than for media.
LLM_TIMEOUT = 300

# A slow or dropped connection is treated like a busy provider: wait and try again.
NETWORK_ERRORS = (TimeoutError, urllib.error.URLError, ConnectionError)


class FakeLLM:
    name = "fake"

    def generate_json(self, system: str, prompt: str, kind: str) -> dict:
        names = re.findall(r"^- ([^:(]+?) \(", prompt, flags=re.M) or ["Ada", "Ben"]
        a = names[0]
        b = names[1] if len(names) > 1 else names[0]
        if kind == "season_plan":
            return {
                "logline": f"{a} and {b} are pulled into a family secret.",
                "episodes": [
                    {"number": i, "title": f"Chapter {i}",
                     "outline": f"Sample outline for episode {i}."}
                    for i in range(1, 6)
                ],
            }
        m = re.search(r"Write episode (\d+)", prompt)
        n = int(m.group(1)) if m else 1
        winner = re.search(r"Viewers voted: (.+)", prompt)
        opening = (f"Viewers chose: {winner.group(1).strip()}."
                   if winner else "A quiet evening hides a storm.")
        lines = [
            ("Narrator", opening),
            (a, "I did not expect to see you here."),
            (b, "Some doors were meant to stay closed."),
            (a, "Then why do you have the key?"),
            (b, "Because someone wanted you to find it."),
            ("Narrator", "Footsteps echo in the hallway."),
            (a, "Tell me the truth. All of it."),
            (b, "Not tonight. Not here."),
            ("Narrator", "A phone rings. Nobody answers."),
            (a, "Whatever happens next, I choose it."),
            ("Narrator", "What should happen next?"),
        ]
        return {
            "title": f"Sample Episode {n}",
            "summary": f"(Sample text, no AI) {a} and {b} face a secret.",
            "scenes": [
                {"speaker": s, "line": t, "visual": f"{s} in a dim room, scene {i + 1}"}
                for i, (s, t) in enumerate(lines)
            ],
            "poll_options": [f"{a} confronts {b}", f"{a} runs away", f"{b} tells the truth"],
        }


class ClaudeLLM:
    name = "claude"
    URL = "https://api.anthropic.com/v1/messages"
    VERSION = "2023-06-01"

    def __init__(self, api_key: str, model: str, max_tokens: int = 8000, waits=(10, 30, 60)):
        self.api_key = api_key
        self.model = model
        self.max_tokens = max_tokens
        self.waits = waits  # seconds to wait before each retry when busy
        self.last_usage = None  # {"input_tokens": .., "output_tokens": ..} for cost logging

    def generate_json(self, system: str, prompt: str, kind: str) -> dict:
        body = {
            "model": self.model,
            "max_tokens": self.max_tokens,
            "temperature": 0.9,
            "system": system + "\n\nRespond with a single JSON object only, no prose, no code fences.",
            "messages": [{"role": "user", "content": prompt}],
        }
        headers = {"x-api-key": self.api_key, "anthropic-version": self.VERSION}
        res = None
        for attempt in range(len(self.waits) + 1):
            try:
                res = http.request("POST", self.URL, headers, body, timeout=LLM_TIMEOUT)
                break
            except NETWORK_ERRORS as e:
                if attempt == len(self.waits):
                    raise TransientLLMError(
                        f"Claude did not answer ({e}) after {attempt + 1} tries") from None
                time.sleep(self.waits[attempt])
            except http.HttpError as e:
                # 529 = Anthropic overloaded
                if e.status not in TRANSIENT_STATUS + (529,):
                    raise LLMError(f"Claude request failed: {e}") from None
                if attempt == len(self.waits):
                    raise TransientLLMError(
                        f"Claude busy (HTTP {e.status}) after {attempt + 1} tries") from None
                time.sleep(self.waits[attempt])
        self.last_usage = (res or {}).get("usage")
        if (res or {}).get("stop_reason") == "max_tokens":
            raise LLMError("Claude output was cut off (max_tokens); raise CLAUDE_MAX_TOKENS.")
        try:
            text = "".join(b["text"] for b in res["content"] if b.get("type") == "text")
        except (KeyError, TypeError):
            raise LLMError(f"Claude returned no text: {res}") from None
        if not text.strip():
            raise LLMError(f"Claude returned empty text (stop_reason={res.get('stop_reason')})")
        return parse_json(text)


class GeminiLLM:
    """Gemini with backup models: the free tier gives each model its own daily quota
    (e.g. only 20 requests/day for gemini-3.8-flash), so when one model says 429
    (quota used up) or 404 (not available) the next model in the list answers."""
    name = "gemini"
    URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    COOLDOWN = 15 * 60  # seconds a model that hit its quota is skipped

    def __init__(self, api_key: str, model: str, waits=(10, 30, 60), thinking: str = "low",
                 fallbacks=()):
        self.api_key = api_key
        self.model = model
        fallbacks = fallbacks if isinstance(fallbacks, (list, tuple)) else ()
        self.models = [model] + [m for m in fallbacks if m and m != model]
        self.waits = waits  # seconds to wait before each retry when busy
        # Less thinking = a much faster answer; long thinking is what timed out.
        self.thinking = thinking
        self.no_thinking = set()  # models that refused the thinking setting
        self.resting = {}         # model -> time until which it is skipped
        self.last_model = None

    def generate_json(self, system: str, prompt: str, kind: str) -> dict:
        now = time.time()
        ready = [m for m in self.models if self.resting.get(m, 0) <= now]
        last_error, statuses = None, []
        for model in ready:
            try:
                res = self._ask(model, system, prompt)
            except _QuotaUsedUp as e:
                last_error = e
                statuses.append(e.status)
                self.resting[model] = time.time() + (
                    10 ** 9 if e.status == 404 else self.COOLDOWN)
                continue
            self.last_model = model
            try:
                text = res["candidates"][0]["content"]["parts"][0]["text"]
            except (KeyError, IndexError, TypeError):
                reason = (res or {}).get("promptFeedback") or (res or {}).get("candidates")
                raise LLMError(f"Gemini returned no text (blocked or empty): {reason}") from None
            return parse_json(text)
        tried = ", ".join(ready) or "none (all resting)"
        if statuses and all(st == 404 for st in statuses):
            raise LLMError(f"Gemini model not found ({tried}); check GEMINI_MODEL.")
        raise TransientLLMError(
            f"Gemini quota used up for every model ({tried}); "
            f"free daily limits reset at midnight Pacific time. Last error: {last_error}")

    def _ask(self, model: str, system: str, prompt: str) -> dict:
        body = {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "temperature": 0.9,
            },
        }
        if self.thinking and model not in self.no_thinking:
            body["generationConfig"]["thinkingConfig"] = {"thinkingLevel": self.thinking}
        attempt = 0
        while True:
            try:
                return http.request("POST", self.URL.format(model=model),
                                    {"x-goog-api-key": self.api_key}, body,
                                    timeout=LLM_TIMEOUT)
            except NETWORK_ERRORS as e:
                if attempt >= len(self.waits):
                    raise TransientLLMError(
                        f"Gemini did not answer ({e}) after {attempt + 1} tries") from None
            except http.HttpError as e:
                if e.status == 400 and "thinkingConfig" in body["generationConfig"]:
                    # This model does not take the thinking setting: send without it.
                    del body["generationConfig"]["thinkingConfig"]
                    self.no_thinking.add(model)
                    continue
                if e.status in (404, 429):
                    raise _QuotaUsedUp(e.status, f"{model}: HTTP {e.status}") from None
                if e.status not in TRANSIENT_STATUS:
                    raise LLMError(f"Gemini request failed: {e}") from None
                if attempt >= len(self.waits):
                    raise TransientLLMError(
                        f"Gemini busy (HTTP {e.status}) after {attempt + 1} tries") from None
            time.sleep(self.waits[attempt])
            attempt += 1


class _QuotaUsedUp(Exception):
    def __init__(self, status: int, msg: str):
        super().__init__(msg)
        self.status = status


def parse_json(text: str) -> dict:
    """Parse model output, tolerating ```json fences."""
    t = text.strip()
    if t.startswith("```"):
        t = re.sub(r"^```[a-zA-Z]*\s*|\s*```$", "", t)
    try:
        return json.loads(t)
    except json.JSONDecodeError as e:
        # Tolerate a sentence before or after the object.
        start, end = t.find("{"), t.rfind("}")
        if 0 <= start < end:
            try:
                return json.loads(t[start:end + 1])
            except json.JSONDecodeError:
                pass
        raise LLMError(f"Model did not return valid JSON: {e}") from None


def make_llm(cfg: Config):
    """auto: Claude if ANTHROPIC_API_KEY is set, else Gemini if GEMINI_API_KEY is set, else fake."""
    p = cfg.llm_provider
    if p == "fake":
        return FakeLLM()
    if p in ("claude", "auto") and cfg.anthropic_api_key:
        return ClaudeLLM(cfg.anthropic_api_key, cfg.claude_model, cfg.claude_max_tokens)
    if p == "claude":
        raise SystemExit("LLM_PROVIDER=claude but ANTHROPIC_API_KEY is empty.")
    if p in ("gemini", "auto") and cfg.gemini_api_key:
        return GeminiLLM(cfg.gemini_api_key, cfg.gemini_model, thinking=cfg.gemini_thinking,
                         fallbacks=cfg.gemini_fallbacks)
    if p == "gemini":
        raise SystemExit("LLM_PROVIDER=gemini but GEMINI_API_KEY is empty.")
    return FakeLLM()
