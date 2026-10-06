#!/usr/bin/env bash
# Run every Devvy test script (unit tests, daemon integration tests against a
# mock Discord IPC server, Windows helpers, and VS Code CLI discovery).
# Runs all tests even after a failure, prints a summary, and exits non-zero if
# any test failed. Under GitHub Actions each test is a collapsible log group
# and each failure becomes an error annotation.
# Usage: scripts/run-tests.sh [TEST_FILE...]
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT}" || exit 1

if [ "$#" -gt 0 ]; then
  TESTS=("$@")
else
  TESTS=(daemon/test-*.mjs windows/test-*.mjs scripts/test-vscode-cli.sh daemon/test-*.sh)
fi

in_ci() { [ -n "${GITHUB_ACTIONS:-}" ]; }
PASSED=()
FAILED=()
LOG_DIR="$(mktemp -d)"
trap 'rm -rf "${LOG_DIR}"' EXIT

for test in "${TESTS[@]}"; do
  [ -f "${test}" ] || { printf 'FAIL: test file not found: %s\n' "${test}" >&2; FAILED+=("${test}"); continue; }
  log="${LOG_DIR}/$(printf '%s' "${test}" | tr '/' '_').log"
  case "${test}" in
    *.mjs) runner=(node "${test}") ;;
    *.sh) runner=(bash "${test}") ;;
    *) printf 'FAIL: unknown test type: %s\n' "${test}" >&2; FAILED+=("${test}"); continue ;;
  esac
  in_ci && printf '::group::%s\n' "${test}"
  start=$(date +%s)
  "${runner[@]}" > "${log}" 2>&1
  status=$?
  elapsed=$(( $(date +%s) - start ))
  cat "${log}"
  in_ci && printf '::endgroup::\n'
  if [ "${status}" -eq 0 ]; then
    printf 'ok   %-40s %4ss\n' "${test}" "${elapsed}"
    PASSED+=("${test}")
  else
    printf 'FAIL %-40s %4ss (exit %s)\n' "${test}" "${elapsed}" "${status}"
    FAILED+=("${test}")
    reason="$(grep -m1 '^FAIL' "${log}" || tail -n 1 "${log}")"
    in_ci && printf '::error file=%s,title=%s failed::%s\n' "${test}" "${test}" "${reason//$'\n'/ }"
  fi
done

printf '\n%s passed, %s failed, %s total\n' "${#PASSED[@]}" "${#FAILED[@]}" "${#TESTS[@]}"
if [ "${#FAILED[@]}" -gt 0 ]; then
  printf '\nFailed tests (full output above):\n' >&2
  printf '  %s\n' "${FAILED[@]}" >&2
  exit 1
fi
