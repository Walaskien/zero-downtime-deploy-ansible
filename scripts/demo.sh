#!/usr/bin/env bash
# Runs the whole scenario against local containers. CI runs this same script.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
logs="$root/.state/logs"

# Colima does not create /var/run/docker.sock
if [ -z "${DOCKER_HOST:-}" ] && [ ! -S /var/run/docker.sock ] && [ -S "$HOME/.colima/default/docker.sock" ]; then
  export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
fi

die() { echo "FAIL: $*" >&2; exit 1; }

# Old images have to go too: the build is skipped when the tag already exists
clean() {
  docker rm -f zdd-app1 zdd-app2 zdd-app3 zdd-lb >/dev/null 2>&1 || true
  docker network rm zdd >/dev/null 2>&1 || true
  for img in $(docker image ls --format '{{.Repository}}:{{.Tag}}' zdd-app); do
    docker rmi "$img" >/dev/null
  done
  rm -rf "$root/.state"
}

if [ "${1:-}" = clean ]; then
  clean
  exit 0
fi

clean
mkdir -p "$logs"
cd "$root/ansible"

# play <name> <ansible-playbook args...>, full output goes to .state/logs/<name>.txt
play() {
  local name=$1
  shift
  ansible-playbook "$@" >"$logs/$name.txt" 2>&1
}

recap() { grep -A1 'PLAY RECAP' "$logs/$1.txt" | tail -1 | tr -s ' '; }

# Access log lines where a request was tried on more than one instance. nginx retries
# on connection errors, so a client can see zero failures even when the pool
# update was wrong. This count shows whether the retry was ever needed.
retried() { docker logs zdd-lb 2>&1 | grep -cE '^[0-9]{3} [^ ]+, ' || true; }

# under_load <name> <command...>: requests keep coming while the command runs.
# Sets deploy_rc, load_rc and retries.
under_load() {
  local name=$1
  shift
  local stop="$logs/$name.stop"
  rm -f "$stop"
  python3 "$root/scripts/load.py" --stop-file "$stop" >"$logs/$name.load.txt" &
  local pid=$!
  sleep 1
  retries_before=$(retried)
  deploy_rc=0
  "$@" || deploy_rc=$?
  retries=$(($(retried) - retries_before))
  sleep 1
  touch "$stop"
  load_rc=0
  wait "$pid" || load_rc=$?
  cat "$logs/$name.load.txt"
  echo "  nginx retried on another instance: $retries requests"
}

# every answer through the balancer must come from this version
serving() {
  python3 "$root/scripts/load.py" --requests 10 | grep -qx "versions: $1=40" || die "balancer is not serving only $1"
}

images() { docker inspect -f '{{.Config.Image}}' zdd-app1 zdd-app2 zdd-app3 | sort -u | paste -sd, -; }

echo "== 1. first deploy of v1"
play first deploy.yml -e app_version=v1 || die "first deploy failed, see $logs/first.txt"
recap first
serving v1

echo "== 2. same release again, nothing should change"
play again deploy.yml -e app_version=v1 || die "second run failed"
recap again
recap again | grep -q 'changed=0 ' || die "second run changed something"

echo "== 3. rolling deploy v1 -> v2 under load"
under_load rolling play rolling deploy.yml -e app_version=v2
[ "$deploy_rc" = 0 ] || die "rolling deploy failed, see $logs/rolling.txt"
recap rolling
[ "$load_rc" = 0 ] || die "requests failed during the rolling deploy"
[ "$retries" = 0 ] || die "nginx still sent requests to an instance that was being replaced"
serving v2

echo "== 4. naive deploy v2 -> v3 under load (control, failures expected)"
under_load naive play naive deploy_naive.yml -e app_version=v3
[ "$deploy_rc" = 0 ] || die "naive deploy failed, see $logs/naive.txt"
[ "$load_rc" != 0 ] || die "naive deploy dropped nothing, the control case shows nothing"
serving v3

echo "== 5. v4 never gets healthy on any instance"
under_load broken_all play broken_all deploy.yml -e app_version=v4 -e health_retries=6 \
  -e '{"broken_on": ["app1", "app2", "app3"]}'
[ "$deploy_rc" != 0 ] || die "broken release was accepted"
grep -o 'rolled back, failed task: [^"]*' "$logs/broken_all.txt" | head -1
recap broken_all
[ "$load_rc" = 0 ] || die "requests failed during the rollback"
[ "$retries" = 0 ] || die "nginx still sent requests to an instance that was being replaced"
[ "$(images)" = zdd-app:v3 ] || die "instances are not back on v3: $(images)"
serving v3

echo "== 6. v4 is fine on app1 but broken on app2"
under_load broken_second play broken_second deploy.yml -e app_version=v4 -e health_retries=6 \
  -e '{"broken_on": ["app2"]}'
[ "$deploy_rc" != 0 ] || die "broken release was accepted"
grep -o 'rolled back, failed task: [^"]*' "$logs/broken_second.txt" | head -1
recap broken_second
[ "$load_rc" = 0 ] || die "requests failed during the rollback"
[ "$retries" = 0 ] || die "nginx still sent requests to an instance that was being replaced"
grep -q 'v4=' "$logs/broken_second.load.txt" || die "app1 never served v4, the scenario did not test what it should"
[ "$(images)" = zdd-app:v3 ] || die "instances are not back on v3: $(images)"
serving v3

echo "== all checks passed"
