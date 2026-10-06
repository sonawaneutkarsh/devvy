#!/bin/bash
# With a heartbeating VS Code source: OpenCode wins, holds through its idle
# window, hands over to VS Code, and wins again when it becomes active.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${ROOT}/.test-fallback-heartbeat"
IPC_DIR="${TEST_DIR}/ipc"
MOCK_LOG="${IPC_DIR}/server.log"
DAEMON_LOG="${TEST_DIR}/daemon.log"
PORT=18380
source "${ROOT}/assertions.sh"

rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}"

node "${ROOT}/mock-discord.mjs" "${IPC_DIR}" &
MOCK_PID=$!
DISCORD_IPC_DIR="${IPC_DIR}" PRESENCE_PORT=${PORT} \
  node "${ROOT}/daemon.mjs" > "${DAEMON_LOG}" 2>&1 &
DAEMON_PID=$!
VSC_HEARTBEAT_PID=""

cleanup() {
  kill "${DAEMON_PID}" "${MOCK_PID}" ${VSC_HEARTBEAT_PID} 2>/dev/null || true
  wait "${DAEMON_PID}" "${MOCK_PID}" ${VSC_HEARTBEAT_PID} 2>/dev/null || true
}
trap cleanup EXIT

wait_for_health "${PORT}"

put() {
  curl -fsS -X PUT "http://127.0.0.1:${PORT}/state" \
    -H 'content-type: application/json' -d "$1" > /dev/null
}

# VS Code heartbeat every 5s (stays alive and active).
(
  while true; do
    put '{"sourceId":"vscode:w1","kind":"vscode","ts":'"$(date +%s)"',"active":true,"state":{"app":"VS Code","project":"p","file":"Hero.tsx","language":"TypeScript","branch":"main","startedAt":2000}}' || true
    sleep 5
  done
) &
VSC_HEARTBEAT_PID=$!

echo "=== 1. OpenCode active wins over VS Code ==="
put '{"sourceId":"opencode:/x","kind":"opencode","ts":1,"active":true,"state":{"app":"OpenCode","project":"p","model":"Kimi K3","activity":"Implementing auth","file":"auth.ts","startedAt":1000}}'
sleep 2.5
expect_last_activity 'details=p state=Thinking • Kimi K3' "OpenCode must win over VS Code"

echo "=== 2. OpenCode idle -> holds as Idle ==="
put '{"sourceId":"opencode:/x","kind":"opencode","ts":2,"active":false,"state":{"app":"OpenCode","project":"p"}}'
sleep 2.5
expect_last_activity 'details=p state=Idle' "OpenCode must hold during its idle window"

echo "=== 3. after the idle window -> VS Code wins ==="
sleep 18
expect_last_activity 'details=p state=Editing • TypeScript' "heartbeating VS Code must take over"

echo "=== 4. OpenCode re-active -> wins immediately ==="
put '{"sourceId":"opencode:/x","kind":"opencode","ts":3,"active":true,"state":{"app":"OpenCode","project":"p","model":"Kimi K3","activity":"Refactoring","file":"auth.ts","startedAt":3000}}'
sleep 2.5
expect_last_activity 'details=p state=Thinking • Kimi K3' "returning OpenCode must win"

for secret in 'Implementing auth' 'Refactoring' 'auth.ts' 'Hero.tsx'; do
  expect_absent "${MOCK_LOG}" "${secret}" "private text reached Discord"
done

echo "PASS: OpenCode priority, idle hold, heartbeating VS Code fallback, privacy"
