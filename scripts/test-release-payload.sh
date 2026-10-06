#!/usr/bin/env bash
# Validate a macOS release payload built by scripts/package-release.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ARCH="${1:?usage: $0 ARCH ARCHIVE}"
ARCHIVE="${2:?usage: $0 ARCH ARCHIVE}"
VERSION="${DEVVY_VERSION:-$("${ROOT}/scripts/version.sh")}"
fail() { printf 'FAIL: %s payload %s: %s\n' "${ARCH}" "${ARCHIVE}" "$*" >&2; exit 1; }
case "${ARCH}" in
  arm64|x86_64) ;;
  *) printf 'unsupported architecture: %s\n' "${ARCH}" >&2; exit 1;;
esac
[ -f "${ARCHIVE}" ] || fail "archive not found"
LIST="$(tar -tzf "${ARCHIVE}")"
for required in \
  "devvy/runtime/node" \
  "devvy/runtime/node.LICENSE" \
  "devvy/scripts/vscode-cli.sh" \
  "devvy/daemon/daemon.mjs" \
  "devvy/daemon/config.json" \
  "devvy/daemon/launchd/com.sonawaneutkarsh.devvy.plist" \
  "devvy/devvy-${VERSION}.vsix" \
  "devvy/uninstall.sh"; do
  printf '%s\n' "${LIST}" | grep -Fx "${required}" >/dev/null || fail "missing ${required}"
done
if FORBIDDEN="$(printf '%s\n' "${LIST}" | grep -E '(^|/)(node_modules|\.git|test-|.*\.log|.*\.sock)(/|$)')"; then
  fail "contains development files:
${FORBIDDEN}"
fi
RUNTIME_SIZE="$(tar -xOf "${ARCHIVE}" devvy/runtime/node | wc -c | tr -d ' ')"
[ "${RUNTIME_SIZE}" -gt 100000000 ] || fail "bundled Node runtime is only ${RUNTIME_SIZE} bytes"
printf 'PASS: %s release payload contains the isolated runtime and required files\n' "${ARCH}"
