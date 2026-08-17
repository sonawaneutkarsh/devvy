#!/bin/bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${ROOT}/.test-reconnect"
IPC_DIR="${TEST_DIR}/ipc"
MOCK_LOG="${IPC_DIR}/server.log"
DAEMON_LOG="${TEST_DIR}/daemon.log"

rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}"

MOCK_PID=""
DAEMON_PID=""

cleanup() {
  [ -n "${DAEMON_PID}" ] && kill "${DAEMON_PID}" 2>/dev/null || true
  [ -n "${MOCK_PID}" ] && kill "${MOCK_PID}" 2>/dev/null || true
  sleep 0.2
}
trap cleanup EXIT

start_mock() {
  node "${ROOT}/mock-discord.mjs" "${IPC_DIR}" &
  MOCK_PID=$!
  sleep 0.3
}

start_mock

DISCORD_IPC_DIR="${IPC_DIR}" PRESENCE_PORT=18378 \
  node "${ROOT}/daemon.mjs" > "${DAEMON_LOG}" 2>&1 &
DAEMON_PID=$!

for i in $(seq 1 30); do
  curl -sf http://127.0.0.1:18378/healthz > /dev/null && break
  sleep 0.2
done

echo "=== set presence while Discord up ==="
curl -s -X PUT http://127.0.0.1:18378/state \
  -H 'content-type: application/json' \
  -d '{"sourceId":"opencode:/x","kind":"opencode","ts":1,"active":true,"state":{"app":"OpenCode","project":"p","model":"M","activity":"A","file":"f","startedAt":1000}}' > /dev/null
sleep 2.5

echo "=== kill Discord ==="
kill "${MOCK_PID}" 2>/dev/null || true
MOCK_PID=""
sleep 0.5

echo "=== restart Discord ==="
start_mock
sleep 3

echo "=== server log ==="
cat "${MOCK_LOG}"

echo "=== daemon log ==="
cat "${DAEMON_LOG}"
