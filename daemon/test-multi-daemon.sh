#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${ROOT}/.test-multi-daemon"
IPC_DIR="${TEST_DIR}/ipc"
MOCK_LOG="${IPC_DIR}/server.log"
DAEMON_LOG="${TEST_DIR}/daemon.log"

rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}"

node "${ROOT}/mock-discord.mjs" "${IPC_DIR}" &
MOCK_PID=$!

DISCORD_IPC_DIR="${IPC_DIR}" PRESENCE_PORT=18382 \
  node "${ROOT}/daemon.mjs" > "${DAEMON_LOG}" 2>&1 &
DAEMON_PID=$!

cleanup() {
  kill "${DAEMON_PID}" "${MOCK_PID}" 2>/dev/null || true
  wait "${DAEMON_PID}" "${MOCK_PID}" 2>/dev/null || true
}
trap cleanup EXIT

for i in $(seq 1 30); do
  curl -sf http://127.0.0.1:18382/healthz > /dev/null && break
  sleep 0.2
done

put() {
  curl -s -X PUT http://127.0.0.1:18382/state \
    -H 'content-type: application/json' -d "$1" > /dev/null
}

# two opencode sources, one active one idle
put '{"sourceId":"opencode:/a","kind":"opencode","ts":1,"active":true,"state":{"app":"OpenCode","project":"a","model":"M1","activity":"A1","startedAt":1000}}'
put '{"sourceId":"opencode:/b","kind":"opencode","ts":1,"active":false,"state":{"app":"OpenCode","project":"b"}}'
sleep 2.5

echo "=== both opencode: active one should win ==="
grep -E 'ACTIVITY details' "${MOCK_LOG}" | tail -1

# idle the active one; other was already idle
put '{"sourceId":"opencode:/a","kind":"opencode","ts":2,"active":false,"state":{"app":"OpenCode","project":"a"}}'
sleep 18

echo "=== after both opencode idle, should clear (no VS Code) ==="
grep -E 'ACTIVITY (details|cleared)' "${MOCK_LOG}" | tail -1

echo "=== daemon log ==="
cat "${DAEMON_LOG}"
