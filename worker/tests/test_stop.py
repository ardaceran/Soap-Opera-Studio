"""Stopping the worker mid-job and the heartbeat of a running job."""

import time
import unittest

from sos_worker.__main__ import Heartbeat


class FakeDb:
    def __init__(self):
        self.touched = 0

    def touch_job(self, job_id):
        self.touched += 1


class HeartbeatTest(unittest.TestCase):
    def test_beats_while_running_and_stops_after(self):
        db = FakeDb()
        with Heartbeat(db, "j1", every=0.05):
            time.sleep(0.18)
        beats = db.touched
        self.assertGreaterEqual(beats, 2)
        time.sleep(0.15)
        self.assertEqual(db.touched, beats)  # no beats after the job ended

    def test_a_failing_beat_does_not_break_the_job(self):
        class Broken:
            def touch_job(self, job_id):
                raise OSError("network down")
        with Heartbeat(Broken(), "j1", every=0.02):
            time.sleep(0.06)


if __name__ == "__main__":
    unittest.main()
