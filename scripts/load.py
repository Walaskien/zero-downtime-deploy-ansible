"""Hit the load balancer in a loop and count what fails.

Runs until --stop-file exists, or for --requests requests per worker.
Exit code is 1 if any request failed.
"""
import argparse
import json
import os
import sys
import threading
import time
import urllib.request
from collections import Counter


def worker(url, interval, stop, limit, stats, lock):
    sent = 0
    while not stop() and (limit is None or sent < limit):
        sent += 1
        try:
            with urllib.request.urlopen(url, timeout=3) as resp:
                version = json.loads(resp.read().decode())["version"]
            outcome = ("ok", version)
        except Exception as exc:
            # keep the message short so identical failures group together
            outcome = ("failed", type(exc).__name__ + ": " + str(exc)[:50])
        with lock:
            stats[outcome[0]][outcome[1]] += 1
        time.sleep(interval)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:18080/")
    ap.add_argument("--stop-file")
    ap.add_argument("--requests", type=int, help="per worker, instead of --stop-file")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--interval", type=float, default=0.02)
    args = ap.parse_args()
    if not args.stop_file and not args.requests:
        ap.error("need --stop-file or --requests")

    stats = {"ok": Counter(), "failed": Counter()}
    lock = threading.Lock()
    stop = (lambda: os.path.exists(args.stop_file)) if args.stop_file else (lambda: False)
    threads = [
        threading.Thread(target=worker, args=(args.url, args.interval, stop, args.requests, stats, lock))
        for _ in range(args.workers)
    ]
    started = time.time()
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    ok = sum(stats["ok"].values())
    failed = sum(stats["failed"].values())
    print("requests=%d ok=%d failed=%d duration=%.1fs" % (ok + failed, ok, failed, time.time() - started))
    print("versions: " + " ".join("%s=%d" % kv for kv in sorted(stats["ok"].items())))
    for msg, n in stats["failed"].most_common():
        print("  %dx %s" % (n, msg))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
