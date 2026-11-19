"""Runs the pipeline end to end with an in-memory database and the fake model.

    cd worker && python -m unittest discover -s tests
"""

import unittest

from sos_worker import story
from sos_worker.llm import FakeLLM, parse_json, LLMError
from sos_worker.pipeline import Pipeline


class MemoryDb:
    def __init__(self):
        self.series = {
            "s1": {"id": "s1", "title": "Red Villa", "genre": "Drama",
                   "setting": "A mansion", "season_plan": None,
                   "characters": [{"name": "Defne", "role": "Heir"},
                                  {"name": "Kerem", "role": "Lawyer"}]},
        }
        self.jobs = []
        self.episodes = {}  # number -> dict
        self.winners = {}   # episode number -> winning label

    def get_series(self, sid):
        return self.series[sid]

    def save_season_plan(self, sid, plan):
        self.series[sid]["season_plan"] = plan

    def enqueue(self, sid, job_type, payload, episode_id=None):
        self.jobs.append({"series_id": sid, "type": job_type, "payload": payload})

    def episode_summaries(self, sid):
        return [dict(number=n, **e) for n, e in sorted(self.episodes.items())]

    def episode_exists(self, sid, number):
        return number in self.episodes

    def poll_winner(self, sid, number):
        return self.winners.get(number)

    def publish_episode(self, sid, number, title, summary, scenes, options, hours):
        self.episodes[number] = {"title": title, "summary": summary,
                                 "scenes": scenes, "options": options, "hours": hours}
        return f"e{number}"


class PipelineTest(unittest.TestCase):
    def setUp(self):
        self.db = MemoryDb()
        self.pipe = Pipeline(self.db, FakeLLM(), poll_hours=24)

    def test_season_plan_queues_episode_one(self):
        self.pipe.run({"type": "season_plan", "series_id": "s1"})
        self.assertEqual(len(self.db.series["s1"]["season_plan"]["episodes"]), 5)
        self.assertEqual(self.db.jobs, [
            {"series_id": "s1", "type": "script", "payload": {"episode": 1}}])

    def test_script_publishes_scenes_and_poll(self):
        self.pipe.run({"type": "season_plan", "series_id": "s1"})
        self.pipe.run({"type": "script", "series_id": "s1", "payload": {"episode": 1}})
        ep = self.db.episodes[1]
        self.assertGreaterEqual(len(ep["scenes"]), story.MIN_SCENES)
        self.assertTrue(all(":" in s["dialogue"] for s in ep["scenes"]))
        self.assertEqual(len(ep["options"]), 3)

    def test_winner_reaches_next_episode(self):
        self.pipe.run({"type": "script", "series_id": "s1", "payload": {"episode": 1}})
        self.db.winners[1] = "Defne runs away"
        self.pipe.run({"type": "script", "series_id": "s1", "payload": {"episode": 2}})
        first = self.db.episodes[2]["scenes"][0]["dialogue"]
        self.assertIn("Defne runs away", first)

    def test_unknown_job_type(self):
        with self.assertRaises(NotImplementedError):
            self.pipe.run({"type": "voice", "series_id": "s1"})


class HandWrittenEpisodesTest(unittest.TestCase):
    def test_season_plan_starts_after_hand_written_episodes(self):
        db = MemoryDb()
        db.episodes[1] = {"title": "Written by the owner", "summary": "", "scenes": [],
                          "options": [], "hours": 24}
        Pipeline(db, FakeLLM(), poll_hours=24).run({"type": "season_plan", "series_id": "s1"})
        scripts = [j for j in db.jobs if j["type"] == "script"]
        self.assertEqual(scripts[0]["payload"], {"episode": 2})
        self.assertEqual(db.episodes[1]["title"], "Written by the owner")


class ValidationTest(unittest.TestCase):
    def test_unknown_speaker_becomes_narrator_and_lines_are_trimmed(self):
        raw = {"title": " T ", "summary": "S",
               "scenes": [{"speaker": "Stranger", "line": "x " * 300, "visual": "v"}] * 10,
               "poll_options": ["a", "b", "", "c", "d", "e"]}
        ep = story.validate_episode(raw, ["Defne"])
        self.assertTrue(ep["scenes"][0]["dialogue"].startswith("Narrator: "))
        self.assertLessEqual(len(ep["scenes"][0]["dialogue"]), story.MAX_LINE + 11)
        self.assertEqual(ep["poll_options"], ["a", "b", "c", "d"])

    def test_too_few_scenes(self):
        with self.assertRaises(story.StoryError):
            story.validate_episode({"scenes": [{"speaker": "A", "line": "hi"}],
                                    "poll_options": ["a", "b"]}, ["A"])

    def test_parse_json_with_fences(self):
        self.assertEqual(parse_json('```json\n{"a": 1}\n```'), {"a": 1})
        with self.assertRaises(LLMError):
            parse_json("not json")


if __name__ == "__main__":
    unittest.main()
