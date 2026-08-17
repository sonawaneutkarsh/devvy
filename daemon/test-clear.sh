#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${ROOT}/.test-clear"
IPC_DIR="${TEST_DIR}/ipc"
MOCK_LOG="${IPC_DIR}/server.log"
DAEMON_LOG="${TEST_DIR}/daemon.log"

rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}"

node "${ROOT}/mock-discord.mjs" "${IPC_DIR}" &
MOCK_PID=$!

DISCORD_IPC_DIR="${IPC_DIR}" PRESENCE_PORT=18381 \
  node "${ROOT}/daemon.mjs" > "${DAEMON_LOG}" 2>&1 &
DAEMON_PID=$!

cleanup() {
  kill "${DAEMON_PID}" "${MOCK_PID}" "${OC_PID:-}" "${VS_PID:-}" 2>/dev/null || true
  wait "${DAEMON_PID}" "${MOCK_PID}" "${OC_PID:-}" "${VS_PID:-}" 2>/dev/null || true
}
trap cleanup EXIT

for i in $(seq 1 30); do
  curl -sf http://127.0.0.1:18381/healthz > /dev/null && break
  sleep 0.2
done

put() {
  curl -s -X PUT http://127.0.0.1:18381/state \
    -H 'content-type: application/json' -d "$1" > /dev/null
}

# both active initially
put '{"sourceId":"opencode:/x","kind":"opencode","ts":1,"active":true,"state":{"app":"OpenCode","project":"p","model":"M","activity":"A","file":"f","startedAt":1000}}'
put '{"sourceId":"vscode:w1","kind":"vscode","ts":1,"active":true,"state":{"app":"VS Code","project":"p","file":"h.ts","language":"ts","branch":"main","startedAt":2000}}'
sleep 2.5

# both go inactive but keep heartbeating
(
  while true; do
    put '{"sourceId":"opencode:/x","kind":"opencode","ts":'"$(date +%s)"',"active":false,"state":{"app":"OpenCode","project":"p"}}'
    sleep 5
  done
) &
OC_PID=$!

(
  while true; do
    put '{"sourceId":"vscode:w1","kind":"vscode","ts":'"$(date +%s)"',"active":false,"state":{"app":"VS Code"}}'
    sleep 5
  done
) &
VS_PID=$!

echo "=== wait for idle holds to expire ==="
sleep 20

echo "=== server log ==="
cat "${MOCK_LOG}"

echo "=== daemon log ==="
cat "${DAEMON_LOG}"
