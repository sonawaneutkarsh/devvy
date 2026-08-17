#!/usr/bin/env bash
# Sets DEVVY_VSCODE_CLI and DEVVY_VSCODE_APP for the current user.
DEVVY_VSCODE_CLI="$(command -v code || true)"
DEVVY_VSCODE_APP=""
for candidate in \
  "/Applications/Visual Studio Code.app" \
  "${HOME}/Applications/Visual Studio Code.app" \
  "/Applications/Visual Studio Code - Insiders.app" \
  "${HOME}/Applications/Visual Studio Code - Insiders.app"; do
  if [ -d "${candidate}" ]; then
    DEVVY_VSCODE_APP="${candidate}"
    if [ -z "${DEVVY_VSCODE_CLI}" ] && [ -x "${candidate}/Contents/Resources/app/bin/code" ]; then
      DEVVY_VSCODE_CLI="${candidate}/Contents/Resources/app/bin/code"
    fi
    [ -n "${DEVVY_VSCODE_CLI}" ] && break
  fi
done
