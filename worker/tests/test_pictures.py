"""Picture prompts: people count, framing by shot type, narrator shots, series look,
and when the character portrait is used."""

import unittest

from sos_worker import media, story

SERIES = {
    "id": "s1", "owner_id": "u1", "title": "The Lighthouse", "genre": "Drama",
    "setting": "A lighthouse on the Black Sea",
    "season_plan": {"visual_style": "cold blue-grey palette, stormy night light"},
    "characters": [
        {"id": "c1", "name": "Elif", "description": "young woman, green raincoat"},
        {"id": "c2", "name": "Can", "description": "man, short beard"},
    ],
}


class ShotTest(unittest.TestCase):
    def test_writer_shot_is_kept_in_the_visual_and_defaults_are_sane(self):
        scenes = [{"speaker": "Elif", "line": f"l{i}", "shot": "Close-Up", "visual": "v"}
                  for i in range(7)] + [
                 {"speaker": "Narrator", "line": "n", "visual": "sea"},
                 {"speaker": "Can", "line": "c", "shot": "dolly zoom", "visual": "door"}]
        ep = story.validate_episode({"scenes": scenes, "poll_options": ["a", "b"]},
                                    ["Elif", "Can"])
        self.assertEqual(ep["scenes"][0]["visual"], "Close-up: v")
        self.assertEqual(ep["scenes"][7]["visual"], "Establishing: sea")  # narrator default
        self.assertEqual(ep["scenes"][8]["visual"], "Medium: door")       # unknown shot

    def test_split_shot(self):
        self.assertEqual(media.split_shot("Wide: Elif on the cliff"), ("wide", "Elif on the cliff"))
        self.assertEqual(media.split_shot("Elif: on the cliff"), (None, "Elif: on the cliff"))


class PromptTest(unittest.TestCase):
    def test_establishing_shot_has_no_people_even_if_named(self):
        p = media.scene_prompt("Establishing: the lighthouse Elif lives in", "Narrator",
                               SERIES, False)
        self.assertIn("No people in the frame", p)
        self.assertNotIn("Exactly", p)

    def test_one_person_close_up_is_off_centre_with_series_look(self):
        p = media.scene_prompt("Close-up: Elif in tears", "Elif", SERIES, True)
        self.assertIn("Exactly 1 person in the frame: Elif (young woman, green raincoat)", p)
        self.assertIn("off-centre", p)
        self.assertIn("cold blue-grey palette", p)
        self.assertIn("bottom third", p)
        self.assertIn("Keep this person's face", p)

    def test_speaker_counts_when_no_one_is_named(self):
        p = media.scene_prompt("Medium: hands on the railing, looking at the sea", "Can",
                               SERIES, False)
        self.assertIn("Exactly 1 person in the frame: Can", p)


class PortraitRuleTest(unittest.TestCase):
    """The portrait goes only to one-person medium / close-up shots of the speaker."""

    def rule(self, visual, speaker):
        return media.use_portrait(visual, speaker, SERIES)

    def test_rule(self):
        self.assertTrue(self.rule("Close-up: Elif in tears", "Elif"))
        self.assertFalse(self.rule("Medium: Elif and Can at a window", "Elif"))  # two people
        self.assertFalse(self.rule("Wide: Elif on the cliff", "Elif"))          # wide shot
        self.assertFalse(self.rule("Close-up: Can listening", "Elif"))          # not the speaker


if __name__ == "__main__":
    unittest.main()
