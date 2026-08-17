#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${ROOT}/.test-run"
MOCK_LOG="${TEST_DIR}/ipc/server.log"
DAEMON_LOG="${TEST_DIR}/daemon.log"

rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}"

# 1. Start mock Discord on isolated IPC dir
node "${ROOT}/mock-discord.mjs" "${TEST_DIR}/ipc" &
MOCK_PID=$!

# 2. Start daemon pointed at mock + isolated port
DISCORD_IPC_DIR="${TEST_DIR}/ipc" PRESENCE_PORT=18377 \
  node "${ROOT}/daemon.mjs" > "${DAEMON_LOG}" 2>&1 &
DAEMON_PID=$!

cleanup() {
  kill "${DAEMON_PID}" "${MOCK_PID}" 2>/dev/null || true
  wait "${DAEMON_PID}" "${MOCK_PID}" 2>/dev/null || true
}
trap cleanup EXIT

# wait for daemon health
for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:18377/healthz > /dev/null; then
    break
  fi
  sleep 0.2
done

echo "=== health ==="
curl -s http://127.0.0.1:18377/healthz; echo

echo "=== opencode active ==="
curl -s -X PUT http://127.0.0.1:18377/state \
  -H 'content-type: application/json' \
  -d '{"sourceId":"opencode:/test/project","kind":"opencode","ts":1,"active":true,"state":{"app":"OpenCode","project":"rich","model":"Kimi K3","activity":"Implementing auth","file":"auth.ts","startedAt":1000}}'; echo

sleep 0.3

echo "=== duplicate same state (should not re-SET) ==="
curl -s -X PUT http://127.0.0.1:18377/state \
  -H 'content-type: application/json' \
  -d '{"sourceId":"opencode:/test/project","kind":"opencode","ts":2,"active":true,"state":{"app":"OpenCode","project":"rich","model":"Kimi K3","activity":"Implementing auth","file":"auth.ts","startedAt":1000}}' > /dev/null
sleep 2.5

echo "=== opencode idle -> clear ==="
curl -s -X PUT http://127.0.0.1:18377/state \
  -H 'content-type: application/json' \
  -d '{"sourceId":"opencode:/test/project","kind":"opencode","ts":3,"active":false,"state":{"app":"OpenCode","project":"rich"}}' > /dev/null
sleep 2.5

echo "=== server log ==="
cat "${MOCK_LOG}"

echo "=== daemon log ==="
cat "${DAEMON_LOG}"
