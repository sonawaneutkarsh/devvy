#!/bin/bash
# Discord restarts: the daemon reconnects and re-sends the current presence.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${ROOT}/.test-reconnect"
IPC_DIR="${TEST_DIR}/ipc"
MOCK_LOG="${IPC_DIR}/server.log"
DAEMON_LOG="${TEST_DIR}/daemon.log"
PORT=18378
source "${ROOT}/assertions.sh"

rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}"

MOCK_PID=""
DAEMON_PID=""

cleanup() {
  [ -z "${DAEMON_PID}" ] || kill "${DAEMON_PID}" 2>/dev/null || true
  [ -z "${MOCK_PID}" ] || kill "${MOCK_PID}" 2>/dev/null || true
  sleep 0.2
}
trap cleanup EXIT

start_mock() {
  node "${ROOT}/mock-discord.mjs" "${IPC_DIR}" &
  MOCK_PID=$!
  sleep 0.3
}

start_mock
DISCORD_IPC_DIR="${IPC_DIR}" PRESENCE_PORT=${PORT} \
  node "${ROOT}/daemon.mjs" > "${DAEMON_LOG}" 2>&1 &
DAEMON_PID=$!

wait_for_health "${PORT}"

echo "=== 1. set presence while Discord is up ==="
curl -fsS -X PUT "http://127.0.0.1:${PORT}/state" \
  -H 'content-type: application/json' \
  -d '{"sourceId":"opencode:/x","kind":"opencode","ts":1,"active":true,"state":{"app":"OpenCode","project":"p","model":"M","activity":"A","file":"f","startedAt":1000}}' > /dev/null
sleep 2.5
expect_count 'ACTIVITY details=p state=Thinking' "${MOCK_LOG}" 1 "presence before restart"

echo "=== 2. kill and restart Discord ==="
kill "${MOCK_PID}" 2>/dev/null || true
wait "${MOCK_PID}" 2>/dev/null || true
MOCK_PID=""
sleep 0.5
start_mock
sleep 3

echo "=== 3. daemon reconnected and restored presence ==="
expect_log "${DAEMON_LOG}" 'reconnecting in' "daemon must schedule a reconnect"
expect_count 'client connected' "${MOCK_LOG}" 2 "daemon must reconnect exactly once"
expect_count 'ACTIVITY details=p state=Thinking' "${MOCK_LOG}" 2 "presence must be re-sent after reconnect"

echo "PASS: Discord restart, reconnect, and presence restore"
