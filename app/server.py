"""Small HTTP service used as the deploy target.

STARTUP_DELAY: seconds to wait before listening, like a service that warms up.
BROKEN=1: /health answers 503, to simulate a release that never gets healthy.
"""
import json
import os
import signal
import socket
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = os.environ.get("APP_VERSION", "dev")
STARTUP_DELAY = float(os.environ.get("STARTUP_DELAY", "0"))
BROKEN = os.environ.get("BROKEN") == "1"


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            if BROKEN:
                self.reply(503, {"status": "broken"})
            else:
                self.reply(200, {"status": "ok"})
        else:
            self.reply(200, {"version": VERSION, "host": socket.gethostname()})

    def log_message(self, *args):
        pass  # one line per request would bury the deploy output


if __name__ == "__main__":
    # As PID 1 the process ignores SIGTERM unless it has a handler, and
    # docker stop would sit through its 10 second timeout before SIGKILL.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    time.sleep(STARTUP_DELAY)
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
