#!/usr/bin/env bash
# Build the verified payload uploaded as devvy-macos.tar.gz to a GitHub Release.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
OUT="${1:-${ROOT}/devvy-macos.tar.gz}"
VERSION="${DEVVY_VERSION:-3.0.1}"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

[ -f "${ROOT}/devvy-${VERSION}.vsix" ] || {
  printf 'Missing bundled VSIX: %s\n' "${ROOT}/devvy-${VERSION}.vsix" >&2
  exit 1
}
mkdir -p "${STAGE}/devvy/daemon/launchd" "${STAGE}/devvy/integrations/opencode" "${STAGE}/devvy/integrations/commandcode"
cp "${ROOT}/daemon/arbitration.mjs" "${ROOT}/daemon/daemon.mjs" "${ROOT}/daemon/discord-ipc.mjs" \
  "${ROOT}/daemon/model-display.mjs" "${ROOT}/daemon/presence.mjs" "${ROOT}/daemon/config.json" "${STAGE}/devvy/daemon/"
cp "${ROOT}/daemon/launchd/com.sonawaneutkarsh.devvy.plist" "${STAGE}/devvy/daemon/launchd/"
cp "${ROOT}/integrations/opencode/discord-presence.ts" "${STAGE}/devvy/integrations/opencode/"
cp "${ROOT}/integrations/commandcode/discord-presence.ts" "${STAGE}/devvy/integrations/commandcode/"
cp "${ROOT}/devvy-${VERSION}.vsix" "${STAGE}/devvy/"
cp "${ROOT}/uninstall.sh" "${STAGE}/devvy/"
find "${STAGE}" -name '.DS_Store' -delete

# Normalize metadata so repeated builds from the same inputs have stable tar entries.
find "${STAGE}" -exec touch -t 202001010000 {} +
rm -f "${OUT}"
TAR_OUT="${OUT%.gz}"
rm -f "${TAR_OUT}"
COPYFILE_DISABLE=1 tar --format=ustar -C "${STAGE}" -cf "${TAR_OUT}" devvy
gzip -n -f "${TAR_OUT}"
printf 'Created %s\n' "${OUT}"
printf 'SHA256 %s\n' "$(shasum -a 256 "${OUT}" | awk '{print $1}')"
