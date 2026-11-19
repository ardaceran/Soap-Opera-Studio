"""Image and voice providers for the episode video.

- FalImages: fal.ai. Character reference portraits with FLUX.1 [schnell]
  (cheap), scene stills with FLUX.1 Kontext [pro], which redraws the speaking
  character from their reference portrait so faces stay the same across
  scenes and episodes.
- ElevenVoice: ElevenLabs text-to-speech, one fixed voice per character.
- FakeImages / FakeVoice: no key, no network. Placeholder cards and quiet
  audio made with FFmpeg, so the whole pipeline can be tested for free.

Every call reports its cost in USD so episode cost (Demo Day c) is measured.
Unit prices are settings (see config.py); check them against the provider
dashboards after a real run.
"""

import json
import subprocess
import tempfile
from pathlib import Path

from . import http

STYLE = ("cinematic still from a Turkish TV drama, dramatic soft lighting, "
         "shallow depth of field, photorealistic, vertical 9:16 frame, "
         "no text, no captions, no watermark")

# ElevenLabs premade voices, handed out in order to characters without a voice_id.
DEFAULT_VOICES = [
    "21m00Tcm4TlvDq8ikWAM",  # Rachel
    "pNInz6obpgDQGcFmaJgB",  # Adam
    "EXAVITQu4vr4xnSDxMaL",  # Bella
    "ErXwobaYiN019PkySvjV",  # Antoni
    "AZnzlk1XvdvUeBnXmlld",  # Domi
    "TxGEqnHWrfWFTfGW9XjX",  # Josh
]
NARRATOR_VOICE = "onwK4e9ZLuTAKqWW03F9"  # Daniel


class MediaError(Exception):
    pass


def character_prompt(c: dict, series: dict) -> str:
    desc = c.get("description") or ""
    return (f"Head-and-shoulders portrait of {c['name']}, {c.get('role') or 'a character'} "
            f"in a {series['genre']} series set in {series['setting']}. {desc}. "
            f"Looking at the camera, neutral expression, plain background. {STYLE}")


def scene_prompt(visual: str, speaker: str, series: dict, has_ref: bool) -> str:
    who = (f"Keep this person's face, hair and look exactly the same. Show {speaker} in this scene: "
           if has_ref else "")
    return f"{who}{visual}. Setting: {series['setting']}. {STYLE}"


# ---------------------------------------------------------------- fal.ai
class FalImages:
    name = "fal"
    BASE = "https://fal.run/"

    def __init__(self, key, ref_model, scene_model, usd_per_ref, usd_per_scene):
        self.headers = {"Authorization": "Key " + key}
        self.ref_model = ref_model
        self.scene_model = scene_model
        self.usd_per_ref = usd_per_ref
        self.usd_per_scene = usd_per_scene

    def _run(self, model: str, body: dict) -> bytes:
        try:
            res = http.request("POST", self.BASE + model, self.headers, body, timeout=300)
        except http.HttpError as e:
            raise MediaError(f"fal.ai {model} failed: {e}") from None
        try:
            if any(res.get("has_nsfw_concepts") or []):
                raise MediaError(f"fal.ai {model}: image blocked by the safety checker")
            return http.download(res["images"][0]["url"])
        except (KeyError, IndexError, TypeError):
            raise MediaError(f"fal.ai {model} returned no image: {res}") from None

    def reference(self, character: dict, series: dict):
        """Portrait of a character -> (jpeg bytes, cost)."""
        img = self._run(self.ref_model, {
            "prompt": character_prompt(character, series),
            "image_size": "portrait_16_9",
            "output_format": "jpeg",
            "enable_safety_checker": True,
        })
        return img, self.usd_per_ref

    def scene(self, visual: str, speaker: str, series: dict, ref_url=None):
        """Scene still -> (jpeg bytes, cost). With ref_url the speaker keeps their face."""
        if ref_url:
            img = self._run(self.scene_model, {
                "prompt": scene_prompt(visual, speaker, series, True),
                "image_url": ref_url,
                "aspect_ratio": "9:16",
                "output_format": "jpeg",
            })
            return img, self.usd_per_scene
        # Narrator / establishing shots: no face to keep, so the cheap model is enough.
        img = self._run(self.ref_model, {
            "prompt": scene_prompt(visual, speaker, series, False),
            "image_size": "portrait_16_9",
            "output_format": "jpeg",
            "enable_safety_checker": True,
        })
        return img, self.usd_per_ref


