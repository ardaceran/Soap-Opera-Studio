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

    do_GET = do_POST = do_PATCH = _reply

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


if __name__ == "__main__":
    unittest.main()
