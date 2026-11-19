"""Tiny JSON-over-HTTP helper on the standard library (no extra packages)."""

import json
import urllib.error
import urllib.request


class HttpError(Exception):
    def __init__(self, status: int, body: str):
        super().__init__(f"HTTP {status}: {body[:500]}")
        self.status = status
        self.body = body


def raw(method: str, url: str, headers: dict, data: bytes = None,
        content_type: str = None, timeout: int = 120) -> bytes:
    """Send bytes, get bytes back (images, audio, file uploads)."""
    req = urllib.request.Request(url, data=data, method=method)
    for k, v in headers.items():
        req.add_header(k, v)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        raise HttpError(e.code, e.read().decode("utf-8", "replace")) from None


def request(method: str, url: str, headers: dict, body=None, timeout: int = 120):
    data = None if body is None else json.dumps(body).encode("utf-8")
    out = raw(method, url, headers, data,
              "application/json" if data is not None else None, timeout)
    text = out.decode("utf-8")
    return json.loads(text) if text.strip() else None


def download(url: str, timeout: int = 120) -> bytes:
    return raw("GET", url, {}, timeout=timeout)
