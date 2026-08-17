# Devvy

**One Discord presence for your entire coding workflow.**

Devvy combines safe activity from OpenCode, Command Code, and VS Code into one
Discord Rich Presence. It is local-only: one small daemon owns Discord IPC and
every integration publishes only to its loopback HTTP endpoint.

```
OpenCode ───────┐
Command Code ───┼──> 127.0.0.1 Devvy daemon ──> Discord IPC
VS Code ────────┘
```

The daemon is the **only** Discord IPC/RPC client. Integrations never connect
to Discord, cloud services, accounts, databases, or telemetry.

## What is shown

Devvy uses a friendly model label such as `GLM 5.3` or `DeepSeek V4 Pro` and
short supported labels including **Reading files**, **Searching code**,
**Editing code**, **Running commands**, **Thinking…**, **Waiting for
response**, **Reviewing changes**, and **Working on code**. Idle agent
sessions show **Waiting for prompt**. VS Code shows only a project basename
and file basename/language when available.

Source priority is OpenCode, then Command Code, then VS Code. An active source
beats an idle-held source. Within a source kind, a newer real active transition
wins; ties use a stable source ID. Heartbeats do not affect selection. Sources
expire after the existing 15-second TTL, and Discord updates remain deduplicated
and throttled.

## Install (macOS)

For a checkout:

```bash
git clone https://github.com/sonawaneutkarsh/devvy.git
cd devvy
./install.sh
curl -fsS http://127.0.0.1:17377/healthz
```

The eventual release command is:

```bash
curl -fsSL https://github.com/sonawaneutkarsh/devvy/releases/latest/download/install.sh | bash
```

It will work only after a GitHub Release includes both `install.sh` and
`devvy-macos.tar.gz`; no release is published by this repository change. The
installer detects macOS and Node.js 18+, creates or updates only Devvy's
LaunchAgent, installs optional OpenCode/Command Code files when their commands
are detected, starts the existing daemon, and checks `/healthz`. It preserves an
existing `daemon/config.json` when installing from a release archive.

The installer changes:
- `~/Library/LaunchAgents/com.rich.discord-presence.plist`
- Devvy integration files under `~/.config/opencode/plugins/` and
  `~/.commandcode/mods/` only when the matching tool is installed
- Release installs: `~/.local/share/devvy` (override with `DEVVY_INSTALL_DIR`)

It downloads only the official GitHub Release archive, does not use credentials,
and collects/transmits no data.

## VS Code extension

The extension sends safe state only to `http://127.0.0.1:17377/state`; it does
not create a Discord connection. It supports focused/editor changes, workspace
and Git branch refreshes, heartbeats, graceful deactivation, multiple windows,
and automatic recovery after daemon restarts.

Marketplace publication has **not** happened. For development/testing:

```bash
cd vscode-extension
npm run package
# VS Code → Extensions: Install from VSIX…
```

This produces `devvy-2.0.0.vsix` at the repository root with standard `vsce`.
The VSIX excludes source control, `node_modules`, tests, logs, and runtime
files. Publication still requires creating/verifying the `sonawaneutkarsh`
Visual Studio Marketplace publisher and publishing the generated VSIX.

## OpenCode and Command Code

The checkout installer copies the existing integration only when its command is
present. Manual setup is also supported:

```bash
mkdir -p ~/.config/opencode/plugins ~/.commandcode/mods
cp integrations/opencode/discord-presence.ts ~/.config/opencode/plugins/
cp integrations/commandcode/discord-presence.ts ~/.commandcode/mods/
```

Restart the relevant application after installation. Both publishers retry
quietly on a daemon outage; their next heartbeat recovers automatically.

## Configuration

`daemon/config.json` centralizes the Discord application ID, local port, idle
holds, and asset keys. The existing Discord application assets are:

| Source | Asset config | Default payload key |
|---|---|---|
| VS Code | `assets.vscode` | `vscode` |
| OpenCode | `assets.opencode` | `opencode` |
| Command Code | `assets.commandcode` | `commandcode` |

After changing it, restart the existing agent:

```bash
launchctl kickstart -k gui/$(id -u)/com.rich.discord-presence
```

## Privacy

Only safe metadata is published: source type, project/file basenames, language,
a raw model identifier sent locally for normalization, and an allowlisted
activity label. Discord receives the friendly model label and safe presence
fields only.

Never sent: prompts, todo/session titles, source code, file contents, command
arguments, credentials, API keys, or absolute filesystem paths. There is one
consistent presence representation; Devvy has no public/private mode.

## Troubleshooting

- Check the daemon: `curl -fsS http://127.0.0.1:17377/healthz`
- Check the agent: `launchctl print gui/$(id -u)/com.rich.discord-presence`
- Check logs: `daemon/.live-ipc/launchd.stderr.log` in the installed Devvy
  directory.
- Discord desktop must be running locally. If it is unavailable, Devvy retries
  its existing IPC connection without affecting publishers.
- For development run `node daemon/daemon.mjs`; set `PRESENCE_PORT` and
  `DISCORD_IPC_DIR` for isolated tests.

## Development and tests

Node.js is required for the daemon and test suite. From `daemon/`:

```bash
node --check daemon.mjs
node --check discord-ipc.mjs
node --check model-display.mjs
node test-model-display.mjs
./test-v2-presence.sh
for test in test-*.sh; do "$test"; done
for test in test-*.mjs; do node "$test"; done
```

Validate scripts with `bash -n install.sh scripts/package-release.sh` and
validate `daemon/config.json` with `node -e 'JSON.parse(require("fs").readFileSync("daemon/config.json"))'`.
Use `scripts/package-release.sh` to create the release archive; upload that
archive and the root `install.sh` manually to a future GitHub Release.

## Uninstall

```bash
launchctl bootout gui/$(id -u)/com.rich.discord-presence 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.rich.discord-presence.plist
rm -f ~/.config/opencode/plugins/discord-presence.ts
rm -f ~/.commandcode/mods/discord-presence.ts
rm -rf ~/.local/share/devvy       # only if installed from a release
```

For checkout installs, remove the checkout when no longer needed. Remove the
Devvy VSIX/extension from VS Code separately.

## License

MIT
