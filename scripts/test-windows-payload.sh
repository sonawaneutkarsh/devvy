#!/usr/bin/env bash
set -euo pipefail
ARCHIVE="${1:?usage: $0 ARCHIVE [SHA256_FILE|SHA256]}"
CHECKSUM_SOURCE="${2:-${ARCHIVE}.sha256}"
[ -f "${ARCHIVE}" ]
if [ -f "${CHECKSUM_SOURCE}" ]; then
EXPECTED="$(awk 'NF {print $1; exit}' "${CHECKSUM_SOURCE}")"
else
EXPECTED="${CHECKSUM_SOURCE}"
fi
EXPECTED="$(printf '%s' "${EXPECTED}" | tr '[:upper:]' '[:lower:]')"
[ -n "${EXPECTED}" ]
printf '%s' "${EXPECTED}" | grep -Eq '^[A-Fa-f0-9]{64}$'
ACTUAL="$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
[ "${ACTUAL}" = "${EXPECTED}" ] || { printf 'FAIL: archive checksum mismatch\n' >&2; exit 1; }
LIST="$(unzip -Z1 "${ARCHIVE}")"
for required in devvy/runtime/node.exe devvy/runtime/node.LICENSE devvy/windows/install.ps1 \
  devvy/windows/run-daemon.ps1 devvy/uninstall.ps1 devvy/scripts/vscode-cli.ps1 \
  devvy/daemon/daemon.mjs devvy/devvy-4.0.2.vsix; do
  printf '%s\n' "${LIST}" | grep -Fx "${required}" >/dev/null
done
UNINSTALLER_COUNT="$(printf '%s\n' "${LIST}" | grep -Ec '(^|/)uninstall\.ps1$')"
[ "${UNINSTALLER_COUNT}" -eq 1 ]
! printf '%s\n' "${LIST}" | grep -Fx 'devvy/windows/uninstall.ps1' >/dev/null
! printf '%s\n' "${LIST}" | grep -E '(^|/)(node_modules|\.git|test-|.*\.log)(/|$)' >/dev/null
unzip -p "${ARCHIVE}" devvy/runtime/node.exe | wc -c | tr -d ' ' | awk '$1 > 10000000 {ok=1} END {exit !ok}'
printf 'PASS: Windows payload contains the isolated runtime and required files\n'
