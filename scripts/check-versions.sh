#!/usr/bin/env bash
# Verify that every version reference agrees with scripts/version.sh.
# Usage: scripts/check-versions.sh [TAG]   (TAG, e.g. v4.1.0, is checked when given)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION="$("${ROOT}/scripts/version.sh")"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

printf '%s' "${VERSION}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' ||
  fail "vscode-extension/package.json version '${VERSION}' is not MAJOR.MINOR.PATCH"

PS_VERSION="$(sed -n "s/.*\[string\]\$ReleaseVersion = '\(v[^']*\)'.*/\1/p" "${ROOT}/windows/install.ps1")"
[ "${PS_VERSION}" = "v${VERSION}" ] ||
  fail "windows/install.ps1 default ReleaseVersion is '${PS_VERSION}', expected 'v${VERSION}'"

# install.sh pins the latest *published* macOS release and its checksums, so it
# may lag behind VERSION until that release exists. It must agree with itself.
SH_RELEASE="$(sed -n 's/^RELEASE_VERSION="\(v[^"]*\)"$/\1/p' "${ROOT}/install.sh")"
SH_VSIX="$(sed -n 's/^VSIX_VERSION="\([^"]*\)"$/\1/p' "${ROOT}/install.sh")"
[ -n "${SH_RELEASE}" ] && [ "${SH_RELEASE}" = "v${SH_VSIX}" ] ||
  fail "install.sh RELEASE_VERSION '${SH_RELEASE}' and VSIX_VERSION '${SH_VSIX}' disagree"

if [ -n "${1:-}" ]; then
  [ "$1" = "v${VERSION}" ] ||
    fail "tag '$1' does not match vscode-extension/package.json version 'v${VERSION}'; bump the version or fix the tag"
fi
printf 'PASS: version %s is consistent (install.sh pins published release %s)\n' "${VERSION}" "${SH_RELEASE}"