# ---------------------------------------------------------------- ElevenLabs
class ElevenVoice:
    name = "elevenlabs"
    URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_44100_128"

    def __init__(self, key, model, usd_per_char):
        self.headers = {"xi-api-key": key, "Accept": "audio/mpeg"}
        self.model = model
        self.usd_per_char = usd_per_char

    def speak(self, text: str, voice_id: str):
        """Line of dialogue -> (mp3 bytes, cost)."""
        body = json.dumps({"text": text, "model_id": self.model}).encode("utf-8")
        try:
            mp3 = http.raw("POST", self.URL.format(voice=voice_id), self.headers,
                           body, "application/json", timeout=120)
        except http.HttpError as e:
            raise MediaError(f"ElevenLabs failed: {e}") from None
        return mp3, len(text) * self.usd_per_char


# ---------------------------------------------------------------- offline fakes
def _ffmpeg(args, cwd):
    p = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args],
                       cwd=cwd, capture_output=True, text=True)
    if p.returncode != 0:
        raise MediaError("ffmpeg: " + p.stderr.strip()[-800:])


COLORS = ["0x7a2e3b", "0x2e4a7a", "0x3b6b4a", "0x6b4a2e", "0x4a2e6b", "0x2e6b6b"]


class FakeImages:
    """Solid color card with the scene words on it. Free, offline."""
    name = "fake"

    def _card(self, text: str, color: str) -> bytes:
        with tempfile.TemporaryDirectory() as d:
            Path(d, "t.txt").write_text(_wrap(text, 28))
            _ffmpeg(["-f", "lavfi", "-i", f"color=c={color}:s=576x1024",
                     "-vf", "drawtext=textfile=t.txt:fontcolor=white:fontsize=34:"
                            "line_spacing=10:x=(w-text_w)/2:y=(h-text_h)/2",
                     "-frames:v", "1", "out.jpg"], d)
            return Path(d, "out.jpg").read_bytes()

    def reference(self, character, series):
        return self._card(f"{character['name']}\n({character.get('role') or ''})",
                          COLORS[hash(character["name"]) % len(COLORS)]), 0.0

    def scene(self, visual, speaker, series, ref_url=None):
        return self._card(f"[{speaker}]\n{visual}",
                          COLORS[hash(speaker) % len(COLORS)]), 0.0


class FakeVoice:
    """Quiet tone as long as the line would take to say (~2.6 words/s). Free."""
    name = "fake"

    def speak(self, text, voice_id):
        secs = max(1.5, len(text.split()) / 2.6)
        with tempfile.TemporaryDirectory() as d:
            _ffmpeg(["-f", "lavfi", "-i", f"sine=frequency=220:duration={secs:.2f}",
                     "-af", "volume=0.05", "-c:a", "libmp3lame", "-q:a", "6", "out.mp3"], d)
            return Path(d, "out.mp3").read_bytes(), 0.0


def _wrap(text: str, width: int) -> str:
    words, lines, cur = text.replace("\n", " \n ").split(" "), [], ""
    for w in words:
        if w == "\n":
            lines.append(cur); cur = ""
        elif len(cur) + len(w) + 1 > width and cur:
            lines.append(cur); cur = w
        else:
            cur = (cur + " " + w).strip()
    lines.append(cur)
    return "\n".join(l for l in lines if l is not None)[:600]


def make_media(cfg):
    """(images, voice). auto = real provider when its key is set, else the free fake."""
    mode = cfg.media_provider
    if mode == "fake":
        return FakeImages(), FakeVoice()
    images = (FalImages(cfg.fal_key, cfg.fal_ref_model, cfg.fal_scene_model,
                        cfg.fal_usd_per_ref, cfg.fal_usd_per_scene)
              if cfg.fal_key else None)
    voice = (ElevenVoice(cfg.elevenlabs_key, cfg.elevenlabs_model, cfg.elevenlabs_usd_per_char)
             if cfg.elevenlabs_key else None)
    if mode == "real" and not (images and voice):
        raise SystemExit("MEDIA_PROVIDER=real needs FAL_KEY and ELEVENLABS_API_KEY.")
    return images or FakeImages(), voice or FakeVoice()


def pick_voice(character: dict, used: set) -> str:
    """Keep a character's voice; otherwise give them the next free default voice."""
    if character.get("voice_id"):
        return character["voice_id"]
    for v in DEFAULT_VOICES:
        if v not in used:
            return v
    return DEFAULT_VOICES[len(used) % len(DEFAULT_VOICES)]
