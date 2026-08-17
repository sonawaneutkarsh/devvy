#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${ROOT}/.test-fallback"
IPC_DIR="${TEST_DIR}/ipc"
MOCK_LOG="${IPC_DIR}/server.log"
DAEMON_LOG="${TEST_DIR}/daemon.log"

rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}"

node "${ROOT}/mock-discord.mjs" "${IPC_DIR}" &
MOCK_PID=$!

DISCORD_IPC_DIR="${IPC_DIR}" PRESENCE_PORT=18379 \
  node "${ROOT}/daemon.mjs" > "${DAEMON_LOG}" 2>&1 &
DAEMON_PID=$!

cleanup() {
  kill "${DAEMON_PID}" "${MOCK_PID}" 2>/dev/null || true
  wait "${DAEMON_PID}" "${MOCK_PID}" 2>/dev/null || true
}
trap cleanup EXIT

for i in $(seq 1 30); do
  curl -sf http://127.0.0.1:18379/healthz > /dev/null && break
  sleep 0.2
done

put() {
  curl -s -X PUT http://127.0.0.1:18379/state \
    -H 'content-type: application/json' \
    -d "$1" > /dev/null
}

echo "=== 1. OpenCode active (wins) ==="
put '{"sourceId":"opencode:/x","kind":"opencode","ts":1,"active":true,"state":{"app":"OpenCode","project":"p","model":"Kimi K3","mode":"Thinking","startedAt":1000}}'
sleep 2.5

echo "=== 2. OpenCode idle, VS Code active (OpenCode holds) ==="
put '{"sourceId":"opencode:/x","kind":"opencode","ts":2,"active":false,"state":{"app":"OpenCode","project":"p"}}'
put '{"sourceId":"vscode:w1","kind":"vscode","ts":2,"active":true,"state":{"app":"VS Code","project":"p","language":"TypeScript","mode":"Editing","startedAt":2000}}'
sleep 2.5

echo "=== 3. After OpenCode idle timeout, VS Code should win ==="
sleep 18

echo "=== 4. OpenCode re-active (should switch back immediately) ==="
put '{"sourceId":"opencode:/x","kind":"opencode","ts":3,"active":true,"state":{"app":"OpenCode","project":"p","model":"Kimi K3","mode":"Editing","startedAt":3000}}'
sleep 2.5

echo "=== server log ==="
cat "${MOCK_LOG}"

echo "=== daemon log ==="
cat "${DAEMON_LOG}"
