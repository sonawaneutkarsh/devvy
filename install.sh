#!/usr/bin/env bash
# Devvy V4 macOS bootstrapper and installer.
set -euo pipefail

REPO_URL="https://github.com/sonawaneutkarsh/devvy"
RELEASE_VERSION="v4.0.2"
NODE_RUNTIME_VERSION="v24.19.0"
NODE_ARM64_SHA256="3f1cf157479c1480352083105e13faf9d008ede98e7e157746b6df940d197b94"
NODE_X86_64_SHA256="d35e95230f46f6f0751df497c56622c6735e05d5e1fb1630996a005b9d328fe4"
LABEL="com.sonawaneutkarsh.devvy"
INSTALL_DIR="${DEVVY_INSTALL_DIR:-${HOME}/.local/share/devvy}"
TEMP_DIR=""

cleanup() { [ -z "${TEMP_DIR}" ] || rm -rf "${TEMP_DIR}"; }
trap cleanup EXIT
fail() { printf 'Devvy install failed: %s\n' "$*" >&2; exit 1; }
note() { printf 'Devvy: %s\n' "$*"; }

[ "$(uname -s)" = "Darwin" ] || fail "macOS is required."
case "$(uname -m)" in
  arm64) ARCH="arm64"; RELEASE_SHA256="c35d543043b4fe6a8bbd9867c8c244e3346b8b63b932457d8e2fd99f8f0a0fee";;
  x86_64) ARCH="x86_64"; RELEASE_SHA256="629b3ad6589acf053d0c86c2eb79df59aa7c21786f83a3516b06add27d37f416";;
  *) fail "unsupported macOS architecture: $(uname -m)";;
esac
RELEASE_ASSET_NAME="devvy-macos-${ARCH}.tar.gz"
RELEASE_ASSET_URL="${DEVVY_RELEASE_ASSET_URL:-${REPO_URL}/releases/download/${RELEASE_VERSION}/${RELEASE_ASSET_NAME}?download=1}"
note "Installing Devvy ${RELEASE_VERSION} for ${ARCH}."

command -v curl >/dev/null 2>&1 || fail "curl is required."
command -v tar >/dev/null 2>&1 || fail "tar is required."
command -v shasum >/dev/null 2>&1 || fail "shasum is required to verify downloads."
command -v launchctl >/dev/null 2>&1 || fail "launchctl was not found."
command -v lsof >/dev/null 2>&1 || fail "lsof was not found."

SCRIPT_ORIGIN="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
if [ -n "${SCRIPT_ORIGIN}" ] && [ -f "${SCRIPT_ORIGIN}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_ORIGIN}")" && pwd -P)"
fi
SOURCE_DIR=""
if [ -n "${SCRIPT_DIR}" ] && [ -f "${SCRIPT_DIR}/daemon/daemon.mjs" ] && [ -f "${SCRIPT_DIR}/daemon/launchd/${LABEL}.plist" ]; then
  SOURCE_DIR="${SCRIPT_DIR}"
else
  TEMP_DIR="$(mktemp -d)"
  note "Downloading the signed-by-checksum Devvy release artifact."
  curl --fail --location --silent --show-error "${RELEASE_ASSET_URL}" -o "${TEMP_DIR}/devvy-macos.tar.gz" ||
    fail "could not download ${RELEASE_ASSET_URL}."
  ACTUAL_SHA256="$(shasum -a 256 "${TEMP_DIR}/devvy-macos.tar.gz" | awk '{print $1}')"
  [ "${ACTUAL_SHA256}" = "${RELEASE_SHA256}" ] || fail "release checksum mismatch."
  tar -xzf "${TEMP_DIR}/devvy-macos.tar.gz" -C "${TEMP_DIR}" || fail "release archive could not be unpacked."
  SOURCE_DIR="${TEMP_DIR}/devvy"
fi

DAEMON_PATH="${SOURCE_DIR}/daemon/daemon.mjs"
PLIST_SRC="${SOURCE_DIR}/daemon/launchd/${LABEL}.plist"
VSIX_VERSION="4.0.2"
VSIX_PATH="${SOURCE_DIR}/devvy-${VSIX_VERSION}.vsix"
[ -f "${DAEMON_PATH}" ] && [ -f "${PLIST_SRC}" ] || fail "the Devvy payload is incomplete."

