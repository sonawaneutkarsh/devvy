#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="${ROOT}/scripts/vscode-cli.sh"
[ -f "${HELPER}" ]

TEST_HOME="$(mktemp -d)"
TEST_BIN="$(mktemp -d)"
cleanup() { rm -rf "${TEST_HOME}" "${TEST_BIN}"; }
trap cleanup EXIT

mkdir -p "${TEST_HOME}/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
cat > "${TEST_HOME}/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TEST_HOME}/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"

HOME="${TEST_HOME}" PATH="${TEST_BIN}:/usr/bin:/bin" source "${HELPER}"
[ "${DEVVY_VSCODE_APP}" = "${TEST_HOME}/Applications/Visual Studio Code.app" ]
[ "${DEVVY_VSCODE_CLI}" = "${TEST_HOME}/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]

cat > "${TEST_BIN}/code" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TEST_BIN}/code"
HOME="${TEST_HOME}" PATH="${TEST_BIN}:/usr/bin:/bin" source "${HELPER}"
[ "${DEVVY_VSCODE_CLI}" = "${TEST_BIN}/code" ]

rm -rf "${TEST_HOME}/Applications"
HOME="${TEST_HOME}" PATH="${TEST_BIN%/*}/missing:/usr/bin:/bin" source "${HELPER}"
[ -z "${DEVVY_VSCODE_CLI}" ]
[ -z "${DEVVY_VSCODE_APP}" ]
printf 'PASS: VS Code PATH, bundled CLI, and absent-app discovery\n'
