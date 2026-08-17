#!/usr/bin/env bash
# Devvy V3 macOS bootstrapper and installer.
set -euo pipefail

REPO_URL="https://github.com/sonawaneutkarsh/devvy"
RELEASE_VERSION="v3.0.1"
RELEASE_ASSET_URL="${REPO_URL}/releases/download/${RELEASE_VERSION}/devvy-macos.tar.gz?download=1"
# Updated by scripts/package-release.sh after the release archive is built.
RELEASE_SHA256="f30bc1f9af0c7e917f42cfde255d2a8c5d1318bc2cb1eda129a130d36578a95f"
LABEL="com.sonawaneutkarsh.devvy"
INSTALL_DIR="${DEVVY_INSTALL_DIR:-${HOME}/.local/share/devvy}"
TEMP_DIR=""

cleanup() { [ -z "${TEMP_DIR}" ] || rm -rf "${TEMP_DIR}"; }
trap cleanup EXIT
fail() { printf 'Devvy install failed: %s\n' "$*" >&2; exit 1; }
note() { printf 'Devvy: %s\n' "$*"; }

[ "$(uname -s)" = "Darwin" ] || fail "macOS is required."
case "$(uname -m)" in
  arm64) ARCH="arm64";;
  x86_64) ARCH="x86_64";;
  *) fail "unsupported macOS architecture: $(uname -m)";;
esac
note "Installing Devvy ${RELEASE_VERSION} for ${ARCH}."

command -v node >/dev/null 2>&1 || fail "Node.js 18 or later is required."
NODE_PATH="$(command -v node)"
NODE_MAJOR="$(${NODE_PATH} -p 'process.versions.node.split(".")[0]')"
[ "${NODE_MAJOR}" -ge 18 ] || fail "Node.js 18 or later is required (found ${NODE_PATH})."
command -v launchctl >/dev/null 2>&1 || fail "launchctl was not found."
command -v lsof >/dev/null 2>&1 || fail "lsof was not found."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_DIR=""
if [ -f "${SCRIPT_DIR}/daemon/daemon.mjs" ] && [ -f "${SCRIPT_DIR}/daemon/launchd/${LABEL}.plist" ]; then
  SOURCE_DIR="${SCRIPT_DIR}"
else
  command -v curl >/dev/null 2>&1 || fail "curl is required for release installation."
  command -v tar >/dev/null 2>&1 || fail "tar is required for release installation."
  command -v shasum >/dev/null 2>&1 || fail "shasum is required to verify the release."
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
VSIX_PATH="${SOURCE_DIR}/devvy-${RELEASE_VERSION#v}.vsix"
[ -f "${DAEMON_PATH}" ] && [ -f "${PLIST_SRC}" ] || fail "the Devvy payload is incomplete."

mkdir -p "${INSTALL_DIR}/daemon/.live-ipc" "${HOME}/Library/LaunchAgents"
UID_VALUE="$(id -u)"
launchctl bootout "gui/${UID_VALUE}/${LABEL}" 2>/dev/null || true
SAVED_CONFIG=""
if [ -f "${INSTALL_DIR}/daemon/config.json" ]; then
  SAVED_CONFIG="${TEMP_DIR:-$(mktemp -d)}/devvy-config.json"
  cp "${INSTALL_DIR}/daemon/config.json" "${SAVED_CONFIG}"
fi
rm -rf "${INSTALL_DIR}/daemon" "${INSTALL_DIR}/integrations"
mkdir -p "${INSTALL_DIR}/daemon/launchd" "${INSTALL_DIR}/integrations/opencode" "${INSTALL_DIR}/integrations/commandcode"
cp "${SOURCE_DIR}/daemon/arbitration.mjs" "${SOURCE_DIR}/daemon/daemon.mjs" "${SOURCE_DIR}/daemon/discord-ipc.mjs" \
  "${SOURCE_DIR}/daemon/model-display.mjs" "${SOURCE_DIR}/daemon/presence.mjs" "${SOURCE_DIR}/daemon/config.json" "${INSTALL_DIR}/daemon/"
