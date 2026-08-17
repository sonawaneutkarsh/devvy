#!/usr/bin/env bash
# Build a verified architecture-specific payload for a GitHub Release.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ARCH="${DEVVY_ARCH:-$(uname -m)}"
case "${ARCH}" in
  arm64) NODE_PLATFORM="darwin-arm64"; NODE_SHA256="3f1cf157479c1480352083105e13faf9d008ede98e7e157746b6df940d197b94";;
  x86_64) NODE_PLATFORM="darwin-x64"; NODE_SHA256="d35e95230f46f6f0751df497c56622c6735e05d5e1fb1630996a005b9d328fe4";;
  *) printf 'Unsupported DEVVY_ARCH: %s\n' "${ARCH}" >&2; exit 1;;
esac
OUT="${1:-${ROOT}/devvy-macos-${ARCH}.tar.gz}"
VERSION="${DEVVY_VERSION:-4.0.0}"
VSIX_VERSION="${DEVVY_VSIX_VERSION:-4.0.0}"
NODE_VERSION="v24.19.0"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

[ -f "${ROOT}/devvy-${VSIX_VERSION}.vsix" ] || {
  printf 'Missing bundled VSIX: %s\n' "${ROOT}/devvy-${VSIX_VERSION}.vsix" >&2
  exit 1
}
command -v curl >/dev/null 2>&1 || { printf 'curl is required\n' >&2; exit 1; }
command -v shasum >/dev/null 2>&1 || { printf 'shasum is required\n' >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { printf 'tar is required\n' >&2; exit 1; }
NODE_ARCHIVE="node-${NODE_VERSION}-${NODE_PLATFORM}.tar.xz"
curl --fail --location --silent --show-error \
  "https://nodejs.org/dist/${NODE_VERSION}/${NODE_ARCHIVE}" -o "${STAGE}/${NODE_ARCHIVE}"
[ "$(shasum -a 256 "${STAGE}/${NODE_ARCHIVE}" | awk '{print $1}')" = "${NODE_SHA256}" ] || {
  printf 'Node.js runtime checksum mismatch\n' >&2
  exit 1
}
mkdir -p "${STAGE}/node-runtime" "${STAGE}/devvy/daemon/launchd" \
  "${STAGE}/devvy/integrations/opencode" "${STAGE}/devvy/integrations/commandcode" \
  "${STAGE}/devvy/runtime"
tar -xJf "${STAGE}/${NODE_ARCHIVE}" -C "${STAGE}/node-runtime" --strip-components=1
cp "${STAGE}/node-runtime/bin/node" "${STAGE}/devvy/runtime/node"
cp "${STAGE}/node-runtime/LICENSE" "${STAGE}/devvy/runtime/node.LICENSE"
chmod 755 "${STAGE}/devvy/runtime/node"
rm -rf "${STAGE}/node-runtime" "${STAGE}/${NODE_ARCHIVE}"
cp "${ROOT}/daemon/arbitration.mjs" "${ROOT}/daemon/daemon.mjs" "${ROOT}/daemon/discord-ipc.mjs" \
  "${ROOT}/daemon/model-display.mjs" "${ROOT}/daemon/presence.mjs" "${ROOT}/daemon/config.json" "${STAGE}/devvy/daemon/"
cp "${ROOT}/daemon/launchd/com.sonawaneutkarsh.devvy.plist" "${STAGE}/devvy/daemon/launchd/"
cp "${ROOT}/integrations/opencode/discord-presence.ts" "${STAGE}/devvy/integrations/opencode/"
cp "${ROOT}/integrations/commandcode/discord-presence.ts" "${STAGE}/devvy/integrations/commandcode/"
cp "${ROOT}/devvy-${VSIX_VERSION}.vsix" "${STAGE}/devvy/"
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
