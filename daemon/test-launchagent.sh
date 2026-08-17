#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="${ROOT}/daemon/launchd/com.sonawaneutkarsh.devvy.plist"
[ -f "${PLIST}" ]
grep -q '<string>com.sonawaneutkarsh.devvy</string>' "${PLIST}"
for key in RunAtLoad KeepAlive ThrottleInterval StandardOutPath StandardErrorPath; do
  grep -q "<key>${key}</key>" "${PLIST}"
done
! grep -R -q 'com\.rich\.discord-presence\|/Downloads/rich' "${ROOT}/install.sh" "${ROOT}/uninstall.sh" "${PLIST}" "${ROOT}/daemon/daemon.mjs"
printf 'PASS: V3 LaunchAgent identity, restart, logging, and path template\n'
