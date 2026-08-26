#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIR="${ROOT}/.test-v2-presence"; PORT=18391
rm -rf "${DIR}"; mkdir -p "${DIR}"
node "${ROOT}/mock-discord.mjs" "${DIR}/ipc" & MOCK=$!
DISCORD_IPC_DIR="${DIR}/ipc" PRESENCE_PORT="${PORT}" node "${ROOT}/daemon.mjs" >"${DIR}/daemon.log" 2>&1 & DAEMON=$!
cleanup() { kill "${DAEMON}" "${MOCK}" 2>/dev/null || true; wait "${DAEMON}" "${MOCK}" 2>/dev/null || true; }
trap cleanup EXIT
for _ in $(seq 1 30); do curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null && break; sleep .2; done
put() { curl -fsS -X PUT "http://127.0.0.1:${PORT}/state" -H content-type:application/json -d "$1" >/dev/null; }
put '{"sourceId":"opencode:a","kind":"opencode","active":true,"state":{"project":"C:\\Users\\Ada\\Projects\\private-project","model":"zai-org/GLM-5.3","activity":"Editing code","startedAt":1}}'
sleep 2.2
grep -q 'ACTIVITY details=private-project state=Editing • GLM 5.3' "${DIR}/ipc/server.log"
grep -q 'ACTIVITY_ASSETS large=opencode' "${DIR}/ipc/server.log"
# Model identifiers are normalized, while arbitrary prompt-like activity is
# reduced to a safe high-level mode and never reaches the Discord payload.
put '{"sourceId":"opencode:a","kind":"opencode","active":true,"state":{"project":"C:\\Users\\Ada\\Projects\\private-project","model":"deepseek/deepseek-v4-pro","activity":"secret prompt text"}}'
sleep 2.2
grep -q 'ACTIVITY details=private-project state=Thinking • DeepSeek V4 Pro' "${DIR}/ipc/server.log"
! grep -F 'secret prompt text' "${DIR}/ipc/server.log" >/dev/null
! grep -F 'C:\\Users\\Ada\\Projects\\private-project' "${DIR}/ipc/server.log" >/dev/null
echo "PASS: V4 normalized mode/model, Windows basename privacy, and centralized asset payload"
