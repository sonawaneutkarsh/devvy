const vscode = require("vscode");

const DAEMON_URL = "http://127.0.0.1:17377";
const HEARTBEAT_MS = 5000;
let stopPublisher;

function activate(context) {
  let active = false;
  let focused = false;
  let startedAt;
  let debounceTimer;
  let heartbeat;
  let disposed = false;

  function activeEditorInfo() {
    const editor = vscode.window.activeTextEditor;
    if (!editor) return undefined;
    const doc = editor.document;
    const folder = vscode.workspace.getWorkspaceFolder(doc.uri);
    return {
      language: doc.languageId,
      dirty: doc.isDirty,
      project: folder ? folder.name : undefined,
    };
  }

  function computeState() {
    const info = activeEditorInfo();
    return {
      app: "VS Code",
      project: info?.project,
      language: info?.language,
      editing: info?.dirty,
      mode: active ? "Editing" : "Idle",
      startedAt,
    };
  }

  async function send() {
    if (disposed) return;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 2000);
    const body = {
      sourceId: `vscode:${vscode.env.sessionId}`,
      kind: "vscode",
      connected: true,
      ts: Date.now(),
      active,
      focused,
      state: computeState(),
    };
    try {
      await fetch(`${DAEMON_URL}/state`, {
        method: "PUT",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
    } catch {
      // daemon may be restarting; next heartbeat retries
    } finally {
      clearTimeout(timeout);
    }
  }

  function scheduleSend() {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(send, 500);
  }

  function recomputeActive() {
    const editor = vscode.window.activeTextEditor;
    // An open editor keeps VS Code a valid fallback presence even when the
    // window is unfocused; losing focus must not clear the presence. The
    // daemon treats missing heartbeats (TTL) as "unavailable" instead.
    const shouldBeActive = !!editor;

    active = shouldBeActive;
    focused = vscode.window.state.focused;
    if (shouldBeActive) {
      if (!startedAt) startedAt = Date.now();
    } else {
      startedAt = undefined;
    }
  }

  async function refresh() {
    recomputeActive();
    await send();
  }

  context.subscriptions.push(
    vscode.window.onDidChangeActiveTextEditor(refresh),
    vscode.window.onDidChangeWindowState(refresh),
    vscode.workspace.onDidChangeWorkspaceFolders(refresh),
    vscode.workspace.onDidOpenTextDocument((doc) => {
      if (doc.uri.scheme === "file") scheduleSend();
    }),
    vscode.workspace.onDidChangeTextDocument(() => scheduleSend()),
  );

  heartbeat = setInterval(send, HEARTBEAT_MS);
  context.subscriptions.push({
    dispose() {
      disposed = true;
      if (heartbeat) clearInterval(heartbeat);
      if (debounceTimer) clearTimeout(debounceTimer);
    },
  });

  stopPublisher = async () => {
    if (disposed) return;
    active = false;
    focused = false;
    // Give the daemon an explicit inactive state; if it is unavailable,
    // TTL performs the same cleanup and the error remains intentionally quiet.
    await send();
    disposed = true;
    if (heartbeat) clearInterval(heartbeat);
    if (debounceTimer) clearTimeout(debounceTimer);
  };

  void refresh();
}

async function deactivate() {
  await stopPublisher?.();
  stopPublisher = undefined;
}

module.exports = { activate, deactivate };
