"""Tiny HTTP service used as the deployment target.

STARTUP_DELAY keeps /health failing for a while after start, so the deploy's
health wait has something to wait for. BROKEN=1 makes a release that never
becomes healthy, to exercise the rollback.
"""
import json
import os
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

START = time.time()
VERSION = os.environ.get("APP_VERSION", "dev")
DELAY = float(os.environ.get("STARTUP_DELAY", "0"))
BROKEN = os.environ.get("BROKEN") == "1"


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            healthy = not BROKEN and time.time() - START >= DELAY
            self._send(200 if healthy else 503, json.dumps({"healthy": healthy}))
        else:
            self._send(200, json.dumps({"version": VERSION, "host": socket.gethostname()}))

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
