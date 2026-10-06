#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${ROOT}/.test-assets"
IPC_DIR="${TEST_DIR}/ipc"
MOCK_LOG="${IPC_DIR}/server.log"
DAEMON_LOG="${TEST_DIR}/daemon.log"
source "${ROOT}/assertions.sh"
PORT=18385

rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}"

node "${ROOT}/mock-discord.mjs" "${IPC_DIR}" &
MOCK_PID=$!

# Uses the REAL config.json from the daemon directory (same file launchd uses).
DISCORD_IPC_DIR="${IPC_DIR}" PRESENCE_PORT=${PORT} \
  node "${ROOT}/daemon.mjs" > "${DAEMON_LOG}" 2>&1 &
DAEMON_PID=$!

cleanup() {
  [ -n "${DAEMON_PID}" ] && kill "${DAEMON_PID}" 2>/dev/null || true
  [ -n "${MOCK_PID}" ] && kill "${MOCK_PID}" 2>/dev/null || true
}
trap cleanup EXIT

wait_for_health "${PORT}"

put() {
  curl -s -X PUT "http://127.0.0.1:${PORT}/state" \
    -H 'content-type: application/json' -d "$1" > /dev/null
}


expect_asset() {
  local kind="$1" expected="$2"
  put "$3"
  sleep 2.5
  local line
  line=$(grep 'ACTIVITY_ASSETS' "${MOCK_LOG}" | tail -1 || true)
  [ -n "${line}" ] || fail "${kind}: no assets sent at all"
  echo "${line}" | grep -q "large=${expected} " || fail "${kind}: expected asset key '${expected}', got: ${line}"
  echo "${kind} -> ${line}"
}

echo "=== config assets under test ==="
node -e "const c=require('${ROOT}/config.json'); console.log(JSON.stringify(c.assets))"

expect_asset "vscode"      "vscode"      '{"sourceId":"vscode:w1","kind":"vscode","ts":1,"active":true,"focused":true,"state":{"app":"VS Code","project":"p","file":"f.ts","language":"ts","startedAt":1000}}'
expect_asset "commandcode" "commandcode" '{"sourceId":"commandcode:cc1","kind":"commandcode","ts":2,"active":true,"state":{"app":"Command Code","project":"p","model":"M","activity":"A","startedAt":1000}}'
expect_asset "opencode"    "opencode"    '{"sourceId":"opencode:/x","kind":"opencode","ts":3,"active":true,"state":{"app":"OpenCode","project":"p","model":"M","activity":"A","startedAt":1000}}'

# All three must have produced asset lines (3 total, one per kind).
COUNT=$(grep -c 'ACTIVITY_ASSETS' "${MOCK_LOG}" || true)
[ "${COUNT}" -eq 3 ] || fail "expected 3 ACTIVITY_ASSETS lines, got ${COUNT}"

echo ""
echo "PASS: asset keys opencode/commandcode/vscode present in SET_ACTIVITY payloads"
