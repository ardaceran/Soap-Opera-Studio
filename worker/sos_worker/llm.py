"""Text model providers. Every provider returns parsed JSON for a prompt.

- FakeLLM: no key, no network, deterministic sample text (for development).
- GeminiLLM: Google Gemini API free tier (key from aistudio.google.com).

New providers (Groq, Claude, ...) only need a `generate_json` method.
"""

import json
import re
import time

from . import http
from .config import Config


class LLMError(Exception):
    pass


class TransientLLMError(LLMError):
    """The provider is busy or rate-limited; trying again later usually works."""


TRANSIENT_STATUS = (429, 500, 502, 503, 504)


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


class GeminiLLM:
    name = "gemini"
    URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

    def __init__(self, api_key: str, model: str, waits=(10, 30, 60)):
        self.api_key = api_key
        self.model = model
        self.waits = waits  # seconds to wait before each retry when busy

    def generate_json(self, system: str, prompt: str, kind: str) -> dict:
        body = {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "temperature": 0.9,
            },
        }
        res = None
        for attempt in range(len(self.waits) + 1):
            try:
                res = http.request(
                    "POST",
                    self.URL.format(model=self.model),
                    {"x-goog-api-key": self.api_key},
                    body,
                )
                break
            except http.HttpError as e:
                if e.status not in TRANSIENT_STATUS:
                    raise LLMError(f"Gemini request failed: {e}") from None
                if attempt == len(self.waits):
                    raise TransientLLMError(
                        f"Gemini busy (HTTP {e.status}) after {attempt + 1} tries") from None
                time.sleep(self.waits[attempt])
        try:
            text = res["candidates"][0]["content"]["parts"][0]["text"]
        except (KeyError, IndexError, TypeError):
            reason = (res or {}).get("promptFeedback") or (res or {}).get("candidates")
            raise LLMError(f"Gemini returned no text (blocked or empty): {reason}") from None
        return parse_json(text)


def parse_json(text: str) -> dict:
    """Parse model output, tolerating ```json fences."""
    t = text.strip()
    if t.startswith("```"):
        t = re.sub(r"^```[a-zA-Z]*\s*|\s*```$", "", t)
    try:
        return json.loads(t)
    except json.JSONDecodeError as e:
        raise LLMError(f"Model did not return valid JSON: {e}") from None


def make_llm(cfg: Config):
    if cfg.llm_provider == "fake":
        return FakeLLM()
    if cfg.llm_provider in ("gemini", "auto") and cfg.gemini_api_key:
        return GeminiLLM(cfg.gemini_api_key, cfg.gemini_model)
    if cfg.llm_provider == "gemini":
        raise SystemExit("LLM_PROVIDER=gemini but GEMINI_API_KEY is empty.")
    return FakeLLM()
