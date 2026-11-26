"""Checks the real HTTP code (Supabase REST + Gemini) against a local fake server."""

import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

from sos_worker.config import Config
from sos_worker.db import Db
from sos_worker.llm import GeminiLLM

SEEN = []
REPLIES = {}


class Handler(BaseHTTPRequestHandler):
    def _reply(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n)) if n else None
        SEEN.append({"method": self.command, "path": self.path,
                     "headers": {k.lower(): v for k, v in self.headers.items()}, "body": body})
        key = (self.command, self.path.split("?")[0])
        status, payload = REPLIES.get(key, (200, None))
        data = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _reply_any(self):
        # Storage uploads send raw bytes, not JSON.
        if self.headers.get("Content-Type", "").startswith("application/json") \
                or not self.headers.get("Content-Length"):
            return self._reply()
        n = int(self.headers.get("Content-Length") or 0)
        SEEN.append({"method": self.command, "path": self.path,
                     "headers": {k.lower(): v for k, v in self.headers.items()},
                     "body": self.rfile.read(n)})
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"{}")

    do_GET = do_PATCH = _reply
    do_POST = _reply_any

    def log_message(self, *a):
        pass


class HttpTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = HTTPServer(("127.0.0.1", 0), Handler)
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        SEEN.clear()
        REPLIES.clear()
        self.cfg = Config(self.base, "sb_secret_test", "fake", "", "m", 24, 1, 3)

    def test_empty_queue_returns_none(self):
        REPLIES[("POST", "/rest/v1/rpc/claim_next_job")] = (
            200, {"id": None, "type": None, "series_id": None})
        self.assertIsNone(Db(self.cfg).claim_next_job())
        h = SEEN[0]["headers"]
        self.assertEqual(h.get("apikey"), "sb_secret_test")
        self.assertNotIn("authorization", h)  # sb_secret keys go only in apikey

    def test_legacy_jwt_key_also_sent_as_bearer(self):
        cfg = Config(self.base, "eyJabc", "fake", "", "m", 24, 1, 3)
        REPLIES[("POST", "/rest/v1/rpc/claim_next_job")] = (200, None)
        Db(cfg).claim_next_job()
        self.assertEqual(SEEN[0]["headers"].get("authorization"), "Bearer eyJabc")

    def test_publish_and_finish(self):
        db = Db(self.cfg)
        REPLIES[("POST", "/rest/v1/rpc/worker_publish_episode")] = (200, "ep-1")
        self.assertEqual(db.publish_episode("s", 1, "T", "S",
                                            [{"dialogue": "A: hi", "visual": "v"}],
                                            ["x", "y"], 24), "ep-1")
        self.assertEqual(SEEN[0]["body"]["p_poll_options"], ["x", "y"])
        db.finish_job("j1", "gemini")
        self.assertEqual(SEEN[1]["method"], "PATCH")
        self.assertIn("id=eq.j1", SEEN[1]["path"])
        self.assertEqual(SEEN[1]["body"]["status"], "done")

    def test_release_and_touch_only_affect_running_jobs(self):
        db = Db(self.cfg)
        db.release_job("j9", 3)
        db.touch_job("j9")
        self.assertIn("id=eq.j9&status=eq.running", SEEN[0]["path"])
        self.assertEqual(SEEN[0]["body"]["status"], "queued")
        self.assertEqual(SEEN[0]["body"]["attempts"], 2)  # the interrupted try does not count
        self.assertIn("status=eq.running", SEEN[1]["path"])
        self.assertEqual(set(SEEN[1]["body"]), {"updated_at"})

    def test_poll_winner(self):
        REPLIES[("GET", "/rest/v1/episodes")] = (200, [{"polls": [{
            "winner_option_id": "o2",
            "poll_options": [{"id": "o1", "label": "A"}, {"id": "o2", "label": "B"}]}]}])
        self.assertEqual(Db(self.cfg).poll_winner("s", 1), "B")

    def test_gemini_request_and_parse(self):
        llm = GeminiLLM("gkey", "gemini-test")
        llm.URL = self.base + "/v1beta/models/{model}:generateContent"
        REPLIES[("POST", "/v1beta/models/gemini-test:generateContent")] = (200, {
            "candidates": [{"content": {"parts": [{"text": '{"ok": true}'}]}}]})
        self.assertEqual(llm.generate_json("sys", "prompt", "episode"), {"ok": True})
        self.assertEqual(SEEN[0]["headers"].get("x-goog-api-key"), "gkey")
        self.assertEqual(SEEN[0]["body"]["generationConfig"]["responseMimeType"],
                         "application/json")

    def test_gemini_busy_is_retried_then_transient(self):
        from sos_worker.llm import TransientLLMError, LLMError
        llm = GeminiLLM("gkey", "busy-model", waits=(0, 0))
        llm.URL = self.base + "/v1beta/models/{model}:generateContent"
        REPLIES[("POST", "/v1beta/models/busy-model:generateContent")] = (
            503, {"error": {"code": 503, "status": "UNAVAILABLE"}})
        with self.assertRaises(TransientLLMError):
            llm.generate_json("s", "p", "episode")
        self.assertEqual(len(SEEN), 3)  # first try + 2 retries
        SEEN.clear()
        REPLIES[("POST", "/v1beta/models/busy-model:generateContent")] = (
            404, {"error": {"code": 404}})
        with self.assertRaises(LLMError) as ctx:
            llm.generate_json("s", "p", "episode")
        self.assertNotIsInstance(ctx.exception, TransientLLMError)
        self.assertEqual(len(SEEN), 1)  # no retry on a real error

    def test_vote_closing_requests(self):
        db = Db(self.cfg)
        REPLIES[("PATCH", "/rest/v1/polls")] = (200, [{"id": "p1"}])
        REPLIES[("GET", "/rest/v1/votes")] = (200, [{"option_id": "a"}, {"option_id": "a"},
                                                    {"option_id": "b"}])
        self.assertEqual(db.vote_counts("p1"), {"a": 2, "b": 1})
        self.assertTrue(db.set_winner("p1", "a"))
        patch = SEEN[-1]
        # only a poll without a winner may be closed (two workers never both win)
        self.assertIn("winner_option_id=is.null", patch["path"])
        self.assertEqual(patch["body"], {"winner_option_id": "a"})
        REPLIES[("PATCH", "/rest/v1/polls")] = (200, [])
        self.assertFalse(db.set_winner("p1", "b"))
        db.due_polls("2026-11-20T10:00:00Z")
        self.assertIn("closes_at=lte.2026-11-20T10:00:00Z", SEEN[-1]["path"])

    def test_requeue_stale_and_job_counts(self):
        db = Db(self.cfg)
        REPLIES[("PATCH", "/rest/v1/jobs")] = (200, [{"id": "j1"}, {"id": "j2"}])
        self.assertEqual(db.requeue_stale("2026-11-19T13:30:00Z"), 2)
        patch = SEEN[-1]
        self.assertIn("status=eq.running", patch["path"])
        self.assertIn("updated_at=lt.2026-11-19T13:30:00Z", patch["path"])
        self.assertEqual(patch["body"]["status"], "queued")
        REPLIES[("GET", "/rest/v1/jobs")] = (200, [{"status": "done"}, {"status": "done"},
                                                   {"status": "failed"}])
        self.assertEqual(db.job_counts(), {"done": 2, "failed": 1})

    def test_storage_upload_and_signed_url(self):
        db = Db(self.cfg)
        db.upload("episodes", "s1/e1.mp4", b"\x00mp4", "video/mp4")
        up = SEEN[-1]
        self.assertEqual(up["path"], "/storage/v1/object/episodes/s1/e1.mp4")
        self.assertEqual(up["headers"]["x-upsert"], "true")
        self.assertEqual(up["headers"]["content-type"], "video/mp4")
        self.assertEqual(up["body"], b"\x00mp4")
        REPLIES[("POST", "/storage/v1/object/sign/character-refs/u/s/c.jpg")] = (
            200, {"signedURL": "/object/sign/character-refs/u/s/c.jpg?token=t"})
        url = db.signed_url("character-refs", "u/s/c.jpg")
        self.assertEqual(url, self.base + "/storage/v1/object/sign/character-refs/u/s/c.jpg?token=t")


class TimeoutTest(unittest.TestCase):
    def test_gemini_timeout_is_transient(self):
        from unittest import mock
        from sos_worker import llm as llm_mod
        g = llm_mod.GeminiLLM("k", "m", waits=(0,))
        with mock.patch.object(llm_mod.http, "request", side_effect=TimeoutError("timed out")) as req:
            with self.assertRaises(llm_mod.TransientLLMError):
                g.generate_json("s", "p", "episode")
        self.assertEqual(req.call_count, 2)
        self.assertEqual(req.call_args.kwargs.get("timeout"), llm_mod.LLM_TIMEOUT)


if __name__ == "__main__":
    unittest.main()
