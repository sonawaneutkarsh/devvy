#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIR="${ROOT}/.test-presence-privacy"; PORT=18391
MOCK_LOG="${DIR}/ipc/server.log"; DAEMON_LOG="${DIR}/daemon.log"
source "${ROOT}/assertions.sh"
rm -rf "${DIR}"; mkdir -p "${DIR}"
node "${ROOT}/mock-discord.mjs" "${DIR}/ipc" & MOCK=$!
DISCORD_IPC_DIR="${DIR}/ipc" PRESENCE_PORT="${PORT}" node "${ROOT}/daemon.mjs" >"${DIR}/daemon.log" 2>&1 & DAEMON=$!
cleanup() { kill "${DAEMON}" "${MOCK}" 2>/dev/null || true; wait "${DAEMON}" "${MOCK}" 2>/dev/null || true; }
trap cleanup EXIT
wait_for_health "${PORT}"
put() { curl -fsS -X PUT "http://127.0.0.1:${PORT}/state" -H content-type:application/json -d "$1" >/dev/null; }
put '{"sourceId":"opencode:a","kind":"opencode","active":true,"state":{"project":"C:\\Users\\Ada\\Projects\\private-project","model":"zai-org/GLM-5.3","activity":"Editing code","startedAt":1}}'
sleep 2.2
expect_last_activity 'details=private-project state=Editing • GLM 5.3' "normalized mode and model with Windows basename"
expect_log "${MOCK_LOG}" 'ACTIVITY_ASSETS large=opencode' "OpenCode asset key"
# Model identifiers are normalized, while arbitrary prompt-like activity is
# reduced to a safe high-level mode and never reaches the Discord payload.
put '{"sourceId":"opencode:a","kind":"opencode","active":true,"state":{"project":"C:\\Users\\Ada\\Projects\\private-project","model":"deepseek/deepseek-v4-pro","activity":"secret prompt text"}}'
sleep 2.2
expect_last_activity 'details=private-project state=Thinking • DeepSeek V4 Pro' "prompt-like activity reduced to a safe mode"
expect_absent "${MOCK_LOG}" 'secret prompt text' "prompt text reached Discord"
expect_absent "${MOCK_LOG}" 'C:' "Windows drive path reached Discord"
expect_absent "${MOCK_LOG}" 'Ada' "Windows user name reached Discord"
echo "PASS: normalized mode/model, Windows basename privacy, and centralized asset payload"
