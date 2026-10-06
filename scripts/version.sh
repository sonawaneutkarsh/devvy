#!/usr/bin/env bash
# Print the Devvy version. vscode-extension/package.json "version" is the single
# source: the VSIX name, release payloads, and release tags all derive from it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
node -p "require(process.argv[1]).version" "${ROOT}/vscode-extension/package.json"
