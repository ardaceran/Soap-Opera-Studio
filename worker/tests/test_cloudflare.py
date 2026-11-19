"""Cloudflare Workers AI providers with the HTTP call replaced (no network, no key)."""

import base64
import json
import shutil
import unittest
from unittest import mock

from sos_worker import http, media

HAS_FFMPEG = bool(shutil.which("ffmpeg"))
SERIES = {"genre": "Drama", "setting": "A vineyard house in Urla"}


def form_fields(body: bytes, ctype: str) -> dict:
    """Parse our multipart body back into {name: bytes}."""
    boundary = ctype.split("boundary=")[1].encode()
    out = {}
    for part in body.split(b"--" + boundary)[1:-1]:
        head, _, data = part.partition(b"\r\n\r\n")
        name = head.split(b'name="')[1].split(b'"')[0].decode()
        out[name] = data[:-2]
    return out


class CloudflareImagesTest(unittest.TestCase):
    def setUp(self):
        self.cf = media.CloudflareImages("acc", "tok", "@cf/black-forest-labs/flux-2-klein-4b",
                                         0.001)

    def test_portrait_request_is_vertical_multipart(self):
        img = base64.b64encode(b"JPEGDATA").decode()
        reply = json.dumps({"result": {"image": img}, "success": True}).encode()
        with mock.patch.object(http, "raw", return_value=reply) as req:
            out, usd = self.cf.reference({"name": "Defne", "role": "Heir"}, SERIES)
        self.assertEqual((out, usd), (b"JPEGDATA", 0.001))
        method, url, headers, body, ctype = req.call_args.args[:5]
        self.assertEqual(url, "https://api.cloudflare.com/client/v4/accounts/acc/ai/run/"
                              "@cf/black-forest-labs/flux-2-klein-4b")
        self.assertEqual(headers["Authorization"], "Bearer tok")
        f = form_fields(body, ctype)
        self.assertEqual((f["width"], f["height"]), (b"576", b"1024"))
        self.assertIn(b"Defne", f["prompt"])
        self.assertNotIn("input_image_0", f)

    def test_raw_image_reply_is_accepted(self):
        with mock.patch.object(http, "raw", return_value=b"\xff\xd8\xffJPEG"):
            out, _ = self.cf.scene("Rain on the house", "Narrator", SERIES)
        self.assertEqual(out, b"\xff\xd8\xffJPEG")

    def test_error_reply_is_an_error(self):
        bad = json.dumps({"success": False, "errors": [{"message": "quota"}]}).encode()
        with mock.patch.object(http, "raw", return_value=bad):
            with self.assertRaises(media.MediaError):
                self.cf.scene("x", "Narrator", SERIES)

    @unittest.skipUnless(HAS_FFMPEG, "ffmpeg not installed")
    def test_scene_sends_the_portrait_as_a_small_reference(self):
        portrait, _ = media.FakeImages().reference({"name": "Defne"}, SERIES)  # 576x1024
        with mock.patch.object(http, "raw", return_value=b"\xff\xd8IMG") as req:
            self.cf.scene("Defne at the door", "Defne", SERIES, portrait)
        method, url, headers, body, ctype = req.call_args.args[:5]
        f = form_fields(body, ctype)
        self.assertIn("input_image_0", f)
        self.assertIn(b"image 0 is Defne", f["prompt"])
        # the reference was shrunk below 512x512
        import subprocess, tempfile, pathlib
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d, "r.jpg")
            p.write_bytes(f["input_image_0"])
            w, h = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                                   "stream=width,height", "-of", "csv=p=0", str(p)],
                                  capture_output=True, text=True).stdout.strip().split(",")
        self.assertLess(int(w), 512)
        self.assertLess(int(h), 512)


class CloudflareVoiceTest(unittest.TestCase):
    def setUp(self):
        self.v = media.CloudflareVoice("acc", "tok", "@cf/deepgram/aura-1", 0.000015)

    def test_speak_sends_speaker_and_returns_mp3(self):
        with mock.patch.object(http, "raw", return_value=b"ID3mp3") as req:
            mp3, usd = self.v.speak("Hello there", "luna")
        self.assertEqual(mp3, b"ID3mp3")
        self.assertAlmostEqual(usd, 11 * 0.000015)
        body = json.loads(req.call_args.args[3])
        self.assertEqual(body, {"text": "Hello there", "speaker": "luna", "encoding": "mp3"})

    def test_base64_json_reply(self):
        reply = json.dumps({"result": {"audio": base64.b64encode(b"MP3").decode()}}).encode()
        with mock.patch.object(http, "raw", return_value=reply):
            self.assertEqual(self.v.speak("Hi", "zeus")[0], b"MP3")


class VoicePickTest(unittest.TestCase):
    def test_gender_hints_and_alternation(self):
        V = media.CloudflareVoice
        used = set()
        mother = media.pick_voice({"role": "Mother", "description": ""}, used, V, 1)
        lawyer = media.pick_voice({"role": "Family lawyer", "description": "he is 40"},
                                  used, V, 0)
        unknown0 = media.pick_voice({"role": "Heir"}, used, V, 0)
        self.assertIn(mother, media.AURA_VOICES["female"])
        self.assertIn(lawyer, media.AURA_VOICES["male"])
        self.assertIn(unknown0, media.AURA_VOICES["female"])  # no hint: index 0 -> female

    def test_voice_from_another_provider_is_replaced(self):
        eleven_id = "21m00Tcm4TlvDq8ikWAM"
        v = media.pick_voice({"role": "Mother", "voice_id": eleven_id}, set(),
                             media.CloudflareVoice)
        self.assertIn(v, media.AURA_VOICES["female"])
        # and kept when it belongs to the provider
        self.assertEqual(media.pick_voice({"voice_id": "luna"}, set(), media.CloudflareVoice),
                         "luna")


if __name__ == "__main__":
    unittest.main()
