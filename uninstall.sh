#!/usr/bin/env bash
set -euo pipefail
LABEL="com.sonawaneutkarsh.devvy"
INSTALL_DIR="${DEVVY_INSTALL_DIR:-${HOME}/.local/share/devvy}"
UID_VALUE="$(id -u)"
if [ "$(uname -s)" = "Darwin" ] && command -v launchctl >/dev/null 2>&1; then
  launchctl bootout "gui/${UID_VALUE}/${LABEL}" 2>/dev/null || true
fi
rm -f "${HOME}/Library/LaunchAgents/${LABEL}.plist"
rm -f "${HOME}/.config/opencode/plugins/discord-presence.ts" "${HOME}/.commandcode/mods/discord-presence.ts"
if command -v code >/dev/null 2>&1; then
  code --uninstall-extension sonawaneutkarsh.devvy >/dev/null 2>&1 || true
fi
rm -rf "${INSTALL_DIR}"
printf 'Devvy V3 uninstalled. Unrelated LaunchAgents and VS Code extensions were not changed.\n'
