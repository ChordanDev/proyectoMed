"""Deterministic OpenAI chat-completions stand-in for the local voice stack (#191).

Answers every `POST /v1/chat/completions` with the same assistant message,
`MOCK_LLM_REPLY`, like the web E2E harness mock (web/src/integration/harness.ts).
Listens on 127.0.0.1 only. Usage: python3 mock_openai.py <port>
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_BODY_BYTES = 64 * 1024


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self._send(200, {"status": "ok"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY_BYTES:
            self._send(413, {"error": {"message": "Payload too large"}})
            return
        self.rfile.read(length)
        if self.path != "/v1/chat/completions":
            self._send(404, {"error": {"message": f"Unexpected path {self.path}"}})
            return
        reply = os.environ.get("MOCK_LLM_REPLY", "")
        self._send(
            200, {"choices": [{"message": {"role": "assistant", "content": reply}}]}
        )

    def _send(self, status: int, body: dict) -> None:
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args):
        pass  # request bodies carry transcript text; log nothing


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
