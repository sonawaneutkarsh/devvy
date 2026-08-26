#!/usr/bin/env bash
# Build the Windows x64 payload. This is separate from the macOS packager so
# the published V4.0.2 macOS recipe remains unchanged.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
OUT="${1:-${ROOT}/devvy-windows-x86_64.zip}"
VERSION="${DEVVY_VERSION:-4.1.0}"
VSIX_VERSION="${DEVVY_VSIX_VERSION:-4.0.2}"
NODE_VERSION="${DEVVY_NODE_VERSION:-v24.19.0}"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

[ -f "${ROOT}/devvy-${VSIX_VERSION}.vsix" ] || { printf 'Missing bundled VSIX\n' >&2; exit 1; }
for command_name in curl shasum unzip zip; do command -v "${command_name}" >/dev/null 2>&1 || { printf '%s is required\n' "${command_name}" >&2; exit 1; }; done
ARCHIVE="node-${NODE_VERSION}-win-x64.zip"
curl --fail --location --silent --show-error "https://nodejs.org/dist/${NODE_VERSION}/${ARCHIVE}" -o "${STAGE}/${ARCHIVE}"
curl --fail --location --silent --show-error "https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt" -o "${STAGE}/SHASUMS256.txt"
EXPECTED="$(awk -v file="${ARCHIVE}" '$2 == file {print $1}' "${STAGE}/SHASUMS256.txt")"
[ -n "${EXPECTED}" ] && [ "$(shasum -a 256 "${STAGE}/${ARCHIVE}" | awk '{print $1}')" = "${EXPECTED}" ] || { printf 'Node.js runtime checksum mismatch\n' >&2; exit 1; }
mkdir -p "${STAGE}/devvy/runtime" "${STAGE}/devvy/daemon/.live-ipc" \
  "${STAGE}/devvy/integrations/opencode" "${STAGE}/devvy/integrations/commandcode" \
  "${STAGE}/devvy/scripts" "${STAGE}/devvy/windows"
unzip -q "${STAGE}/${ARCHIVE}" -d "${STAGE}/node"
cp "${STAGE}/node/node-${NODE_VERSION}-win-x64/node.exe" "${STAGE}/devvy/runtime/node.exe"
cp "${STAGE}/node/node-${NODE_VERSION}-win-x64/LICENSE" "${STAGE}/devvy/runtime/node.LICENSE"
cp "${ROOT}/daemon/arbitration.mjs" "${ROOT}/daemon/daemon.mjs" "${ROOT}/daemon/discord-ipc.mjs" \
  "${ROOT}/daemon/model-display.mjs" "${ROOT}/daemon/presence.mjs" "${ROOT}/daemon/config.json" "${STAGE}/devvy/daemon/"
cp "${ROOT}/integrations/opencode/discord-presence.ts" "${STAGE}/devvy/integrations/opencode/"
cp "${ROOT}/integrations/commandcode/discord-presence.ts" "${STAGE}/devvy/integrations/commandcode/"
cp "${ROOT}/devvy-${VSIX_VERSION}.vsix" "${STAGE}/devvy/"
cp "${ROOT}/windows/install.ps1" "${ROOT}/windows/run-daemon.ps1" "${STAGE}/devvy/windows/"
cp "${ROOT}/scripts/vscode-cli.ps1" "${STAGE}/devvy/scripts/"
cp "${ROOT}/windows/uninstall.ps1" "${STAGE}/devvy/"
rm -rf "${STAGE}/node" "${STAGE}/${ARCHIVE}" "${STAGE}/SHASUMS256.txt"
rm -f "${OUT}" "${OUT}.sha256"
(cd "${STAGE}" && zip -q -r -X "${OUT}" devvy)
printf '%s  %s\n' "$(shasum -a 256 "${OUT}" | awk '{print $1}')" "$(basename "${OUT}")" > "${OUT}.sha256"
