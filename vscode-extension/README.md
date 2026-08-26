# Devvy for VS Code

Devvy gives your coding workflow one privacy-conscious Discord Rich Presence.
This extension publishes only high-level VS Code state to the local Devvy
daemon:

- Workspace name (basename only, never a full path)
- Editing or idle state
- Document language

Devvy is an independent open-source project by sonawaneutkarsh. It is not
affiliated with Microsoft, Visual Studio Code, Discord, or any AI provider.

## How It Works

Devvy is one part of a three-piece local system. This extension never talks to
Discord itself:

```text
VS Code ────────┐
OpenCode ───────┼─→ Devvy daemon (127.0.0.1:17377) ─→ Discord IPC ─→ Discord
Command Code ───┘
```

```text
VS Code
   │
   │ localhost HTTP (127.0.0.1:17377)
   ▼
Devvy daemon
   │
   │ Discord IPC
   ▼
Discord
```

### What this extension sends

The extension sends small structured updates to the local daemon only:

- Workspace/project name (folder basename, e.g. `my-project`)
- Document language ID (e.g. `typescript`)
- Editing/idle mode and timestamps needed for presence arbitration
- Active/focused flags so the daemon can arbitrate between apps

It does **not** send prompts, source code, file contents, file names,
filesystem paths, command arguments, terminal output, credentials, API keys,
tokens, or arbitrary tool output.

### What the daemon sends to Discord

Only sanitized, high-level presence metadata may be emitted: the project
basename, a high-level mode such as **Editing** or **Idle**, the language, and
elapsed time. State held by the local daemon is not automatically shown on
Discord; every value passes through the daemon's allowlists before display.

## Install

Install Devvy using the instructions in the
[Devvy repository](https://github.com/sonawaneutkarsh/devvy#install). The
installer includes the daemon and automatically installs this extension when
VS Code is available. Discord must be running for presence updates.

## Startup Behavior

The extension activates automatically after VS Code finishes starting up
(`onStartupFinished`). At startup and on a 5-second heartbeat it sends the
high-level state above to the local daemon. If the daemon is not running, the
extension stays quiet and retries; it logs nothing outside VS Code's own
output channels and performs no other work.

## Privacy

- No telemetry, analytics, or tracking of any kind
- No cloud service and no accounts
- No external network requests: communication is limited to HTTP PUT calls to
  the local Devvy daemon at `http://127.0.0.1:17377`
- The extension does not connect to Discord directly; the daemon owns the
  Discord IPC connection
- Only the documented VS Code metadata listed above leaves the editor window,
  and it only ever travels to your own computer's daemon loopback interface
- The daemon sanitizes everything before anything is shown on Discord

## License

MIT
