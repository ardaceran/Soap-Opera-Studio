"""Image and voice providers for the episode video.

- FalImages: fal.ai. Character reference portraits with FLUX.1 [schnell]
  (cheap), scene stills with FLUX.1 Kontext [pro], which redraws the speaking
  character from their reference portrait so faces stay the same across
  scenes and episodes.
- ElevenVoice: ElevenLabs text-to-speech, one fixed voice per character.
- CloudflareImages / CloudflareVoice: Cloudflare Workers AI, free daily allowance
  (10,000 neurons/day). FLUX.2 [klein] 4B draws portraits and scenes; for scenes the
  speaker's portrait goes in as a reference image so the face stays the same.
  Deepgram Aura reads the lines, one of 12 voices per character.
- FakeImages / FakeVoice: no key, no network. Placeholder cards and quiet
  audio made with FFmpeg, so the whole pipeline can be tested for free.

Every call reports its cost in USD so episode cost (Demo Day c) is measured.
Unit prices are settings (see config.py); check them against the provider
dashboards after a real run.
"""

import base64
import json
import re
import subprocess
import uuid
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


class ContentFlagged(MediaError):
    """The provider's safety filter refused this prompt or its output."""


def _is_flagged(text: str) -> bool:
    t = (text or "").lower()
    return "flagged" in t or "nsfw" in t or "safety" in t


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
    ref_kind = "url"     # Kontext reads the portrait from a (signed) link
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
    female, male = DEFAULT_VOICES[0::2], DEFAULT_VOICES[1::2]
    narrator = NARRATOR_VOICE

    @staticmethod
    def valid_voice(v: str) -> bool:
        return bool(v) and len(v) >= 15  # ElevenLabs ids are ~20 characters

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
    ref_kind = None

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
    female, male = ["fake-f1", "fake-f2"], ["fake-m1", "fake-m2"]
    narrator = "fake-narrator"

    @staticmethod
    def valid_voice(v):
        return bool(v)

    def speak(self, text, voice_id):
        secs = max(1.5, len(text.split()) / 2.6)
        with tempfile.TemporaryDirectory() as d:
            _ffmpeg(["-f", "lavfi", "-i", f"sine=frequency=220:duration={secs:.2f}",
                     "-af", "volume=0.05", "-c:a", "libmp3lame", "-q:a", "6", "out.mp3"], d)
            return Path(d, "out.mp3").read_bytes(), 0.0


# ---------------------------------------------------------------- Cloudflare Workers AI
CF_URL = "https://api.cloudflare.com/client/v4/accounts/{account}/ai/run/{model}"


def _multipart(fields: dict, files: dict):
    """Encode a multipart/form-data body with the standard library."""
    boundary = "----sos" + uuid.uuid4().hex
    out = []
    for k, v in fields.items():
        out.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'
                   .encode("utf-8"))
    for k, (filename, data, ctype) in files.items():
        out.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"; '
                   f'filename="{filename}"\r\nContent-Type: {ctype}\r\n\r\n'.encode("utf-8"))
        out.append(data + b"\r\n")
    out.append(f"--{boundary}--\r\n".encode("utf-8"))
    return b"".join(out), f"multipart/form-data; boundary={boundary}"


def _cf_payload(raw: bytes, key: str) -> bytes:
    """Workers AI answers with the file itself, or JSON with it in base64."""
    head = raw[:1]
    if head not in (b"{", b"["):
        return raw
    try:
        res = json.loads(raw)
    except json.JSONDecodeError:
        return raw
    if isinstance(res, dict) and res.get("success") is False:
        if _is_flagged(json.dumps(res.get("errors"))):
            raise ContentFlagged(f"Cloudflare flagged it: {res.get('errors')}")
        raise MediaError(f"Cloudflare: {res.get('errors')}")
    body = res.get("result", res) if isinstance(res, dict) else {}
    b64 = body.get(key) if isinstance(body, dict) else None
    if not b64:
        raise MediaError(f"Cloudflare returned no {key}: {str(res)[:300]}")
    return base64.b64decode(b64)


def shrink_jpeg(img: bytes, box: int = 448) -> bytes:
    """Reference images for FLUX.2 [klein] must be smaller than 512x512."""
    with tempfile.TemporaryDirectory() as d:
        Path(d, "in.jpg").write_bytes(img)
        _ffmpeg(["-i", "in.jpg", "-vf",
                 f"scale={box}:{box}:force_original_aspect_ratio=decrease",
                 "-q:v", "3", "out.jpg"], d)
        return Path(d, "out.jpg").read_bytes()


