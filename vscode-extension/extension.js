const vscode = require("vscode");

const DAEMON_URL = "http://127.0.0.1:17377";
const HEARTBEAT_MS = 5000;
let stopPublisher;

function basename(p) {
  if (!p) return undefined;
  const parts = String(p).split(/[\\/]/);
  return parts[parts.length - 1] || undefined;
}

function activate(context) {
  let active = false;
  let focused = false;
  let startedAt;
  let debounceTimer;
  let heartbeat;
  let currentRepo;
  let disposed = false;

  function activeEditorInfo() {
    const editor = vscode.window.activeTextEditor;
    if (!editor) return undefined;
    const doc = editor.document;
    const folder = vscode.workspace.getWorkspaceFolder(doc.uri);
    return {
      file: basename(doc.uri.fsPath),
      path: doc.uri.fsPath,
      language: doc.languageId,
      dirty: doc.isDirty,
      project: folder ? folder.name : undefined,
      projectPath: folder ? folder.uri.fsPath : undefined,
    };
  }

  function findRepo(api, info) {
    if (!api || !info) return undefined;
    for (const repo of api.repositories || []) {
      const root = repo.rootUri?.fsPath;
      if (!root) continue;
      if (info.path.startsWith(root)) return repo;
    }
    return undefined;
  }

  function branchOf(repo) {
    return repo?.state?.HEAD?.name || undefined;
  }

  function computeState() {
    const info = activeEditorInfo();
    const branch = currentRepo ? branchOf(currentRepo) : undefined;
    return {
      app: "VS Code",
      project: info?.project,
      file: info?.file,
      language: info?.language,
      branch,
      editing: info?.dirty,
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

  function refreshRepo() {
    const info = activeEditorInfo();
    const gitExt = vscode.extensions.getExtension("vscode.git");
    if (!gitExt || !gitExt.isActive) {
      currentRepo = undefined;
      return;
    }
    const api = gitExt.exports?.getAPI?.(1);
    currentRepo = findRepo(api, info);
  }

  async function refresh() {
    recomputeActive();
    refreshRepo();
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

  context.subscriptions.push(
    vscode.extensions.onDidChange(() => refresh()),
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
