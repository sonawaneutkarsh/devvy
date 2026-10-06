#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="${ROOT}/daemon/launchd/com.sonawaneutkarsh.devvy.plist"
[ -f "${PLIST}" ] || { printf 'FAIL: missing %s\n' "${PLIST}" >&2; exit 1; }
grep -q '<string>com.sonawaneutkarsh.devvy</string>' "${PLIST}" ||
  { printf 'FAIL: LaunchAgent label com.sonawaneutkarsh.devvy missing\n' >&2; exit 1; }
for key in RunAtLoad KeepAlive ThrottleInterval StandardOutPath StandardErrorPath; do
  grep -q "<key>${key}</key>" "${PLIST}" || { printf 'FAIL: LaunchAgent key %s missing\n' "${key}" >&2; exit 1; }
done
if grep -R -n 'com\.rich\.discord-presence\|/Downloads/rich' "${ROOT}/install.sh" "${ROOT}/uninstall.sh" "${PLIST}" "${ROOT}/daemon/daemon.mjs"; then
  printf 'FAIL: legacy LaunchAgent label or developer path found (lines above)\n' >&2
  exit 1
fi
printf 'PASS: LaunchAgent identity, restart, logging, and path template\n'
