import { createRequire } from "node:module";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

// Mock the vscode module before loading the extension.
const mockVscode = (() => {
  const listeners = new Map();
  const state = {
    focused: false,
    activeEditor: undefined,
    workspaceFolders: [],
    gitApi: undefined,
    gitActive: false,
  };

  function emit(name, ...args) {
    for (const cb of listeners.get(name) || []) cb(...args);
  }

  const disposables = [];
  const context = {
    subscriptions: {
      push(...items) {
        disposables.push(...items);
      },
    },
  };

  return {
    mock: {
      state,
      emit,
      disposables,
      context,
      getLastPayload() {
        return lastPayload;
      },
    },
    window: {
      state: {
        get focused() {
          return state.focused;
        },
      },
      get activeTextEditor() {
        return state.activeEditor;
      },
      onDidChangeActiveTextEditor(cb) {
        listeners.set("onDidChangeActiveTextEditor", [
          ...(listeners.get("onDidChangeActiveTextEditor") || []),
          cb,
        ]);
        return { dispose() {} };
      },
      onDidChangeWindowState(cb) {
        listeners.set("onDidChangeWindowState", [
          ...(listeners.get("onDidChangeWindowState") || []),
          cb,
        ]);
        return { dispose() {} };
      },
    },
    workspace: {
      getWorkspaceFolder(uri) {
        if (!uri || !state.workspaceFolders.length) return undefined;
        return state.workspaceFolders[0];
      },
      onDidChangeWorkspaceFolders(cb) {
        return { dispose() {} };
      },
      onDidOpenTextDocument(cb) {
        return { dispose() {} };
      },
      onDidChangeTextDocument(cb) {
        return { dispose() {} };
      },
    },
    extensions: {
      getExtension(id) {
        if (id === "vscode.git") {
          return {
            isActive: state.gitActive,
            exports: state.gitApi ? { getAPI: () => state.gitApi } : undefined,
          };
        }
        return undefined;
      },
      onDidChange(cb) {
        return { dispose() {} };
      },
    },
    env: {
      sessionId: "test-session-id",
    },
  };
})();

let lastPayload;

// Privacy regression guard: every payload the extension ever sends must stay
// high-level. Absolute paths, workspace-internal paths, and unsafe fields are
// rejected deterministically on every capture, not just at final assertions.
const FORBIDDEN_SUBSTRINGS = [
  "/test/project/src/Hero.tsx",
  "/test/project",
  "/Users/",
  "C:\\Users\\",
];
const FORBIDDEN_FIELDS = ["editing", "dirty", "path", "file", "branch"];

function assertSafePayload(body) {
  const serialized = JSON.stringify(body);
  for (const banned of FORBIDDEN_SUBSTRINGS) {
    if (serialized.includes(banned)) {
      console.log(`FAIL: extension payload leaked forbidden text: ${banned}`);
      process.exit(1);
    }
  }
  for (const field of FORBIDDEN_FIELDS) {
    if (field in body.state) {
      console.log(`FAIL: extension payload contains unsafe field: ${field}`);
      process.exit(1);
    }
  }
}

globalThis.fetch = async (url, options) => {
  lastPayload = JSON.parse(options.body);
  assertSafePayload(lastPayload);
  return { ok: true };
};

// Load extension.js with our mock vscode.
const extensionPath = path.join(__dirname, "..", "vscode-extension", "extension.js");
const extensionCode = fs.readFileSync(extensionPath, "utf8");

// The extension uses require("vscode"); patch require for this module only.
const originalResolve = require.resolve;
require.resolve = (id) => (id === "vscode" ? "/mock/vscode" : originalResolve(id));

// Create a fake module using Function constructor so require("vscode") resolves
// via our patched resolve. Simpler: write a temporary mock and use NODE_PATH.
// Instead, we directly evaluate the extension in a CommonJS-like context.
const moduleObj = { exports: {} };
const wrapper = new Function(
  "require",
  "module",
  "exports",
  "__filename",
  "__dirname",
  extensionCode,
);

