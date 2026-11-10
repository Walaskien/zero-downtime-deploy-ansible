#!/usr/bin/env bash
# Full scenario, also run by CI: first deploy, idempotent re-run, rolling upgrade under load, failed release with rollback.
set -euo pipefail
cd "$(dirname "$0")/../ansible"
PB="ansible-playbook deploy.yml"
LB=http://127.0.0.1:8080/

version() { curl -fsS "$LB" | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])'; }

echo "== 1. first deploy of v1"
$PB -e app_version=v1 | tail -3
[ "$(version)" = v1 ] || { echo "expected v1"; exit 1; }

echo "== 2. same release again must change nothing"
out="$($PB -e app_version=v1)"; echo "$out" | tail -3
echo "$out" | grep -Eq 'changed=0 .*failed=0' || { echo "NOT IDEMPOTENT"; exit 1; }

echo "== 3. rolling upgrade to v2 while requests keep coming"
stop="$(mktemp -u)"
python3 ../scripts/load.py --stop-file "$stop" > /tmp/zdd-load.txt &
load=$!
sleep 1
$PB -e app_version=v2 | tail -3
sleep 1; touch "$stop"
wait $load && rc=0 || rc=$?
cat /tmp/zdd-load.txt
[ "$rc" = 0 ] || { echo "REQUESTS WERE DROPPED"; exit 1; }
[ "$(version)" = v2 ] || { echo "expected v2"; exit 1; }

echo "== 4. broken release v3 must roll back and leave v2 serving"
if $PB -e app_version=v3 -e app_broken=true -e health_retries=6 >/tmp/zdd-v3.txt 2>&1; then
  echo "broken release was accepted"; exit 1
fi
grep -E 'did not become healthy' /tmp/zdd-v3.txt | head -1
for i in 1 2 3 4 5 6; do [ "$(version)" = v2 ] || { echo "traffic not on v2"; exit 1; }; done
echo "OK: v2 still serving after the failed v3 rollout"