class CloudflareImages:
    name = "cloudflare"
    ref_kind = "bytes"   # the portrait is uploaded with the request

    def __init__(self, account, token, model, usd_per_image, width=576, height=1024):
        self.url = CF_URL.format(account=account, model=model)
        self.headers = {"Authorization": "Bearer " + token}
        self.usd_per_image = usd_per_image
        self.width, self.height = width, height

    def _run(self, prompt: str, ref: bytes = None) -> bytes:
        files = {}
        if ref:
            files["input_image_0"] = ("ref.jpg", shrink_jpeg(ref), "image/jpeg")
        body, ctype = _multipart(
            {"prompt": prompt[:2000], "width": self.width, "height": self.height}, files)
        try:
            raw = http.raw("POST", self.url, self.headers, body, ctype, timeout=300)
        except http.HttpError as e:
            if _is_flagged(e.body):
                raise ContentFlagged(f"Cloudflare flagged the image: {e}") from None
            raise MediaError(f"Cloudflare image failed: {e}") from None
        return _cf_payload(raw, "image")

    def reference(self, character: dict, series: dict):
        return self._run(character_prompt(character, series)), self.usd_per_image

    def scene(self, visual: str, speaker: str, series: dict, ref=None):
        if ref:
            prompt = (f"The person in image 0 is {speaker}. Keep their face, hair and look "
                      f"exactly the same. {scene_prompt(visual, speaker, series, False)}")
            try:
                return self._run(prompt, ref), self.usd_per_image
            except ContentFlagged:
                pass  # the safety filter sometimes misfires on edits: try without the portrait
        try:
            return self._run(scene_prompt(visual, speaker, series, False)), self.usd_per_image
        except ContentFlagged:
            # Last try: only the place and the mood, no people.
            calm = f"Empty scene, no people. Setting: {series['setting']}. {STYLE}"
            return self._run(calm), self.usd_per_image


AURA_VOICES = {
    "female": ["asteria", "luna", "athena", "hera", "stella"],
    "male": ["orion", "arcas", "perseus", "angus", "helios", "orpheus"],
    "narrator": "zeus",
}


class CloudflareVoice:
    name = "cloudflare"
    female, male, narrator = AURA_VOICES["female"], AURA_VOICES["male"], AURA_VOICES["narrator"]

    def __init__(self, account, token, model, usd_per_char):
        self.url = CF_URL.format(account=account, model=model)
        self.headers = {"Authorization": "Bearer " + token}
        self.usd_per_char = usd_per_char

    @staticmethod
    def valid_voice(v: str) -> bool:
        return v in AURA_VOICES["female"] + AURA_VOICES["male"] + [AURA_VOICES["narrator"]]

    def speak(self, text: str, voice_id: str):
        body = json.dumps({"text": text, "speaker": voice_id, "encoding": "mp3"}).encode()
        try:
            raw = http.raw("POST", self.url, self.headers, body, "application/json", timeout=120)
        except http.HttpError as e:
            raise MediaError(f"Cloudflare voice failed: {e}") from None
        return _cf_payload(raw, "audio"), len(text) * self.usd_per_char


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
    """(images, voice) for MEDIA_PROVIDER.

    auto: for each of images and voice, the first provider whose key is set:
          fal.ai / ElevenLabs (paid) -> Cloudflare Workers AI (free daily allowance) -> fake.
    cloudflare / fake: that provider for both.
    """
    mode = cfg.media_provider
    cf = bool(cfg.cloudflare_account_id and cfg.cloudflare_api_token)
    cf_images = lambda: CloudflareImages(cfg.cloudflare_account_id, cfg.cloudflare_api_token,
                                         cfg.cloudflare_image_model, cfg.cloudflare_usd_per_image)
    cf_voice = lambda: CloudflareVoice(cfg.cloudflare_account_id, cfg.cloudflare_api_token,
                                       cfg.cloudflare_voice_model, cfg.cloudflare_usd_per_char)
    if mode == "fake":
        return FakeImages(), FakeVoice()
    if mode == "cloudflare":
        if not cf:
            raise SystemExit("MEDIA_PROVIDER=cloudflare needs CLOUDFLARE_ACCOUNT_ID and "
                             "CLOUDFLARE_API_TOKEN.")
        return cf_images(), cf_voice()
    images = (FalImages(cfg.fal_key, cfg.fal_ref_model, cfg.fal_scene_model,
                        cfg.fal_usd_per_ref, cfg.fal_usd_per_scene)
              if cfg.fal_key else cf_images() if cf else None)
    voice = (ElevenVoice(cfg.elevenlabs_key, cfg.elevenlabs_model, cfg.elevenlabs_usd_per_char)
             if cfg.elevenlabs_key else cf_voice() if cf else None)
    if mode == "real" and not (images and voice):
        raise SystemExit("MEDIA_PROVIDER=real needs image and voice keys "
                         "(fal.ai + ElevenLabs, or Cloudflare).")
    return images or FakeImages(), voice or FakeVoice()


FEMALE = {"she", "her", "woman", "girl", "mother", "mom", "wife", "daughter", "sister",
          "aunt", "grandmother", "queen", "lady", "bride", "actress", "heiress", "niece"}
MALE = {"he", "his", "man", "boy", "father", "dad", "husband", "son", "brother", "uncle",
        "grandfather", "king", "groom", "actor", "nephew", "gentleman"}


def guess_gender(character: dict):
    words = set(re.findall(r"[a-z]+", f"{character.get('role') or ''} "
                                       f"{character.get('description') or ''}".lower()))
    if words & FEMALE and not words & MALE:
        return "female"
    if words & MALE and not words & FEMALE:
        return "male"
    return None


def pick_voice(character: dict, used: set, voice=None, index: int = 0) -> str:
    """Keep a character's voice if the provider knows it; otherwise the next free voice
    of the guessed gender (unknown: alternate female/male)."""
    voice = voice or ElevenVoice
    if character.get("voice_id") and voice.valid_voice(character["voice_id"]):
        return character["voice_id"]
    gender = guess_gender(character) or ("female" if index % 2 == 0 else "male")
    pool = voice.female if gender == "female" else voice.male
    for v in pool:
        if v not in used:
            return v
    return pool[len(used) % len(pool)]
