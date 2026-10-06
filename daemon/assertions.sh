# shellcheck shell=bash
# Shared assertions for the daemon integration tests (sourced, not a test).
# Source this file after setting MOCK_LOG (mock Discord server log) and DAEMON_LOG (daemon stdout).
#
# Every assertion prints what it expected, what it saw, and both logs before it
# exits, so a CI failure explains itself instead of ending on a silent grep.
# Note: `! grep ...` is NOT an assertion under `set -e` (bash ignores errexit
# for negated commands), so use expect_absent instead.

print_logs() {
  printf -- '--- mock Discord log (%s):\n' "${MOCK_LOG:-unset}" >&2
  [ -n "${MOCK_LOG:-}" ] && [ -f "${MOCK_LOG}" ] && sed 's/^/  /' "${MOCK_LOG}" >&2 || true
  printf -- '--- daemon log (%s):\n' "${DAEMON_LOG:-unset}" >&2
  [ -n "${DAEMON_LOG:-}" ] && [ -f "${DAEMON_LOG}" ] && sed 's/^/  /' "${DAEMON_LOG}" >&2 || true
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  print_logs
  exit 1
}

# Report the exact command and line when a bare command fails under set -e.
on_error() {
  local status=$?
  printf 'FAIL: command exited %s at %s:%s: %s\n' "${status}" "${BASH_SOURCE[1]:-$0}" "$1" "$2" >&2
  print_logs
  exit "${status}"
}
trap 'on_error "${LINENO}" "${BASH_COMMAND}"' ERR

activities() {
  grep -E 'ACTIVITY (details|cleared)' "${MOCK_LOG}" 2>/dev/null | sed 's/^\[[^]]*\] //' || true
}

last_activity() {
  activities | tail -1
}

wait_for_health() {
  local port="$1"
  for _ in $(seq 1 50); do
    curl -fsS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  fail "daemon on port ${port} did not pass /healthz within 10s"
}

# expect_log FILE FIXED_STRING DESCRIPTION
expect_log() {
  grep -F -- "$2" "$1" >/dev/null 2>&1 || fail "$3 (expected '$2' in $(basename "$1"))"
}

# expect_absent FILE FIXED_STRING DESCRIPTION
expect_absent() {
  if grep -F -- "$2" "$1" >/dev/null 2>&1; then
    fail "$3 (found forbidden '$2' in $(basename "$1"))"
  fi
}

# expect_last_activity FIXED_STRING DESCRIPTION
expect_last_activity() {
  local last
  last="$(last_activity)"
  case "${last}" in
    *"$1"*) ;;
    *) fail "$2 (expected last activity to contain '$1', got '${last:-<none>}')" ;;
  esac
}

# expect_activity_sequence FIXED_STRING... : each string must appear in the
# activity stream, in this order (other activities may appear in between).
expect_activity_sequence() {
  local remaining
  remaining="$(activities)"
  for want in "$@"; do
    local line
    line="$(printf '%s\n' "${remaining}" | grep -n -F -- "${want}" | head -1 | cut -d: -f1 || true)"
    [ -n "${line}" ] || fail "activity '${want}' missing or out of order; expected sequence: $*"
    remaining="$(printf '%s\n' "${remaining}" | tail -n "+$((line + 1))")"
  done
}

# expect_count FIXED_STRING FILE EXPECTED DESCRIPTION
expect_count() {
  local got
  got="$(grep -c -F -- "$1" "$2" 2>/dev/null || true)"
  [ "${got:-0}" -eq "$3" ] || fail "$4 (expected ${3} lines with '$1', got ${got:-0})"
}
