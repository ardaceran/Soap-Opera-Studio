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

STYLE = ("cinematic still from a prestige TV drama, dramatic soft lighting, "
         "shallow depth of field, photorealistic, vertical 9:16 frame, "
         "no text, no captions, no watermark")

# Framing words for each shot type (story.SHOTS). Subjects sit off-centre on a third,
# and the bottom of the frame stays calm for the captions.
FRAMING = {
    "establishing": "establishing shot of the location, no people, deep perspective",
    "wide": "wide shot, people small in the frame and placed on the left or right third, "
            "the place dominates",
    "medium": "medium shot from the waist up, subject on the left or right third, "
              "not centred, background visible",
    "close-up": "close-up of the face, off-centre on a third, strong emotion, "
                "soft background blur",
    "over-the-shoulder": "over-the-shoulder shot, one person's shoulder blurred in the "
                         "foreground, the other person facing camera on a third",
    "detail": "extreme close-up of an object or of hands, no faces",
    "silhouette": "silhouette against bright light, face not visible, strong shapes",
}
CAPTION_SPACE = "keep the bottom third of the frame calm and darker"


SET_TAG = re.compile(r"\s*\[set:\s*([^\]]+)\]\s*$", re.I)


def split_set(visual: str):
    """'Wide: rain on the house [set: Courtyard]' -> ('Wide: rain on the house', 'Courtyard')."""
    m = SET_TAG.search(visual or "")
    if not m:
        return (visual or "").strip(), None
    return (visual[:m.start()]).strip(), m.group(1).strip()


def set_description(name, series: dict):
    plan = series.get("season_plan") or {}
    sets = plan.get("sets") if isinstance(plan, dict) else None
    if not name or not isinstance(sets, dict):
        return None
    for k, v in sets.items():
        if k.lower() == name.lower():
            return v
    return None


def set_prompt(name: str, description: str, series: dict) -> str:
    """Reference picture of a recurring place: no people, the whole room or view."""
    plan = series.get("season_plan") or {}
    look = plan.get("visual_style") if isinstance(plan, dict) else ""
    return (f"Wide establishing view of {name}: {description}. Part of {series['setting']}. "
            f"No people. The whole space is visible, clear layout."
            + (f" Look of the series: {look}." if look else "") + f" {STYLE}")


def split_shot(visual: str):
    """'Close-up: Elif crying' -> ('close-up', 'Elif crying'); no prefix -> (None, text)."""
    head, sep, rest = (visual or "").partition(":")
    key = head.strip().lower()
    if sep and key in FRAMING:
        return key, rest.strip()
    return None, (visual or "").strip()


def people_in(text: str, speaker: str, series: dict) -> list:
    """Characters named in the scene description (the speaker counts when they are not
    the narrator and the shot shows people)."""
    low = (text or "").lower()
    out = [c for c in series.get("characters") or [] if c["name"].lower() in low]
    if not out and speaker and speaker != "Narrator":
        out = [c for c in series.get("characters") or [] if c["name"] == speaker]
    return out


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


def use_portrait(visual: str, speaker: str, series: dict) -> bool:
    """The portrait helps keep a face, but an edit model copies it into the frame:
    use it only when the speaker is the one person in a medium or close shot."""
    shot, text = split_shot(split_set(visual)[0])
    shown = people_in(text, speaker, series)
    return (shot in (None, "medium", "close-up") and len(shown) == 1
            and shown[0]["name"] == speaker)


def scene_prompt(visual: str, speaker: str, series: dict, has_ref: bool) -> str:
    visual, set_name = split_set(visual)
    place = set_description(set_name, series)
    shot, text = split_shot(visual)
    no_people = shot in ("establishing", "detail")
    people = [] if no_people else people_in(text, speaker, series)
    if people:
        def one(c):
            return f"{c['name']} ({c['description']})" if c.get("description") else c["name"]
        n = len(people)
        who = (f"Exactly {n} {'person' if n == 1 else 'people'} in the frame: "
               + "; ".join(one(c) for c in people) + ". Nobody else, no duplicates.")
    else:
        who = "No people in the frame, only the place, the weather and objects."
    keep = ("Keep this person's face, hair and look exactly the same. " if has_ref else "")
    framing = FRAMING.get(shot) or "subject on the left or right third, not centred"
    plan = series.get("season_plan") or {}
    look = plan.get("visual_style") if isinstance(plan, dict) else ""
    where = (f"Location: {set_name}, always the same place: {place}."
             if place else f"Setting: {series['setting']}.")
    return (f"{keep}{text}. {who} Framing: {framing}; {CAPTION_SPACE}. "
            f"{where}"
            + (f" Look of the series: {look}." if look else "")
            + f" {STYLE}")


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

    def set_reference(self, name: str, description: str, series: dict):
        img = self._run(self.ref_model, {
            "prompt": set_prompt(name, description, series),
            "image_size": "portrait_16_9", "output_format": "jpeg",
            "enable_safety_checker": True,
        })
        return img, self.usd_per_ref

    def scene(self, visual: str, speaker: str, series: dict, ref_url=None, set_ref=None):
        """Scene still -> (jpeg bytes, cost). With ref_url the speaker keeps their face.
        (Kontext takes one image, so the set is kept by its description only.)"""
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

    def set_reference(self, name, description, series):
        return self._card(f"SET\n{name}", "0x333333"), 0.0

    def scene(self, visual, speaker, series, ref_url=None, set_ref=None):
        return self._card(f"[{speaker}]\n{split_set(visual)[0]}",
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

    def _run(self, prompt: str, *refs) -> bytes:
        files = {}
        for i, ref in enumerate(r for r in refs if r):
            files[f"input_image_{i}"] = (f"ref{i}.jpg", shrink_jpeg(ref), "image/jpeg")
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
        try:
            return self._run(character_prompt(character, series)), self.usd_per_image
        except ContentFlagged:
            # The safety filter misfires on some descriptions: a plainer portrait prompt.
            plain = (f"Friendly head-and-shoulders portrait photo of an adult, "
                     f"{character.get('role') or 'a character'}, in {series['setting']}. "
                     f"Fully clothed, smiling, plain background. {STYLE}")
            return self._run(plain), self.usd_per_image

    def set_reference(self, name: str, description: str, series: dict):
        """Reference picture of a recurring place, made once per series."""
        try:
            return self._run(set_prompt(name, description, series)), self.usd_per_image
        except ContentFlagged:
            plain = f"Empty interior or landscape, no people: {description}. {STYLE}"
            return self._run(plain), self.usd_per_image

    def scene(self, visual: str, speaker: str, series: dict, ref=None, set_ref=None):
        """Scene still. ref = the speaker's portrait (keeps the face), set_ref = the
        place's reference picture (keeps the background)."""
        base = scene_prompt(visual, speaker, series, False)
        place = ("keep the place exactly the same: same architecture, walls, furniture, "
                 "windows and colours; only the camera angle may change")
        tries = []
        if ref and set_ref:
            tries.append((f"The person in image 0 is {speaker}: keep their face, hair and look "
                          f"exactly the same. Image 1 shows the location: {place}. {base}",
                          (ref, set_ref)))
        if ref:
            tries.append((f"The person in image 0 is {speaker}. Keep their face, hair and look "
                          f"exactly the same. {base}", (ref,)))
        if set_ref:
            tries.append((f"Image 0 shows the location: {place}. {base}", (set_ref,)))
        tries.append((base, ()))
        for prompt, refs in tries:
            try:
                return self._run(prompt, *refs), self.usd_per_image
            except ContentFlagged:
                continue  # the safety filter sometimes misfires on edits: try the next way
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
