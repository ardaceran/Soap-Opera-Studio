"""Story and picture continuity between episodes."""

import unittest

from sos_worker import media, story
from sos_worker.pipeline import Pipeline

SERIES = {
    "id": "s1", "title": "The Lighthouse", "genre": "Drama",
    "setting": "A lighthouse on the Black Sea",
    "season_plan": {"logline": "x", "episodes": []},
    "characters": [
        {"id": "c1", "name": "Elif", "role": "Keeper's daughter",
         "description": "young woman, long dark hair, green raincoat"},
        {"id": "c2", "name": "Can", "role": "Fisherman", "description": ""},
    ],
}


class EpisodePromptTest(unittest.TestCase):
    def test_previous_episode_scenes_and_continuity_rules_are_in_the_prompt(self):
        p = story.episode_prompt(
            SERIES, 2, [{"number": 1, "title": "The Storm", "summary": "A boat crashes."}],
            "Elif runs down to the beach",
            ["Can: It was your father's boat.", "Narrator: What should Elif do?"])
        self.assertIn("1. Can: It was your father's boat.", p)
        self.assertIn("never contradict earlier episodes", p)
        self.assertIn("Viewers voted: Elif runs down to the beach", p)

    def test_first_episode_has_no_previous_scenes(self):
        p = story.episode_prompt(SERIES, 1, [], None)
        self.assertNotIn("scene by scene", p)


class LooksTest(unittest.TestCase):
    def test_scene_prompt_carries_the_look_of_named_characters(self):
        p = media.scene_prompt("Elif and Can at a window", "Narrator", SERIES, False)
        self.assertIn("Elif: young woman, long dark hair, green raincoat", p)
        self.assertNotIn("Can:", p)  # no description yet, nothing to add

    def test_plan_looks_are_kept_and_cleaned(self):
        plan = story.validate_plan({"logline": "l", "episodes": [{"title": "a"}],
                                    "looks": {"Can": "  man,  short beard  ", "Ghost": ""}})
        self.assertEqual(plan["looks"], {"Can": "man, short beard"})

    def test_season_plan_writes_missing_looks_only(self):
        class Db:
            updated = {}
            def get_series(self, sid): return dict(SERIES, season_plan=None)
            def save_season_plan(self, sid, plan): pass
            def episode_exists(self, sid, n): return False
            def enqueue(self, *a, **k): pass
            def update_character(self, cid, values): self.updated[cid] = values

        class Llm:
            name = "test"
            def generate_json(self, system, prompt, kind):
                return {"logline": "l", "episodes": [{"title": "a"}],
                        "looks": {"Elif": "other look", "can": "man, short beard"}}

        db = Db()
        Pipeline(db, Llm(), poll_hours=24).run({"type": "season_plan", "series_id": "s1"})
        self.assertEqual(db.updated, {"c2": {"description": "man, short beard"}})


if __name__ == "__main__":
    unittest.main()
