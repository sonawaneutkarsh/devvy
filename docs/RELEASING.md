# Releasing Devvy

GitHub Actions publishes releases. Do not upload release assets by hand.

## Version source

`vscode-extension/package.json` `version` is the single version source.
`scripts/version.sh` prints it. The VSIX name, the payload contents, and the
release tag derive from it. `scripts/check-versions.sh` fails CI when
`windows/install.ps1` disagrees, or when a tag does not match.

`install.sh` is the exception by design. It pins the latest **published**
macOS release (`RELEASE_VERSION`, `VSIX_VERSION`, and both `RELEASE_SHA256`
values), so it changes only after a release exists.

## Steps

1. On `main`, set `version` in `vscode-extension/package.json` and the default
   `ReleaseVersion` in `windows/install.ps1` to the new version. Push. Wait for
   CI to pass.
2. Optional dry run: Actions → **Release** → **Run workflow** on `main`. This
   runs the full verification, builds every payload, and lists the SHA-256
   checksums in the run summary. It never publishes.
3. Tag and push: `git tag v4.1.0 && git push origin v4.1.0`.
4. The **Release** workflow then runs:
   - `preflight`: the tag must equal `v<version>`;
   - `verify`: the complete CI workflow (`ci.yml`) on the tagged commit, which
     runs the tests and builds and validates the VSIX and payloads;
   - `checksums`: writes `SHA256SUMS` from the verified payloads;
   - `publish`: creates the GitHub Release with those exact files. It runs
     only when every earlier job passed, and it never overwrites an existing
     release.
5. Pin the new macOS checksums from `SHA256SUMS` in `install.sh`
   (`RELEASE_VERSION`, `VSIX_VERSION`, `RELEASE_SHA256` for `arm64` and
   `x86_64`). Push. Until this commit lands, the one-line installer keeps
   installing the previous release.

If CI fails on the tag, nothing is published. Fix the problem on `main`,
delete the tag (`git push --delete origin vX.Y.Z`), and tag again.
