# Devvy

[![CI](https://github.com/sonawaneutkarsh/devvy/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/sonawaneutkarsh/devvy/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/sonawaneutkarsh/devvy)](https://github.com/sonawaneutkarsh/devvy/releases/latest)

Devvy gives your coding workflow one clean, privacy-conscious Discord Rich
Presence. It shows what kind of work is happening without showing the work
itself.

## Install

Discord must be running. Devvy installs its own runtime and manages the
background daemon, so you do not need Node.js, npm, Homebrew, Python, a VSIX,
a LaunchAgent, or Discord RPC set up separately.

### macOS

Run this in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/sonawaneutkarsh/devvy/main/install.sh | bash
```

The installer downloads the [latest release](https://github.com/sonawaneutkarsh/devvy/releases/latest)
payload for your Mac (Apple silicon or Intel), verifies its SHA-256 checksum,
and then:

- starts the background service at login;
- installs the VS Code extension, even without a `code` command in your PATH;
- installs the OpenCode and Command Code integrations when those apps are
  available.

Reload VS Code, open VS Code, OpenCode, or Command Code, and Devvy appears on
Discord.

### Windows (not released yet)

Windows x64 support is in `main` but is **not in a published release yet**.
The current releases (v4.0.x) contain macOS payloads only.
`devvy-windows-x86_64.zip` ships with the next release (v4.1.0). Until then,
build the payload from source on macOS, Linux, or WSL:

```bash
npm ci
(cd vscode-extension && npx --no-install vsce package --out "../devvy-$(../scripts/version.sh).vsix")
./scripts/package-windows-release.sh
```

Copy `devvy-windows-x86_64.zip` to the Windows PC, extract it, and run from
the extracted folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\devvy\windows\install.ps1 -SourceDir .\devvy
```

The installer copies Devvy to `%LOCALAPPDATA%\Devvy`, starts it at login with
a scheduled task, and installs the VS Code extension when VS Code is
available. If VS Code is not installed, installation still succeeds and
OpenCode or Command Code can use the daemon.

## What It Looks Like

![Devvy Discord Rich Presence preview](docs/images/discord-presence.png)

This is a real Devvy v4 Discord presence: the project, high-level state, and
detected model are visible without exposing the task itself.

## Why Devvy?

Devvy makes your presence useful at a glance. Friends can see that you are
thinking, editing, planning, reviewing, or waiting, along with the project you
are in and the AI model when it is reliably known.

It does not turn your Discord status into a transcript of your work.

## Supported Apps

- **VS Code** shows the workspace and high-level editor state.
- **OpenCode** shows the project, high-level agent state, and detected model.
- **Command Code** shows the project, high-level run state, and detected model.

## What Devvy Shows

Depending on the app and available information, Discord can show:

- Project name, using the workspace basename only
- High-level state such as **Thinking**, **Editing**, **Planning**, **Running**,
  **Reviewing**, **Searching**, **Waiting**, or **Idle**
- AI model name when the integration can reliably identify it
- A small amount of safe editor context, such as language

The display stays concise. A typical presence looks like:

```text
Devvy
Thinking • GPT 5.6
```

The exact layout depends on the active app and available model information.

## Privacy

Devvy intentionally shows only high-level context:

- Project name
- Current mode or activity
- AI model when available

Devvy intentionally does **not** show:

- Prompts or AI responses
- Source code or file contents
- Task descriptions or arbitrary commands
- Private filesystem paths
- Credentials, tokens, or secrets

Everything stays on your computer. VS Code, OpenCode, and Command Code send small
structured updates to the local Devvy daemon at `127.0.0.1:17377`. The daemon
is the only component that communicates with Discord.

## After Installation

Usually, nothing else is required. Reload VS Code after installation so the
extension starts, then use one of the supported coding apps. Devvy starts and
restarts itself in the background.

If VS Code is installed, Devvy looks for its bundled CLI directly inside the
application, so you do not need to enable the `code` command in PATH. If the
VS Code application is incomplete and its bundled CLI cannot be found, the
installer stops with a clear error instead of claiming the extension was
installed.

## Uninstall

```bash
~/.local/share/devvy/uninstall.sh
```

On Windows, run `uninstall.ps1` from `%LOCALAPPDATA%\Devvy`.

This removes Devvy's daemon, isolated runtime, logs, LaunchAgent, integrations,
and Devvy VS Code extension. It does not remove unrelated LaunchAgents or
extensions.

## For Developers

The daemon owns Discord IPC. Integrations only publish safe structured state to
the loopback HTTP endpoint, and the daemon arbitrates OpenCode, Command Code,
and VS Code (in that priority order) before creating one Discord activity:

```text
VS Code extension ──┐
OpenCode plugin ────┼─→ Devvy daemon (127.0.0.1:17377) ─→ Discord IPC ─→ Discord
Command Code mod ───┘
```

Run the test suite from a clone with Node.js 22.18 or newer (the `.ts`
integrations load through Node's built-in type stripping):

```bash
npm test
```

Devvy has **26 test scripts, all run in CI**: 22 in `daemon/` (unit tests plus
integration tests that start the real daemon against a mock Discord IPC
server), 1 Windows helper test, 1 VS Code CLI discovery test, and 2
release-payload checks. `npm test` runs the first 24; CI also builds and
checks the VSIX and the macOS and Windows payloads.

Releases are published by GitHub Actions only after CI passes on the tagged
commit. See [docs/RELEASING.md](docs/RELEASING.md).

## License

MIT
