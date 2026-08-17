#!/usr/bin/env bash
# Devvy's macOS installer. It owns only Devvy's LaunchAgent and integration files.
set -euo pipefail

REPO_URL="https://github.com/sonawaneutkarsh/devvy"
RELEASE_ASSET_URL="${DEVVY_RELEASE_ASSET_URL:-${REPO_URL}/releases/latest/download/devvy-macos.tar.gz}"
LABEL="com.rich.discord-presence"
TEMP_DIR=""

cleanup() { [ -z "${TEMP_DIR}" ] || rm -rf "${TEMP_DIR}"; }
trap cleanup EXIT

fail() { echo "Devvy install failed: $*" >&2; exit 1; }
note() { echo "Devvy: $*"; }

[ "$(uname -s)" = "Darwin" ] || fail "macOS is required (the LaunchAgent uses launchd)."

# Running from a checkout needs no network. The release installer obtains only
# the matching archive from this project's official GitHub Release.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/daemon/daemon.mjs" ]; then
  REPO_DIR="${SCRIPT_DIR}"
else
  command -v curl >/dev/null 2>&1 || fail "curl is required to download the official release archive."
  command -v tar >/dev/null 2>&1 || fail "tar is required to unpack the official release archive."
  TEMP_DIR="$(mktemp -d)"
  note "Downloading the official Devvy release archive from GitHub…"
  curl --fail --location --silent --show-error "${RELEASE_ASSET_URL}" -o "${TEMP_DIR}/devvy-macos.tar.gz" ||
    fail "could not download ${RELEASE_ASSET_URL}. A GitHub Release may not exist yet."
  tar -xzf "${TEMP_DIR}/devvy-macos.tar.gz" -C "${TEMP_DIR}" ||
    fail "the release archive could not be unpacked."
  FOUND_DAEMON="$(find "${TEMP_DIR}" -type f -path '*/daemon/daemon.mjs' -print -quit)"
  [ -n "${FOUND_DAEMON}" ] || fail "the release archive does not contain a Devvy installation."
  PACKAGE_DIR="$(dirname "$(dirname "${FOUND_DAEMON}")")"
  INSTALL_DIR="${DEVVY_INSTALL_DIR:-${HOME}/.local/share/devvy}"
  mkdir -p "${INSTALL_DIR}"
  # Preserve local asset/client configuration while replacing only Devvy files.
  SAVED_CONFIG=""
  if [ -f "${INSTALL_DIR}/daemon/config.json" ]; then
    SAVED_CONFIG="${TEMP_DIR}/config.json"
    cp "${INSTALL_DIR}/daemon/config.json" "${SAVED_CONFIG}"
  fi
  cp -R "${PACKAGE_DIR}/." "${INSTALL_DIR}/"
  [ -z "${SAVED_CONFIG}" ] || cp "${SAVED_CONFIG}" "${INSTALL_DIR}/daemon/config.json"
  REPO_DIR="${INSTALL_DIR}"
fi

DAEMON_DIR="${REPO_DIR}/daemon"
DAEMON_PATH="${DAEMON_DIR}/daemon.mjs"
PLIST_SRC="${DAEMON_DIR}/launchd/${LABEL}.plist"
PLIST_DST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
NODE_PATH="$(command -v node || true)"
[ -n "${NODE_PATH}" ] || fail "Node.js 18 or later is required and was not found on PATH."
NODE_MAJOR="$("${NODE_PATH}" -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
[ "${NODE_MAJOR}" -ge 18 ] || fail "Node.js 18 or later is required (found $(node --version 2>/dev/null || echo unknown))."
[ -f "${DAEMON_PATH}" ] && [ -f "${PLIST_SRC}" ] || fail "the Devvy daemon template is incomplete."

# macOS lacks GNU readlink -f; pwd -P produces resolved paths without adding a dependency.
REPO_DIR="$(cd "${REPO_DIR}" && pwd -P)"
DAEMON_DIR="$(cd "${DAEMON_DIR}" && pwd -P)"
DAEMON_PATH="${DAEMON_DIR}/daemon.mjs"
NODE_PATH="$(cd "$(dirname "${NODE_PATH}")" && pwd -P)/$(basename "${NODE_PATH}")"

mkdir -p "${HOME}/Library/LaunchAgents" "${DAEMON_DIR}/.live-ipc"
if [ -f "${PLIST_DST}" ]; then note "Replacing the existing Devvy LaunchAgent configuration."; fi
sed -e "s|__NODE_PATH__|${NODE_PATH}|g" \
    -e "s|__DAEMON_PATH__|${DAEMON_PATH}|g" \
    -e "s|__DAEMON_DIR__|${DAEMON_DIR}|g" \
    "${PLIST_SRC}" > "${PLIST_DST}"

UID_VALUE="$(id -u)"
launchctl bootout "gui/${UID_VALUE}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${UID_VALUE}" "${PLIST_DST}" || fail "launchd could not load Devvy."
launchctl kickstart -k "gui/${UID_VALUE}/${LABEL}" || fail "launchd could not start Devvy."

install_integration() {
  local command_name="$1" source="$2" destination="$3"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    note "${command_name} not detected; skipped its optional integration."
    return
  fi
  mkdir -p "$(dirname "${destination}")"
  if [ -f "${destination}" ] && ! cmp -s "${source}" "${destination}"; then
    note "Updating Devvy's existing ${command_name} integration at ${destination}."
  fi
  cp "${source}" "${destination}"
  note "Installed ${command_name} integration."
}
install_integration opencode "${REPO_DIR}/integrations/opencode/discord-presence.ts" \
  "${HOME}/.config/opencode/plugins/discord-presence.ts"
install_integration commandcode "${REPO_DIR}/integrations/commandcode/discord-presence.ts" \
  "${HOME}/.commandcode/mods/discord-presence.ts"

if command -v code >/dev/null 2>&1; then
  note "VS Code detected. Install the packaged Devvy VSIX with Extensions: Install from VSIX… (or Marketplace after it is published)."
else
  note "VS Code was not detected; its optional extension can be installed later."
fi

launchctl print "gui/${UID_VALUE}/${LABEL}" >/dev/null 2>&1 ||
  fail "the expected Devvy LaunchAgent is not loaded"

for _ in $(seq 1 20); do
  HEALTH_RESPONSE="$(curl -fsS "http://127.0.0.1:17377/healthz" 2>/dev/null || true)"
  if [ -n "${HEALTH_RESPONSE}" ] && "${NODE_PATH}" -e \
      'const value = JSON.parse(process.argv[1]); process.exit(value.ok === true && value.service === "devvy" && value.launchAgent === "com.rich.discord-presence" ? 0 : 1)' \
      "${HEALTH_RESPONSE}" >/dev/null 2>&1; then
    echo "Devvy installed successfully."
    echo "  daemon: ${DAEMON_DIR}"
    echo "  health: http://127.0.0.1:17377/healthz"
    exit 0
  fi
  sleep 0.25
done
fail "LaunchAgent was installed but the daemon health check did not respond. Check ${DAEMON_DIR}/.live-ipc/launchd.stderr.log"
