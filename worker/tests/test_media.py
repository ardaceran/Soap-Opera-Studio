"""Video pipeline: script -> assemble job -> MP4 in storage.

Uses the free fake image/voice providers and real FFmpeg (skipped if missing).
fal.ai and ElevenLabs are tested with the HTTP call replaced.

    cd worker && python -m unittest discover -s tests
"""

import json
import shutil
import unittest
from unittest import mock

from sos_worker import http, media, video
from sos_worker.llm import FakeLLM
from sos_worker.pipeline import Pipeline, split_dialogue

HAS_FFMPEG = bool(shutil.which("ffmpeg") and shutil.which("ffprobe"))


class RenderDb:
    """In-memory stand-in for Db with what the assemble job needs."""

    def __init__(self):
        self.series = {"id": "s1", "owner_id": "u1", "title": "Red Villa",
                       "genre": "Drama", "setting": "A villa in Urla", "season_plan": None,
                       "characters": [
                           {"id": "c1", "name": "Defne", "role": "Heir",
                            "description": "dark curly hair", "voice_id": None,
                            "ref_image_paths": []},
                           {"id": "c2", "name": "Kerem", "role": "Lawyer",
                            "description": None, "voice_id": "keep-me",
                            "ref_image_paths": ["u1/s1/c2.jpg"]}]}
        self.jobs, self.files, self.char_updates, self.scene_updates = [], {}, [], {}
        self.episode = None
        self.video_path = None

    # story side
    def get_series(self, sid):
        return self.series

    def save_season_plan(self, sid, plan):
        self.series["season_plan"] = plan

    def enqueue(self, sid, job_type, payload, episode_id=None):
        self.jobs.append({"type": job_type, "payload": payload, "episode_id": episode_id})

    def episode_summaries(self, sid):
        return []

    def poll_winner(self, sid, number):
        return None

    def publish_episode(self, sid, number, title, summary, scenes, options, hours):
        self.episode = {
            "id": "e1", "series_id": sid, "number": number, "title": title,
            "scenes": [{"id": f"sc{i}", "idx": i, "dialogue": s["dialogue"],
                        "visual_prompt": s["visual"]} for i, s in enumerate(scenes, 1)],
            "poll_options": options, "series": self.series}
        return "e1"

    # media side
    def get_episode_for_render(self, episode_id):
        return self.episode

    def update_character(self, cid, values):
        self.char_updates.append((cid, values))

    def update_scene(self, scene_id, values):
        self.scene_updates[scene_id] = values

    def set_episode_video(self, eid, path):
        self.video_path = path

    def upload(self, bucket, path, data, content_type):
        self.files[f"{bucket}/{path}"] = (data, content_type)
        return path

    def signed_url(self, bucket, path, seconds=3600):
        return f"https://signed/{bucket}/{path}"


class SplitDialogueTest(unittest.TestCase):
    def test_split(self):
        self.assertEqual(split_dialogue("Defne: I knew it."), ("Defne", "I knew it."))
        self.assertEqual(split_dialogue("Rain falls."), ("Narrator", "Rain falls."))


@unittest.skipUnless(HAS_FFMPEG, "ffmpeg not installed")
class AssembleTest(unittest.TestCase):
    def setUp(self):
        self.db = RenderDb()
        self.pipe = Pipeline(self.db, FakeLLM(), 24, video_height=640, max_scenes=3)
        self.pipe.run({"type": "script", "series_id": "s1", "payload": {"episode": 1}})

    def test_script_queues_assemble_job(self):
        self.assertEqual(self.db.jobs[-1],
                         {"type": "assemble", "payload": {"episode": 1}, "episode_id": "e1"})
        self.assertEqual(self.pipe.last["episode_id"], "e1")

    def test_assemble_uploads_video_and_media(self):
        self.pipe.run({"type": "assemble", "series_id": "s1", "episode_id": "e1"})
        self.assertEqual(self.db.video_path, "s1/e1.mp4")
        data, ctype = self.db.files["episodes/s1/e1.mp4"]
        self.assertEqual(ctype, "video/mp4")
        self.assertGreater(len(data), 10_000)
        # max_scenes=3 -> 3 scenes rendered, each with image + audio
        self.assertEqual(len(self.db.scene_updates), 3)
        self.assertEqual(self.db.scene_updates["sc1"],
                         {"image_path": "s1/e1/001.jpg", "audio_path": "s1/e1/001.mp3"})
        self.assertEqual(self.pipe.last["provider"], "fake+fake")
        self.assertEqual(self.pipe.last["cost"], 0.0)

    def test_characters_keep_voice_and_get_one_portrait(self):
        self.pipe.run({"type": "assemble", "series_id": "s1", "episode_id": "e1"})
        updates = dict()
        for cid, v in self.db.char_updates:
            updates.setdefault(cid, {}).update(v)
        # Defne had nothing: gets a default voice and a portrait under the owner's folder
        self.assertIn(updates["c1"]["voice_id"], media.DEFAULT_VOICES)
        self.assertEqual(updates["c1"]["ref_image_paths"], ["u1/s1/c1.jpg"])
        # Kerem already had both: untouched
        self.assertNotIn("c2", updates)

    def test_video_is_vertical_with_audio(self):
        self.pipe.run({"type": "assemble", "series_id": "s1", "episode_id": "e1"})
        import subprocess, tempfile, pathlib
        with tempfile.TemporaryDirectory() as d:
            f = pathlib.Path(d, "e.mp4")
            f.write_bytes(self.db.files["episodes/s1/e1.mp4"][0])
            out = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                                  "stream=codec_type,width,height", "-of", "json", str(f)],
                                 capture_output=True, text=True).stdout
            streams = json.loads(out)["streams"]
            v = [s for s in streams if s["codec_type"] == "video"][0]
            self.assertEqual((v["width"], v["height"]), (360, 640))
            self.assertTrue(any(s["codec_type"] == "audio" for s in streams))
            # title card + 3 scenes + vote card
            self.assertGreater(video.duration(f), video.TITLE_SECS + video.VOTE_SECS + 3)


