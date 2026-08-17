#!/usr/bin/env bash
# Build the archive uploaded as devvy-macos.tar.gz to a GitHub Release.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
OUT="${1:-${ROOT}/devvy-macos.tar.gz}"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
mkdir -p "${STAGE}/devvy"
cp -R "${ROOT}/daemon" "${ROOT}/integrations" "${ROOT}/vscode-extension" "${STAGE}/devvy/"
cp "${ROOT}/install.sh" "${ROOT}/README.md" "${ROOT}/LICENSE" "${STAGE}/devvy/"
find "${STAGE}" -name '.DS_Store' -delete
find "${STAGE}" -maxdepth 3 -type d -name '.test-*' -exec rm -rf {} + 2>/dev/null || true
find "${STAGE}" -maxdepth 3 -type d -name '.live-*' -exec rm -rf {} + 2>/dev/null || true
tar -C "${STAGE}" -czf "${OUT}" devvy
echo "Created ${OUT}"