cp "${PLIST_SRC}" "${INSTALL_DIR}/daemon/launchd/"
cp "${SOURCE_DIR}/integrations/opencode/discord-presence.ts" "${INSTALL_DIR}/integrations/opencode/"
cp "${SOURCE_DIR}/integrations/commandcode/discord-presence.ts" "${INSTALL_DIR}/integrations/commandcode/"
mkdir -p "${INSTALL_DIR}/daemon/.live-ipc"
[ -z "${SAVED_CONFIG}" ] || cp "${SAVED_CONFIG}" "${INSTALL_DIR}/daemon/config.json"
if [ -f "${SOURCE_DIR}/uninstall.sh" ]; then cp "${SOURCE_DIR}/uninstall.sh" "${INSTALL_DIR}/uninstall.sh"; fi
INSTALLED_VSIX_PATH="${INSTALL_DIR}/devvy-${RELEASE_VERSION#v}.vsix"
if [ -f "${VSIX_PATH}" ]; then cp "${VSIX_PATH}" "${INSTALLED_VSIX_PATH}"; fi

REPO_DIR="$(cd "${INSTALL_DIR}" && pwd -P)"
DAEMON_DIR="${REPO_DIR}/daemon"
DAEMON_PATH="${DAEMON_DIR}/daemon.mjs"
NODE_PATH="$(cd "$(dirname "${NODE_PATH}")" && pwd -P)/$(basename "${NODE_PATH}")"
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

VS_CODE_APP=""
for candidate in "/Applications/Visual Studio Code.app" "${HOME}/Applications/Visual Studio Code.app"; do
  [ -d "${candidate}" ] && VS_CODE_APP="${candidate}" && break
done
if command -v code >/dev/null 2>&1 && [ -f "${VSIX_PATH}" ]; then
  code --install-extension "${VSIX_PATH}" --force >/dev/null || fail "VS Code could not install the Devvy VSIX."
  code --list-extensions --show-versions | awk -F@ '$1 == "sonawaneutkarsh.devvy" { found=1; print "Devvy: VS Code extension installed: " $0 } END { exit !found }' ||
    fail "VS Code did not report sonawaneutkarsh.devvy after installation."
elif [ -n "${VS_CODE_APP}" ]; then
  note "VS Code is installed, but the code CLI is unavailable. Enable Shell Command: Install 'code' command in PATH, then run:"
  note "code --install-extension ${INSTALLED_VSIX_PATH} --force"
else
  note "VS Code was not detected; the bundled extension remains at ${INSTALLED_VSIX_PATH}."
fi

launchctl print "gui/${UID_VALUE}/${LABEL}" >/dev/null 2>&1 || fail "V3 LaunchAgent is not loaded."
for _ in $(seq 1 30); do
  HEALTH_RESPONSE="$(curl -fsS http://127.0.0.1:17377/healthz 2>/dev/null || true)"
  if [ -n "${HEALTH_RESPONSE}" ] && "${NODE_PATH}" -e \
    'const v=JSON.parse(process.argv[1]); process.exit(v.ok === true && v.service === "devvy" && v.launchAgent === "com.sonawaneutkarsh.devvy" ? 0 : 1)' \
    "${HEALTH_RESPONSE}" >/dev/null 2>&1; then
    PORT_OWNER="$(lsof -nP -iTCP:17377 -sTCP:LISTEN -t 2>/dev/null | sort -u | awk 'NF {print; exit}')"
    [ -n "${PORT_OWNER}" ] || fail "daemon health succeeded but port 17377 has no listener."
    [ "$(ps -p "${PORT_OWNER}" -o command= | grep -F -- "${DAEMON_PATH}" || true)" ] || fail "port 17377 is not owned by the V3 daemon."
    echo "Devvy ${RELEASE_VERSION} installed successfully."
    echo "  install: ${INSTALL_DIR}"
    echo "  agent:   ${LABEL}"
    echo "  health:  http://127.0.0.1:17377/healthz"
    exit 0
  fi
  sleep 0.25
done
fail "V3 LaunchAgent loaded but daemon health did not respond. Check ${DAEMON_DIR}/.live-ipc/launchd.stderr.log"
