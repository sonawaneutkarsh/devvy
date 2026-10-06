#!/bin/bash
# Single OpenCode source: active presence, duplicate suppression, idle state,
# and privacy of free-text fields, against a mock Discord IPC server.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${ROOT}/.test-run"
MOCK_LOG="${TEST_DIR}/ipc/server.log"
DAEMON_LOG="${TEST_DIR}/daemon.log"
PORT=18377
source "${ROOT}/assertions.sh"

rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}"

node "${ROOT}/mock-discord.mjs" "${TEST_DIR}/ipc" &
MOCK_PID=$!
DISCORD_IPC_DIR="${TEST_DIR}/ipc" PRESENCE_PORT=${PORT} \
  node "${ROOT}/daemon.mjs" > "${DAEMON_LOG}" 2>&1 &
DAEMON_PID=$!

cleanup() {
  kill "${DAEMON_PID}" "${MOCK_PID}" 2>/dev/null || true
  wait "${DAEMON_PID}" "${MOCK_PID}" 2>/dev/null || true
}
trap cleanup EXIT

wait_for_health "${PORT}"

put() {
  curl -fsS -X PUT "http://127.0.0.1:${PORT}/state" \
    -H 'content-type: application/json' -d "$1" > /dev/null
}

ACTIVE='{"sourceId":"opencode:/test/project","kind":"opencode","ts":1,"active":true,"state":{"app":"OpenCode","project":"rich","model":"Kimi K3","activity":"Implementing auth","file":"auth.ts","startedAt":1000}}'

echo "=== 1. OpenCode active -> presence with project, mode, and model ==="
put "${ACTIVE}"
sleep 0.3
echo "=== 2. identical state again -> no second SET_ACTIVITY ==="
put "${ACTIVE/\"ts\":1/\"ts\":2}"
sleep 2.5
expect_last_activity 'details=rich state=Thinking • Kimi K3' "active OpenCode presence"
expect_log "${MOCK_LOG}" 'ACTIVITY_ASSETS large=opencode' "OpenCode asset key"
expect_count 'ACTIVITY details=rich state=Thinking' "${MOCK_LOG}" 1 "duplicate state must not re-send SET_ACTIVITY"

echo "=== 3. OpenCode idle -> Idle presence ==="
put '{"sourceId":"opencode:/test/project","kind":"opencode","ts":3,"active":false,"state":{"app":"OpenCode","project":"rich"}}'
sleep 2.5
expect_last_activity 'details=rich state=Idle' "idle OpenCode presence"

echo "=== 4. privacy and single IPC client ==="
expect_absent "${MOCK_LOG}" 'Implementing auth' "free-text activity reached Discord"
expect_absent "${MOCK_LOG}" 'auth.ts' "file name reached Discord"
expect_count 'client connected' "${MOCK_LOG}" 1 "exactly one Discord IPC client"

echo "PASS: active presence, duplicate suppression, idle state, privacy"
