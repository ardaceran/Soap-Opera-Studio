"""Recurring sets keep backgrounds the same; episode 1 opens slowly."""

import json
import shutil
import unittest
from unittest import mock

from sos_worker import http, media, story
from sos_worker.llm import FakeLLM
from sos_worker.pipeline import Pipeline

HAS_FFMPEG = bool(shutil.which("ffmpeg"))
PLAN = {"logline": "x", "visual_style": "warm amber",
        "sets": {"Manor kitchen": "stone floor, copper pans, oak table, tall window",
                 "Vineyard": "rolling rows of vines, chalk path, oak tree"},
        "episodes": [{"number": 1, "title": "t", "outline": "o"}]}
SERIES = {"id": "s1", "owner_id": "u1", "title": "The Vineyard Secret", "genre": "Drama",
          "setting": "Hartwell Estate, Sussex, England", "season_plan": PLAN,
          "characters": [{"id": "c1", "name": "Emily", "role": "Heiress",
                          "description": "woman, red hair"}]}


class PromptTest(unittest.TestCase):
    def test_plan_prompt_asks_for_sets_and_validation_keeps_them(self):
        self.assertIn('"sets"', story.season_plan_prompt(SERIES))
        plan = story.validate_plan({**PLAN, "sets": {"A": "a place", "": "x", "B": " "}})
        self.assertEqual(plan["sets"], {"A": "a place"})

    def test_episode_1_opens_slowly_and_lists_sets(self):
        p1 = story.episode_prompt(SERIES, 1, [], None)
        self.assertIn("Do not start with the conflict", p1)
        self.assertIn("Manor kitchen: stone floor", p1)
        self.assertIn('"set" is one of: Manor kitchen, Vineyard', p1)
        self.assertNotIn("Do not start with the conflict", story.episode_prompt(SERIES, 2, [], "x"))

    def test_set_tag_is_kept_in_the_visual(self):
        raw = {"title": "t", "poll_options": ["a", "b"], "scenes": [
            {"speaker": "Emily", "line": f"line {i}", "shot": "medium",
             "set": "manor KITCHEN" if i % 2 else "Nowhere", "visual": "Emily at the table"}
            for i in range(8)]}
        ep = story.validate_episode(raw, ["Emily"], ["Manor kitchen", "Vineyard"])
        self.assertEqual(ep["scenes"][1]["visual"], "Medium: Emily at the table [set: Manor kitchen]")
        self.assertEqual(ep["scenes"][0]["visual"], "Medium: Emily at the table")

    def test_scene_prompt_uses_the_fixed_set(self):
        p = media.scene_prompt("Wide: Emily walks in [set: Vineyard]", "Emily", SERIES, False)
        self.assertIn("Location: Vineyard, always the same place: rolling rows of vines", p)
        self.assertNotIn("[set:", p)
        self.assertEqual(media.split_set("Wide: a [set: Vineyard]"), ("Wide: a", "Vineyard"))


class CloudflareSetTest(unittest.TestCase):
    def test_scene_sends_portrait_and_set_as_two_references(self):
        cf = media.CloudflareImages("a", "t", "m", 0.001)
        with mock.patch.object(media, "shrink_jpeg", side_effect=lambda b: b), \
                mock.patch.object(http, "raw", return_value=b"\xff\xd8IMG") as req:
            cf.scene("Medium: Emily cooks [set: Manor kitchen]", "Emily", SERIES,
                     b"FACE", set_ref=b"ROOM")
        body = req.call_args.args[3]
        self.assertIn(b'name="input_image_0"', body)
        self.assertIn(b'name="input_image_1"', body)
        self.assertIn(b"Image 1 shows the location", body)


class BytesImages(media.FakeImages):
    ref_kind = "bytes"

    def __init__(self):
        self.made_sets, self.seen = [], []

    def set_reference(self, name, description, series):
        self.made_sets.append(name)
        return super().set_reference(name, description, series)

    def scene(self, visual, speaker, series, ref=None, set_ref=None):
        self.seen.append((media.split_set(visual)[1], set_ref is not None))
        return super().scene(visual, speaker, series)


class Db:
    def __init__(self):
        self.series = json.loads(json.dumps(SERIES))
        self.files, self.saved_plans = {}, []
        self.episode = {"id": "e1", "series_id": "s1", "number": 1, "title": "Arrival",
                        "poll_options": ["a", "b"], "series": self.series, "scenes": [
                            {"id": f"sc{i}", "idx": i, "dialogue": "Emily: Hello there.",
                             "visual_prompt": f"Medium: Emily [set: {'Vineyard' if i < 3 else 'Manor kitchen'}]"}
                            for i in range(1, 6)]}

    def get_episode_for_render(self, eid): return self.episode
    def update_character(self, cid, v): pass
    def update_scene(self, sid, v): pass
    def set_episode_video(self, eid, p): pass
    def set_poll_closes(self, eid, t): pass
    def save_season_plan(self, sid, plan): self.saved_plans.append(json.loads(json.dumps(plan)))
    def signed_url(self, b, p, seconds=3600): return f"https://signed/{p}"
    def upload(self, bucket, path, data, ctype):
        self.files[f"{bucket}/{path}"] = data
        return path


@unittest.skipUnless(HAS_FFMPEG, "ffmpeg not installed")
class AssembleSetsTest(unittest.TestCase):
    def test_one_reference_per_set_saved_and_reused(self):
        db, images = Db(), BytesImages()
        pipe = Pipeline(db, FakeLLM(), 24, images=images, video_height=640)
        pipe.run({"type": "assemble", "series_id": "s1", "episode_id": "e1"})
        self.assertEqual(images.made_sets, ["Vineyard", "Manor kitchen"])
        self.assertTrue(all(has for _, has in images.seen))
        self.assertIn("character-refs/u1/s1/set-vineyard.jpg", db.files)
        self.assertEqual(db.saved_plans[-1]["set_refs"],
                         {"Vineyard": "u1/s1/set-vineyard.jpg",
                          "Manor kitchen": "u1/s1/set-manor-kitchen.jpg"})

    def test_saved_reference_is_downloaded_not_redrawn(self):
        db, images = Db(), BytesImages()
        db.series["season_plan"]["set_refs"] = {"Vineyard": "u1/s1/set-vineyard.jpg",
                                                "Manor kitchen": "u1/s1/set-manor-kitchen.jpg"}
        pipe = Pipeline(db, FakeLLM(), 24, images=images, video_height=640)
        with mock.patch.object(http, "download", return_value=b"OLD") as dl:
            pipe.run({"type": "assemble", "series_id": "s1", "episode_id": "e1"})
        self.assertEqual(images.made_sets, [])
        # each saved set picture is downloaded once (Emily's portrait is new in this run)
        self.assertEqual(dl.call_count, 2)


if __name__ == "__main__":
    unittest.main()
