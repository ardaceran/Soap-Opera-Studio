"""Closing finished votes: winner, next episode queued, season end, races.

    cd worker && python -m unittest discover -s tests
"""

import unittest
from datetime import datetime, timedelta, timezone

from sos_worker.llm import FakeLLM
from sos_worker.pipeline import Pipeline

A, B, C = "oA", "oB", "oC"


class VoteDb:
    def __init__(self, number=1, votes=None, plan_len=3, existing=()):
        self.poll = {"id": "p1", "episode_id": "e1",
                     "episodes": {"series_id": "s1", "number": number},
                     "poll_options": [{"id": A, "label": "Defne runs"},
                                      {"id": B, "label": "Kerem confesses"},
                                      {"id": C, "label": "Mother arrives"}]}
        self.votes = votes or {}
        self.winner = None
        self.jobs = []
        self.plan_len = plan_len
        self.existing = set(existing)
        self.asked_now = None

    def due_polls(self, now_iso):
        self.asked_now = now_iso
        return [] if self.winner else [self.poll]

    def vote_counts(self, pid):
        return self.votes

    def set_winner(self, pid, oid):
        if self.winner:
            return False
        self.winner = oid
        return True

    def get_series(self, sid):
        return {"season_plan": {"episodes": [{}] * self.plan_len}}

    def episode_exists(self, sid, n):
        return n in self.existing

    def enqueue(self, sid, t, payload, episode_id=None):
        self.jobs.append((t, payload))


def pipe(db, **kw):
    return Pipeline(db, FakeLLM(), 24, **kw)


class CloseVotesTest(unittest.TestCase):
    def test_most_votes_wins_and_next_episode_is_queued(self):
        db = VoteDb(votes={A: 1, B: 4, C: 2})
        out = pipe(db).close_due_polls()
        self.assertEqual(db.winner, B)
        self.assertEqual(db.jobs, [("script", {"episode": 2})])
        self.assertEqual(out, [("s1", 2, "Kerem confesses")])

    def test_tie_goes_to_first_listed_option(self):
        db = VoteDb(votes={B: 3, C: 3})
        pipe(db).close_due_polls()
        self.assertEqual(db.winner, B)

    def test_no_votes_still_continues_the_story(self):
        db = VoteDb()
        pipe(db).close_due_polls()
        self.assertEqual(db.winner, A)
        self.assertEqual(len(db.jobs), 1)

    def test_last_episode_of_the_season_queues_nothing(self):
        db = VoteDb(number=3, votes={A: 1}, plan_len=3)
        out = pipe(db).close_due_polls()
        self.assertEqual(db.winner, A)
        self.assertEqual(db.jobs, [])
        self.assertEqual(out, [("s1", None, "Defne runs")])

    def test_existing_next_episode_is_not_written_again(self):
        db = VoteDb(votes={A: 1}, existing={2})
        pipe(db).close_due_polls()
        self.assertEqual(db.jobs, [])

    def test_closing_twice_does_nothing_the_second_time(self):
        db = VoteDb(votes={A: 1})
        p = pipe(db)
        p.close_due_polls()
        self.assertEqual(p.close_due_polls(), [])
        self.assertEqual(len(db.jobs), 1)

    def test_asks_for_polls_due_now_in_utc(self):
        db = VoteDb()
        now = datetime(2026, 11, 20, 10, 0, tzinfo=timezone.utc)
        pipe(db).close_due_polls(now)
        self.assertEqual(db.asked_now, "2026-11-20T10:00:00Z")


class VoteWindowTest(unittest.TestCase):
    def test_minutes_override_hours(self):
        self.assertEqual(pipe(VoteDb(), poll_minutes=3).poll_window, timedelta(minutes=3))
        self.assertEqual(pipe(VoteDb()).poll_window, timedelta(hours=24))


if __name__ == "__main__":
    unittest.main()