NODE_SOURCE="${SOURCE_DIR}/runtime/node"
NODE_LICENSE_SOURCE="${SOURCE_DIR}/runtime/node.LICENSE"
if [ ! -x "${NODE_SOURCE}" ]; then
  [ -n "${TEMP_DIR}" ] || TEMP_DIR="$(mktemp -d)"
  case "${ARCH}" in
    arm64) NODE_ARCHIVE="node-${NODE_RUNTIME_VERSION}-darwin-arm64.tar.xz"; NODE_SHA256="${NODE_ARM64_SHA256}";;
    x86_64) NODE_ARCHIVE="node-${NODE_RUNTIME_VERSION}-darwin-x64.tar.xz"; NODE_SHA256="${NODE_X86_64_SHA256}";;
  esac
  note "Downloading the verified Node.js ${NODE_RUNTIME_VERSION} runtime for ${ARCH}."
  curl --fail --location --silent --show-error \
    "https://nodejs.org/dist/${NODE_RUNTIME_VERSION}/${NODE_ARCHIVE}" -o "${TEMP_DIR}/${NODE_ARCHIVE}" ||
    fail "could not download the Node.js runtime."
  [ "$(shasum -a 256 "${TEMP_DIR}/${NODE_ARCHIVE}" | awk '{print $1}')" = "${NODE_SHA256}" ] ||
    fail "Node.js runtime checksum mismatch."
  mkdir -p "${TEMP_DIR}/node-runtime"
  tar -xJf "${TEMP_DIR}/${NODE_ARCHIVE}" -C "${TEMP_DIR}/node-runtime" --strip-components=1 ||
    fail "Node.js runtime archive could not be unpacked."
  NODE_SOURCE="${TEMP_DIR}/node-runtime/bin/node"
  NODE_LICENSE_SOURCE="${TEMP_DIR}/node-runtime/LICENSE"
fi
NODE_MAJOR="$(${NODE_SOURCE} -p 'process.versions.node.split(".")[0]')"
[ "${NODE_MAJOR}" -ge 18 ] || fail "the bundled Node.js runtime is too old."

mkdir -p "${INSTALL_DIR}/daemon/.live-ipc" "${HOME}/Library/LaunchAgents"
UID_VALUE="$(id -u)"
launchctl bootout "gui/${UID_VALUE}/${LABEL}" 2>/dev/null || true
SAVED_CONFIG=""
if [ -f "${INSTALL_DIR}/daemon/config.json" ]; then
  SAVED_CONFIG="${TEMP_DIR:-$(mktemp -d)}/devvy-config.json"
  cp "${INSTALL_DIR}/daemon/config.json" "${SAVED_CONFIG}"
fi
rm -rf "${INSTALL_DIR}/daemon" "${INSTALL_DIR}/integrations" "${INSTALL_DIR}/runtime" "${INSTALL_DIR}/scripts"
mkdir -p "${INSTALL_DIR}/daemon/launchd" "${INSTALL_DIR}/integrations/opencode" "${INSTALL_DIR}/integrations/commandcode" "${INSTALL_DIR}/runtime"
mkdir -p "${INSTALL_DIR}/scripts"
cp "${SOURCE_DIR}/daemon/arbitration.mjs" "${SOURCE_DIR}/daemon/daemon.mjs" "${SOURCE_DIR}/daemon/discord-ipc.mjs" \
  "${SOURCE_DIR}/daemon/model-display.mjs" "${SOURCE_DIR}/daemon/presence.mjs" "${SOURCE_DIR}/daemon/config.json" "${INSTALL_DIR}/daemon/"
cp "${PLIST_SRC}" "${INSTALL_DIR}/daemon/launchd/"
cp "${SOURCE_DIR}/integrations/opencode/discord-presence.ts" "${INSTALL_DIR}/integrations/opencode/"
cp "${SOURCE_DIR}/integrations/commandcode/discord-presence.ts" "${INSTALL_DIR}/integrations/commandcode/"
cp "${SOURCE_DIR}/scripts/vscode-cli.sh" "${INSTALL_DIR}/scripts/"
cp "${NODE_SOURCE}" "${INSTALL_DIR}/runtime/node"
if [ -f "${NODE_LICENSE_SOURCE}" ]; then cp "${NODE_LICENSE_SOURCE}" "${INSTALL_DIR}/runtime/node.LICENSE"; fi
chmod 755 "${INSTALL_DIR}/runtime/node"
mkdir -p "${INSTALL_DIR}/daemon/.live-ipc"
[ -z "${SAVED_CONFIG}" ] || cp "${SAVED_CONFIG}" "${INSTALL_DIR}/daemon/config.json"
if [ -f "${SOURCE_DIR}/uninstall.sh" ]; then cp "${SOURCE_DIR}/uninstall.sh" "${INSTALL_DIR}/uninstall.sh"; fi
INSTALLED_VSIX_PATH="${INSTALL_DIR}/devvy-${VSIX_VERSION}.vsix"
if [ -f "${VSIX_PATH}" ]; then cp "${VSIX_PATH}" "${INSTALLED_VSIX_PATH}"; fi

