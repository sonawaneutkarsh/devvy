#!/usr/bin/env bash
# Validate the Windows payload built by scripts/package-windows-release.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ARCHIVE="${1:?usage: $0 ARCHIVE [SHA256_FILE|SHA256]}"
CHECKSUM_SOURCE="${2:-${ARCHIVE}.sha256}"
VERSION="${DEVVY_VERSION:-$("${ROOT}/scripts/version.sh")}"
fail() { printf 'FAIL: Windows payload %s: %s\n' "${ARCHIVE}" "$*" >&2; exit 1; }
[ -f "${ARCHIVE}" ] || fail "archive not found"
if [ -f "${CHECKSUM_SOURCE}" ]; then
  EXPECTED="$(awk 'NF {print $1; exit}' "${CHECKSUM_SOURCE}")"
else
  EXPECTED="${CHECKSUM_SOURCE}"
fi
EXPECTED="$(printf '%s' "${EXPECTED}" | tr '[:upper:]' '[:lower:]')"
printf '%s' "${EXPECTED}" | grep -Eq '^[a-f0-9]{64}$' || fail "expected checksum '${EXPECTED}' is not a SHA-256"
ACTUAL="$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
[ "${ACTUAL}" = "${EXPECTED}" ] || fail "checksum mismatch: expected ${EXPECTED}, got ${ACTUAL}"
LIST="$(unzip -Z1 "${ARCHIVE}")"
for required in devvy/runtime/node.exe devvy/runtime/node.LICENSE devvy/windows/install.ps1 \
  devvy/windows/run-daemon.ps1 devvy/uninstall.ps1 devvy/scripts/vscode-cli.ps1 \
  devvy/daemon/daemon.mjs "devvy/devvy-${VERSION}.vsix"; do
  printf '%s\n' "${LIST}" | grep -Fx "${required}" >/dev/null || fail "missing ${required}"
done
UNINSTALLER_COUNT="$(printf '%s\n' "${LIST}" | grep -Ec '(^|/)uninstall\.ps1$' || true)"
[ "${UNINSTALLER_COUNT}" -eq 1 ] || fail "expected exactly 1 uninstall.ps1, found ${UNINSTALLER_COUNT}"
if FORBIDDEN="$(printf '%s\n' "${LIST}" | grep -E '(^|/)(node_modules|\.git|test-|.*\.log)(/|$)')"; then
  fail "contains development files:
${FORBIDDEN}"
fi
NODE_SIZE="$(unzip -p "${ARCHIVE}" devvy/runtime/node.exe | wc -c | tr -d ' ')"
[ "${NODE_SIZE}" -gt 10000000 ] || fail "bundled node.exe is only ${NODE_SIZE} bytes"
printf 'PASS: Windows payload contains the isolated runtime and required files\n'
