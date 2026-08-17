#!/usr/bin/env bash
set -euo pipefail
ARCH="${1:?usage: $0 ARCH ARCHIVE}"
ARCHIVE="${2:?usage: $0 ARCH ARCHIVE}"
case "${ARCH}" in
  arm64|x86_64) ;;
  *) printf 'unsupported architecture: %s\n' "${ARCH}" >&2; exit 1;;
esac
[ -f "${ARCHIVE}" ]
LIST="$(tar -tzf "${ARCHIVE}")"
for required in \
  "devvy/runtime/node" \
  "devvy/runtime/node.LICENSE" \
  "devvy/daemon/daemon.mjs" \
  "devvy/daemon/config.json" \
  "devvy/daemon/launchd/com.sonawaneutkarsh.devvy.plist" \
  "devvy/devvy-4.0.0.vsix" \
  "devvy/uninstall.sh"; do
  printf '%s\n' "${LIST}" | grep -Fx "${required}" >/dev/null
done
! printf '%s\n' "${LIST}" | grep -E '(^|/)(node_modules|\.git|test-|.*\.log|.*\.sock)(/|$)' >/dev/null
RUNTIME_SIZE="$(tar -xOf "${ARCHIVE}" devvy/runtime/node | wc -c | tr -d ' ')"
[ "${RUNTIME_SIZE}" -gt 100000000 ]
printf 'PASS: %s release payload contains the isolated runtime and required files\n' "${ARCH}"
