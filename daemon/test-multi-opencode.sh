#!/bin/bash
# Two OpenCode sources: the active one wins; when both are idle and no other
# source exists, presence clears after the idle window.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${ROOT}/.test-multi-opencode"
IPC_DIR="${TEST_DIR}/ipc"
MOCK_LOG="${IPC_DIR}/server.log"
DAEMON_LOG="${TEST_DIR}/daemon.log"
PORT=18382
source "${ROOT}/assertions.sh"

rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}"

node "${ROOT}/mock-discord.mjs" "${IPC_DIR}" &
MOCK_PID=$!
DISCORD_IPC_DIR="${IPC_DIR}" PRESENCE_PORT=${PORT} \
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

echo "=== 1. one active, one idle OpenCode source -> active one wins ==="
put '{"sourceId":"opencode:/a","kind":"opencode","ts":1,"active":true,"state":{"app":"OpenCode","project":"a","model":"M1","activity":"A1","startedAt":1000}}'
put '{"sourceId":"opencode:/b","kind":"opencode","ts":1,"active":false,"state":{"app":"OpenCode","project":"b"}}'
sleep 2.5
expect_last_activity 'details=a state=Thinking' "active OpenCode source must win"

echo "=== 2. both idle, no VS Code -> presence clears ==="
put '{"sourceId":"opencode:/a","kind":"opencode","ts":2,"active":false,"state":{"app":"OpenCode","project":"a"}}'
sleep 18
expect_last_activity 'ACTIVITY cleared' "presence must clear when every source is idle and expired"
expect_absent "${MOCK_LOG}" 'details=b state=Thinking' "idle source must never show as active"

echo "PASS: multi-source OpenCode arbitration and clear"