const patchedRequire = (id) => {
  if (id === "vscode") return mockVscode;
  return require(id);
};

wrapper(patchedRequire, moduleObj, moduleObj.exports, extensionPath, path.dirname(extensionPath));

const { activate, deactivate } = moduleObj.exports;

console.log("=== activate: no focus, no editor ===");
activate(mockVscode.mock.context);
await new Promise((r) => setTimeout(r, 600));
console.log("payload:", JSON.stringify(lastPayload));
if (lastPayload.connected !== true || lastPayload.state.mode !== "Idle") {
  console.log("FAIL: idle VS Code presence was not marked connected/Idle");
  process.exit(1);
}

console.log("=== focus + editor with language/project ===");
mockVscode.mock.state.focused = true;
mockVscode.mock.state.activeEditor = {
  document: {
    uri: { fsPath: "/test/project/src/Hero.tsx", scheme: "file" },
    languageId: "typescript",
    isDirty: false,
  },
};
mockVscode.mock.state.workspaceFolders = [
  { name: "portfolio", uri: { fsPath: "/test/project" } },
];
mockVscode.mock.emit("onDidChangeActiveTextEditor");
await new Promise((r) => setTimeout(r, 600));
console.log("payload:", JSON.stringify(lastPayload));

console.log("=== dirty/unsaved state ===");
mockVscode.mock.state.activeEditor.document.isDirty = true;
mockVscode.mock.emit("onDidChangeTextDocument");
await new Promise((r) => setTimeout(r, 600));
console.log("payload:", JSON.stringify(lastPayload));

console.log("=== git branch detection ===");
mockVscode.mock.state.gitActive = true;
mockVscode.mock.state.gitApi = {
  repositories: [
    {
      rootUri: { fsPath: "/test/project" },
      state: { HEAD: { name: "feature/auth" } },
    },
  ],
};
mockVscode.mock.emit("onDidChangeActiveTextEditor");
await new Promise((r) => setTimeout(r, 600));
console.log("payload:", JSON.stringify(lastPayload));

console.log("=== unfocus (presence must stay: active=true, focused=false) ===");
mockVscode.mock.state.focused = false;
mockVscode.mock.emit("onDidChangeWindowState");
await new Promise((r) => setTimeout(r, 600));
console.log("payload:", JSON.stringify(lastPayload));
if (lastPayload.active !== true || lastPayload.focused !== false) {
  console.log("FAIL: unfocused window lost presence eligibility");
  process.exit(1);
}
if (lastPayload.state.mode !== "Editing" || lastPayload.connected !== true || "path" in lastPayload.state || "file" in lastPayload.state || "branch" in lastPayload.state || "editing" in lastPayload.state || "dirty" in lastPayload.state) {
  console.log("FAIL: VS Code payload was not reduced to safe high-level state");
  process.exit(1);
}
if (lastPayload.state.startedAt === undefined) {
  console.log("FAIL: startedAt reset on unfocus");
  process.exit(1);
}

console.log("=== refocus ===");
mockVscode.mock.state.focused = true;
mockVscode.mock.emit("onDidChangeWindowState");
await new Promise((r) => setTimeout(r, 600));
console.log("payload:", JSON.stringify(lastPayload));
if (lastPayload.active !== true || lastPayload.focused !== true) {
  console.log("FAIL: refocus did not report focused");
  process.exit(1);
}

console.log("=== editor closed (unfocused window still open) ===");
mockVscode.mock.state.focused = false;
mockVscode.mock.state.activeEditor = undefined;
mockVscode.mock.emit("onDidChangeActiveTextEditor");
await new Promise((r) => setTimeout(r, 600));
console.log("payload:", JSON.stringify(lastPayload));
if (lastPayload.active !== false || lastPayload.focused !== false) {
  console.log("FAIL: closed editor should report inactive");
  process.exit(1);
}

console.log("=== deactivate ===");
mockVscode.mock.disposables.forEach((d) => d.dispose?.());
console.log("PASS: VS Code extension source exercised");
process.exit(0);
