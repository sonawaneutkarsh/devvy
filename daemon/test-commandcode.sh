#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${ROOT}/.test-commandcode"
IPC_DIR="${TEST_DIR}/ipc"
MOCK_LOG="${IPC_DIR}/server.log"
DAEMON_LOG="${TEST_DIR}/daemon.log"
PORT=18384

rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}"

node "${ROOT}/mock-discord.mjs" "${IPC_DIR}" &
MOCK_PID=$!

DISCORD_IPC_DIR="${IPC_DIR}" PRESENCE_PORT=${PORT} \
  node "${ROOT}/daemon.mjs" > "${DAEMON_LOG}" 2>&1 &
DAEMON_PID=$!

OC_PID=""
CC_PID=""
VS_PID=""

cleanup() {
  [ -n "${DAEMON_PID}" ] && kill "${DAEMON_PID}" 2>/dev/null || true
  [ -n "${MOCK_PID}" ] && kill "${MOCK_PID}" 2>/dev/null || true
  [ -n "${OC_PID}" ] && kill "${OC_PID}" 2>/dev/null || true
  [ -n "${CC_PID}" ] && kill "${CC_PID}" 2>/dev/null || true
  [ -n "${VS_PID}" ] && kill "${VS_PID}" 2>/dev/null || true
}
trap cleanup EXIT

for i in $(seq 1 30); do
  curl -sf "http://127.0.0.1:${PORT}/healthz" > /dev/null && break
  sleep 0.2
done

put() {
  curl -s -X PUT "http://127.0.0.1:${PORT}/state" \
    -H 'content-type: application/json' -d "$1" > /dev/null
}

last_activity() {
  grep -E 'ACTIVITY (details|cleared)' "${MOCK_LOG}" | tail -1
}

activity_count() {
  grep -cE 'ACTIVITY (details|cleared)' "${MOCK_LOG}" || true
}

fail() {
  echo "FAIL: $1"
  echo "--- last activity: $(last_activity)"
  exit 1
}

# VS Code heartbeats continuously (fallback)
(
  while true; do
    put '{"sourceId":"vscode:w1","kind":"vscode","ts":'"$(date +%s)"',"active":true,"focused":false,"state":{"app":"VS Code","project":"p","language":"TypeScript","mode":"Editing","startedAt":2000}}'
    sleep 5
  done
) &
VS_PID=$!

echo "=== 1. VS Code fallback present ==="
sleep 2.5
last_activity | grep -q 'details=p state=Editing' || fail "VS Code fallback missing"

echo "=== 2. Command Code active wins over VS Code ==="
(
  while true; do
    put '{"sourceId":"commandcode:cc1","kind":"commandcode","ts":'"$(date +%s)"',"active":true,"state":{"app":"Command Code","project":"portfolio","model":"claude-sonnet-4-6","mode":"Editing","startedAt":1000000}}'
    sleep 5
  done
) &
CC_PID=$!
sleep 2.5
last_activity | grep -q 'details=portfolio state=Editing' || fail "Command Code did not win over VS Code"

echo "=== 3. OpenCode active immediately beats Command Code ==="
OC_MODE_FILE="${TEST_DIR}/oc-mode"
echo active > "${OC_MODE_FILE}"
(
  while true; do
    ts=$(date +%s)
    mode=$(cat "${OC_MODE_FILE}")
    if [ "${mode}" = "active" ]; then
      put '{"sourceId":"opencode:/x","kind":"opencode","ts":'"${ts}"',"active":true,"state":{"app":"OpenCode","project":"p","model":"Kimi K3","mode":"Thinking","startedAt":2000000}}'
    else
      put '{"sourceId":"opencode:/x","kind":"opencode","ts":'"${ts}"',"active":false,"state":{"app":"OpenCode","project":"p","model":"Kimi K3"}}'
    fi
    sleep 5
  done
) &
OC_PID=$!
sleep 2.5
last_activity | grep -q 'details=p state=Thinking' || fail "OpenCode did not beat Command Code"

echo "=== 4. OpenCode idle -> Command Code takes over (after 15s hold) ==="
BEFORE=$(activity_count)
echo idle > "${OC_MODE_FILE}"
sleep 24
last_activity | grep -q 'details=portfolio state=Editing' || fail "Command Code did not take over after OpenCode idle"
AFTER=$(activity_count)
[ $((AFTER - BEFORE)) -le 2 ] || fail "excessive updates during priority transition"

echo "=== 5. Command Code idle -> VS Code returns ==="
BEFORE=$(activity_count)
kill "${CC_PID}" 2>/dev/null || true
CC_PID=""
# idle Command Code keeps heartbeating
(
  while true; do
    put '{"sourceId":"commandcode:cc1","kind":"commandcode","ts":'"$(date +%s)"',"active":false,"state":{"app":"Command Code","project":"portfolio"}}'
    sleep 5
  done
) &
CC_PID=$!
sleep 24
last_activity | grep -q 'details=p state=Editing' || fail "VS Code did not return after Command Code idle"

echo "=== 6. heartbeats stop -> sources expire, presence clears ==="
BEFORE=$(activity_count)
kill "${CC_PID}" "${VS_PID}" 2>/dev/null || true
CC_PID=""
VS_PID=""
sleep 24
last_activity | grep -q 'ACTIVITY cleared' || fail "stale presence did not clear"
grep -q 'source expired: kind=commandcode' "${DAEMON_LOG}" || fail "commandcode source not expired"
grep -q 'source expired: kind=vscode' "${DAEMON_LOG}" || fail "vscode source not expired"
AFTER=$(activity_count)
[ $((AFTER - BEFORE)) -le 2 ] || fail "unexpected update count on expiry"

echo "=== 7. single IPC client connection ==="
[ "$(grep -c 'client connected' "${MOCK_LOG}")" -eq 1 ] || fail "more than one IPC client"

echo ""
echo "PASS: OpenCode > Command Code > VS Code priority, idle fallback, TTL expiry"
