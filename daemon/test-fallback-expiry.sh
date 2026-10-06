#!/bin/bash
# OpenCode holds presence through its idle window, then a one-shot VS Code
# update takes over; both sources expire without heartbeats, and a returning
# OpenCode source wins immediately.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${ROOT}/.test-fallback-expiry"
IPC_DIR="${TEST_DIR}/ipc"
MOCK_LOG="${IPC_DIR}/server.log"
DAEMON_LOG="${TEST_DIR}/daemon.log"
PORT=18379
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

echo "=== 1. OpenCode active wins ==="
put '{"sourceId":"opencode:/x","kind":"opencode","ts":1,"active":true,"state":{"app":"OpenCode","project":"p","model":"Kimi K3","mode":"Thinking","startedAt":1000}}'
sleep 2.5
expect_last_activity 'details=p state=Thinking • Kimi K3' "OpenCode active presence"

echo "=== 2. OpenCode idle, VS Code active -> OpenCode holds as Idle ==="
put '{"sourceId":"opencode:/x","kind":"opencode","ts":2,"active":false,"state":{"app":"OpenCode","project":"p"}}'
put '{"sourceId":"vscode:w1","kind":"vscode","ts":2,"active":true,"state":{"app":"VS Code","project":"p","language":"TypeScript","mode":"Editing","startedAt":2000}}'
sleep 2.5
expect_last_activity 'details=p state=Idle' "OpenCode must hold during its idle window"

echo "=== 3. after the idle window VS Code wins, then both expire ==="
sleep 18
expect_activity_sequence 'details=p state=Thinking • Kimi K3' 'details=p state=Idle' 'details=p state=Editing • TypeScript'
expect_log "${DAEMON_LOG}" 'source expired: kind=vscode' "VS Code source without heartbeats must expire"

echo "=== 4. OpenCode re-active wins immediately ==="
put '{"sourceId":"opencode:/x","kind":"opencode","ts":3,"active":true,"state":{"app":"OpenCode","project":"p","model":"Kimi K3","mode":"Editing","startedAt":3000}}'
sleep 2.5
expect_last_activity 'details=p state=Editing • Kimi K3' "returning OpenCode presence"

echo "PASS: idle hold, VS Code fallback, TTL expiry, OpenCode return"