class PricedFake(media.FakeImages):
    name = "priced"

    def reference(self, c, s):
        return super().reference(c, s)[0], 0.003

    def scene(self, v, sp, s, ref_url=None):
        self.refs = getattr(self, "refs", []) + [ref_url]
        return super().scene(v, sp, s)[0], 0.04


@unittest.skipUnless(HAS_FFMPEG, "ffmpeg not installed")
class CostTest(unittest.TestCase):
    def test_cost_is_summed_and_faces_use_the_portrait(self):
        db = RenderDb()
        images = PricedFake()
        pipe = Pipeline(db, FakeLLM(), 24, images=images, video_height=640, max_scenes=3)
        pipe.run({"type": "script", "series_id": "s1", "payload": {"episode": 1}})
        pipe.run({"type": "assemble", "series_id": "s1", "episode_id": "e1"})
        # 1 new portrait (Defne) + 3 scenes
        self.assertAlmostEqual(pipe.last["cost"], 0.003 + 3 * 0.04)
        # Fake script: scene 1 is the Narrator (no portrait), scene 2 is Defne
        self.assertIsNone(images.refs[0])
        self.assertEqual(images.refs[1], "https://signed/character-refs/u1/s1/c1.jpg")


class FalTest(unittest.TestCase):
    def setUp(self):
        self.fal = media.FalImages("k", "fal-ai/flux/schnell", "fal-ai/flux-pro/kontext",
                                   0.003, 0.04)
        self.series = {"genre": "Drama", "setting": "Urla"}

    def test_scene_with_portrait_uses_kontext(self):
        ok = {"images": [{"url": "https://cdn/x.jpg"}], "has_nsfw_concepts": [False]}
        with mock.patch.object(http, "request", return_value=ok) as req, \
                mock.patch.object(http, "download", return_value=b"jpg"):
            img, usd = self.fal.scene("Defne at the door", "Defne", self.series, "https://ref")
        self.assertEqual((img, usd), (b"jpg", 0.04))
        method, url, headers, body = req.call_args.args
        self.assertEqual(url, "https://fal.run/fal-ai/flux-pro/kontext")
        self.assertEqual(headers["Authorization"], "Key k")
        self.assertEqual(body["image_url"], "https://ref")
        self.assertEqual(body["aspect_ratio"], "9:16")

    def test_narrator_scene_uses_cheap_model(self):
        ok = {"images": [{"url": "https://cdn/x.jpg"}]}
        with mock.patch.object(http, "request", return_value=ok) as req, \
                mock.patch.object(http, "download", return_value=b"jpg"):
            _, usd = self.fal.scene("Rain on the villa", "Narrator", self.series)
        self.assertEqual(usd, 0.003)
        self.assertEqual(req.call_args.args[1], "https://fal.run/fal-ai/flux/schnell")
        self.assertEqual(req.call_args.args[3]["image_size"], "portrait_16_9")

    def test_blocked_image_is_an_error(self):
        bad = {"images": [{"url": "u"}], "has_nsfw_concepts": [True]}
        with mock.patch.object(http, "request", return_value=bad):
            with self.assertRaises(media.MediaError):
                self.fal.reference({"name": "A"}, self.series)


class ElevenTest(unittest.TestCase):
    def test_speak_sends_text_and_counts_characters(self):
        v = media.ElevenVoice("xk", "eleven_multilingual_v2", 0.0003)
        with mock.patch.object(http, "raw", return_value=b"mp3") as req:
            mp3, usd = v.speak("Hello there", "voice1")
        self.assertEqual(mp3, b"mp3")
        self.assertAlmostEqual(usd, 11 * 0.0003)
        method, url, headers, body, ctype = req.call_args.args[:5]
        self.assertIn("/text-to-speech/voice1", url)
        self.assertEqual(headers["xi-api-key"], "xk")
        self.assertEqual(json.loads(body)["model_id"], "eleven_multilingual_v2")


class MakeMediaTest(unittest.TestCase):
    def cfg(self, mode, fal="", el=""):
        return mock.Mock(media_provider=mode, fal_key=fal, elevenlabs_key=el,
                         fal_ref_model="r", fal_scene_model="s", fal_usd_per_ref=0,
                         fal_usd_per_scene=0, elevenlabs_model="m",
                         elevenlabs_usd_per_char=0)

    def test_auto_uses_real_only_with_keys(self):
        i, v = media.make_media(self.cfg("auto"))
        self.assertEqual((i.name, v.name), ("fake", "fake"))
        i, v = media.make_media(self.cfg("auto", "f", "e"))
        self.assertEqual((i.name, v.name), ("fal", "elevenlabs"))

    def test_real_without_keys_stops(self):
        with self.assertRaises(SystemExit):
            media.make_media(self.cfg("real", "f", ""))


if __name__ == "__main__":
    unittest.main()
