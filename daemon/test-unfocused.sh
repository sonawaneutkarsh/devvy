#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${ROOT}/.test-unfocused"
IPC_DIR="${TEST_DIR}/ipc"
MOCK_LOG="${IPC_DIR}/server.log"
DAEMON_LOG="${TEST_DIR}/daemon.log"
source "${ROOT}/assertions.sh"
PORT=18383

rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}"

node "${ROOT}/mock-discord.mjs" "${IPC_DIR}" &
MOCK_PID=$!

DISCORD_IPC_DIR="${IPC_DIR}" PRESENCE_PORT=${PORT} \
  node "${ROOT}/daemon.mjs" > "${DAEMON_LOG}" 2>&1 &
DAEMON_PID=$!

OC_PID=""
VS_PID=""
VS2_PID=""

cleanup() {
  [ -n "${DAEMON_PID}" ] && kill "${DAEMON_PID}" 2>/dev/null || true
  [ -n "${MOCK_PID}" ] && kill "${MOCK_PID}" 2>/dev/null || true
  [ -n "${OC_PID}" ] && kill "${OC_PID}" 2>/dev/null || true
  [ -n "${VS_PID}" ] && kill "${VS_PID}" 2>/dev/null || true
  [ -n "${VS2_PID}" ] && kill "${VS2_PID}" 2>/dev/null || true
}
trap cleanup EXIT

wait_for_health "${PORT}"

put() {
  curl -s -X PUT "http://127.0.0.1:${PORT}/state" \
    -H 'content-type: application/json' -d "$1" > /dev/null
}

activity_count() {
  grep -cE 'ACTIVITY (details|cleared)' "${MOCK_LOG}" || true
}



# Unfocused VS Code window with an open editor (new extension contract:
# active=true even while focused=false), heartbeating every 5s.
(
  while true; do
    put '{"sourceId":"vscode:w1","kind":"vscode","ts":'"$(date +%s)"',"active":true,"focused":false,"state":{"app":"VS Code","project":"p","language":"TypeScript","mode":"Editing","startedAt":2000}}'
    sleep 5
  done
) &
VS_PID=$!

echo "=== 1. unfocused VS Code gets presence ==="
sleep 2.5
last_activity | grep -q 'details=p state=Editing' || fail "VS Code presence missing"

echo "=== 2. unfocused VS Code keeps presence past idle hold (12s) ==="
BEFORE=$(activity_count)
sleep 12
AFTER=$(activity_count)
[ "${BEFORE}" -eq "${AFTER}" ] || fail "RPC churn while unfocused (${BEFORE} -> ${AFTER})"
last_activity | grep -q 'details=p state=Editing' || fail "unfocused presence cleared"

echo "=== 3. single IPC client connection ==="
[ "$(grep -c 'client connected' "${MOCK_LOG}")" -eq 1 ] || fail "more than one IPC client"

echo "=== 4. OpenCode active wins immediately ==="
OC_MODE_FILE="${TEST_DIR}/oc-mode"
echo active > "${OC_MODE_FILE}"
(
  while true; do
    ts=$(date +%s)
    mode=$(cat "${OC_MODE_FILE}")
    if [ "${mode}" = "active" ]; then
      put '{"sourceId":"opencode:/x","kind":"opencode","ts":'"${ts}"',"active":true,"state":{"app":"OpenCode","project":"p","model":"Kimi K3","mode":"Thinking","startedAt":1000000}}'
    else
      put '{"sourceId":"opencode:/x","kind":"opencode","ts":'"${ts}"',"active":false,"state":{"app":"OpenCode","project":"p","model":"Kimi K3"}}'
    fi
    sleep 5
  done
) &
OC_PID=$!
sleep 2.5
last_activity | grep -q 'details=p state=Thinking' || fail "OpenCode did not win"

echo "=== 5. OpenCode idle -> VS Code returns after 15s hold ==="
BEFORE=$(activity_count)
echo idle > "${OC_MODE_FILE}"
sleep 24
last_activity | grep -q 'details=p state=Editing' || fail "VS Code did not take over after OpenCode idle"
AFTER=$(activity_count)
[ $((AFTER - BEFORE)) -le 2 ] || fail "excessive updates during idle transition (${BEFORE} -> ${AFTER})"

echo "=== 6. OpenCode re-active wins immediately ==="
echo active > "${OC_MODE_FILE}"
sleep 8
last_activity | grep -q 'details=p state=Thinking' || fail "OpenCode did not re-win"

echo "=== 7. heartbeats stop -> presence clears via TTL ==="
BEFORE=$(activity_count)
kill "${OC_PID}" "${VS_PID}" 2>/dev/null || true
OC_PID=""
VS_PID=""
sleep 24
last_activity | grep -q 'ACTIVITY cleared' || fail "stale presence did not clear"
grep -q 'source expired: kind=opencode' "${DAEMON_LOG}" || fail "opencode source not expired"
grep -q 'source expired: kind=vscode' "${DAEMON_LOG}" || fail "vscode source not expired"
AFTER=$(activity_count)
[ $((AFTER - BEFORE)) -le 2 ] || fail "unexpected update count on expiry (${BEFORE} -> ${AFTER})"

echo "=== 8. multi-window: focused window wins, stays stable when unfocused ==="
W2_MODE_FILE="${TEST_DIR}/w2-mode"
echo focused > "${W2_MODE_FILE}"
(
  while true; do
    mode=$(cat "${W2_MODE_FILE}")
    put '{"sourceId":"vscode:w2","kind":"vscode","ts":'"$(date +%s)"',"active":true,"focused":'"$([ "${mode}" = "focused" ] && echo true || echo false)"',"state":{"app":"VS Code","project":"w2proj","language":"Go","mode":"Editing","startedAt":3000}}'
    sleep 5
  done
) &
VS2_PID=$!
# w1 comes back unfocused (never focused since restart)
(
  while true; do
    put '{"sourceId":"vscode:w1","kind":"vscode","ts":'"$(date +%s)"',"active":true,"focused":false,"state":{"app":"VS Code","project":"p","file":"Hero.tsx","language":"TypeScript","branch":"main","startedAt":2000}}'
    sleep 5
  done
) &
VS_PID=$!
sleep 2.5
last_activity | grep -q 'details=w2proj state=Editing' || fail "focused window did not win"

echo unfocused > "${W2_MODE_FILE}"
BEFORE=$(activity_count)
sleep 12
AFTER=$(activity_count)
[ "${BEFORE}" -eq "${AFTER}" ] || fail "multi-window flip-flop (${BEFORE} -> ${AFTER})"
last_activity | grep -q 'details=w2proj state=Editing' || fail "last focused window lost stability"

echo ""
echo "PASS: unfocused persistence, priority, TTL expiry, multi-window stability"
