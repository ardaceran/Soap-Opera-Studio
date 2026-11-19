"""ClaudeLLM with the HTTP call replaced: no network, no key needed."""

import unittest
from unittest import mock

from sos_worker import http, llm
from sos_worker.llm import ClaudeLLM, LLMError, TransientLLMError


def reply(text, stop="end_turn"):
    return {"content": [{"type": "text", "text": text}], "stop_reason": stop,
            "usage": {"input_tokens": 120, "output_tokens": 340}}


class ClaudeTest(unittest.TestCase):
    def setUp(self):
        self.llm = ClaudeLLM("key", "claude-sonnet-5-5", waits=(0, 0))

    def test_sends_messages_request_and_parses_json(self):
        with mock.patch.object(http, "request", return_value=reply('{"title": "Ep 1"}')) as req:
            out = self.llm.generate_json("sys", "Write episode 1", "script")
        self.assertEqual(out, {"title": "Ep 1"})
        method, url, headers, body = req.call_args.args
        self.assertEqual(url, "https://api.anthropic.com/v1/messages")
        self.assertEqual(headers["x-api-key"], "key")
        self.assertEqual(body["model"], "claude-sonnet-5-5")
        self.assertEqual(body["messages"][0]["content"], "Write episode 1")
        self.assertEqual(self.llm.last_usage["output_tokens"], 340)

    def test_tolerates_fences_and_prose(self):
        with mock.patch.object(http, "request", return_value=reply('Here:\n```json\n{"a": 1}\n```')):
            self.assertEqual(self.llm.generate_json("s", "p", "script"), {"a": 1})

    def test_retries_when_overloaded(self):
        busy = http.HttpError(529, "overloaded")
        with mock.patch.object(http, "request", side_effect=[busy, reply('{"ok": true}')]):
            self.assertEqual(self.llm.generate_json("s", "p", "script"), {"ok": True})

    def test_gives_up_after_retries(self):
        with mock.patch.object(http, "request", side_effect=http.HttpError(529, "x")):
            with self.assertRaises(TransientLLMError):
                self.llm.generate_json("s", "p", "script")

    def test_bad_request_is_not_retried(self):
        with mock.patch.object(http, "request", side_effect=http.HttpError(400, "bad")) as req:
            with self.assertRaises(LLMError):
                self.llm.generate_json("s", "p", "script")
        self.assertEqual(req.call_count, 1)

    def test_cut_off_output_is_an_error(self):
        with mock.patch.object(http, "request", return_value=reply('{"a": ', stop="max_tokens")):
            with self.assertRaises(LLMError):
                self.llm.generate_json("s", "p", "script")


class MakeLlmTest(unittest.TestCase):
    def cfg(self, provider, anthropic="", gemini=""):
        return mock.Mock(llm_provider=provider, anthropic_api_key=anthropic,
                         claude_model="m", claude_max_tokens=100,
                         gemini_api_key=gemini, gemini_model="g")

    def test_auto_prefers_claude(self):
        self.assertEqual(llm.make_llm(self.cfg("auto", "a", "g")).name, "claude")

    def test_auto_falls_back_to_gemini_then_fake(self):
        self.assertEqual(llm.make_llm(self.cfg("auto", "", "g")).name, "gemini")
        self.assertEqual(llm.make_llm(self.cfg("auto")).name, "fake")

    def test_claude_without_key_stops(self):
        with self.assertRaises(SystemExit):
            llm.make_llm(self.cfg("claude"))


if __name__ == "__main__":
    unittest.main()
