"""Send requests in a loop until a stop file appears; report failures and versions seen.

Exit code 1 if any request failed, so a deploy that drops requests fails the check.
"""
import argparse
import json
import os
import sys
import time
import urllib.request
from collections import Counter


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--url", default="http://127.0.0.1:8080/")
    p.add_argument("--stop-file", required=True)
    p.add_argument("--interval", type=float, default=0.02)
    a = p.parse_args()

    ok, failed, versions, errors = 0, 0, Counter(), Counter()
    while not os.path.exists(a.stop_file):
        try:
            with urllib.request.urlopen(a.url, timeout=3) as resp:
                versions[json.loads(resp.read().decode())["version"]] += 1
                ok += 1
        except Exception as exc:
            failed += 1
            errors[type(exc).__name__ + ": " + str(exc)[:60]] += 1
        time.sleep(a.interval)

    print("requests=%d ok=%d failed=%d" % (ok + failed, ok, failed))
    print("versions seen: %s" % dict(versions))
    for msg, n in errors.items():
        print("  %dx %s" % (n, msg))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