REPO_DIR="$(cd "${INSTALL_DIR}" && pwd -P)"
DAEMON_DIR="${REPO_DIR}/daemon"
DAEMON_PATH="${DAEMON_DIR}/daemon.mjs"
NODE_PATH="${REPO_DIR}/runtime/node"
PLIST_DST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
sed -e "s|__NODE_PATH__|${NODE_PATH}|g" -e "s|__DAEMON_PATH__|${DAEMON_PATH}|g" \
  -e "s|__DAEMON_DIR__|${DAEMON_DIR}|g" "${PLIST_SRC}" > "${PLIST_DST}"

launchctl bootstrap "gui/${UID_VALUE}" "${PLIST_DST}" || fail "launchd could not load Devvy."
launchctl kickstart -k "gui/${UID_VALUE}/${LABEL}" || fail "launchd could not start Devvy."

install_integration() {
  local command_name="$1" source="$2" destination="$3"
  if command -v "${command_name}" >/dev/null 2>&1; then
    mkdir -p "$(dirname "${destination}")"
    cp "${source}" "${destination}"
    note "Installed ${command_name} integration."
  fi
}
install_integration opencode "${REPO_DIR}/integrations/opencode/discord-presence.ts" "${HOME}/.config/opencode/plugins/discord-presence.ts"
install_integration commandcode "${REPO_DIR}/integrations/commandcode/discord-presence.ts" "${HOME}/.commandcode/mods/discord-presence.ts"

CLI_HELPER="${SOURCE_DIR}/scripts/vscode-cli.sh"
[ -f "${CLI_HELPER}" ] || fail "the Devvy payload is missing its VS Code integration helper."
# shellcheck source=/dev/null
source "${CLI_HELPER}"
if [ -n "${DEVVY_VSCODE_CLI}" ] && [ -f "${VSIX_PATH}" ]; then
  "${DEVVY_VSCODE_CLI}" --install-extension "${VSIX_PATH}" --force >/dev/null || fail "VS Code could not install the Devvy VSIX."
  "${DEVVY_VSCODE_CLI}" --list-extensions --show-versions | awk -F@ '$1 == "sonawaneutkarsh.devvy" { found=1; print "Devvy: VS Code extension installed: " $0 } END { exit !found }' ||
    fail "VS Code did not report sonawaneutkarsh.devvy after installation."
elif [ -n "${DEVVY_VSCODE_APP}" ]; then
  fail "VS Code was found at ${DEVVY_VSCODE_APP}, but its bundled CLI could not be located. Reinstall VS Code from Microsoft and run the installer again."
else
  note "VS Code was not detected; the daemon is installed and the bundled extension is available at ${INSTALLED_VSIX_PATH}."
fi

launchctl print "gui/${UID_VALUE}/${LABEL}" >/dev/null 2>&1 || fail "V4 LaunchAgent is not loaded."
for _ in $(seq 1 30); do
  HEALTH_RESPONSE="$(curl -fsS http://127.0.0.1:17377/healthz 2>/dev/null || true)"
  if [ -n "${HEALTH_RESPONSE}" ] && "${NODE_PATH}" -e \
    'const v=JSON.parse(process.argv[1]); process.exit(v.ok === true && v.service === "devvy" && v.launchAgent === "com.sonawaneutkarsh.devvy" ? 0 : 1)' \
    "${HEALTH_RESPONSE}" >/dev/null 2>&1; then
    PORT_OWNER="$(lsof -nP -iTCP:17377 -sTCP:LISTEN -t 2>/dev/null | sort -u | awk 'NF {print; exit}')"
    [ -n "${PORT_OWNER}" ] || fail "daemon health succeeded but port 17377 has no listener."
    [ "$(ps -p "${PORT_OWNER}" -o command= | grep -F -- "${DAEMON_PATH}" || true)" ] || fail "port 17377 is not owned by the V4 daemon."
echo "Devvy ${RELEASE_VERSION} installed successfully."
    echo "  install: ${INSTALL_DIR}"
    echo "  agent:   ${LABEL}"
    echo "  health:  http://127.0.0.1:17377/healthz"
    exit 0
  fi
  sleep 0.25
done
fail "V4 LaunchAgent loaded but daemon health did not respond. Check ${DAEMON_DIR}/.live-ipc/launchd.stderr.log"
