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
put '{"sourceId":"opencode:a","kind":"opencode","active":true,"state":{"model":"zai-org/GLM-5.3","activity":"Editing code","startedAt":1}}'
sleep 2.2
grep -q 'ACTIVITY details=GLM 5.3 state=Editing code' "${DIR}/ipc/server.log"
grep -q 'ACTIVITY_ASSETS large=opencode' "${DIR}/ipc/server.log"
# An unsupported input is treated as a safe generic state, not shown verbatim.
put '{"sourceId":"opencode:a","kind":"opencode","active":true,"state":{"model":"deepseek/deepseek-v4-pro","activity":"secret prompt text"}}'
sleep 2.2
grep -q 'ACTIVITY details=DeepSeek V4 Pro state=Thinking...' "${DIR}/ipc/server.log"
echo "PASS: V2 labels, normalized model, and centralized asset payload"
