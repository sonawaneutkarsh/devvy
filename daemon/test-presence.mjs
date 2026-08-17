import assert from "node:assert/strict";
import {
  buildDiscordActivity,
  defaultVisibility,
  presenceVisibility,
  safeActivity,
  safeBasename,
  safeBranch,
  safeLanguage,
  safeModel,
} from "./presence.mjs";

const source = {
  kind: "opencode",
  active: true,
  state: {
    model: "zai-org/GLM-5.3",
    activity: "Editing code",
    project: "/private/project",
    file: "/private/project/src/auth.ts",
    language: "typescript",
    branch: "feature/auth",
    editing: true,
    startedAt: 100,
  },
};

assert.deepEqual(presenceVisibility(undefined), defaultVisibility());
assert.equal(presenceVisibility({ presence: { showFile: false, showDirty: "yes" } }).showFile, false);
assert.equal(presenceVisibility({ presence: { showDirty: "yes" } }).showDirty, false);
assert.equal(presenceVisibility({ presence: null }).showProject, true);

assert.equal(safeActivity("Editing code"), "Editing code");
assert.equal(safeActivity("Thinking"), "Thinking...");
assert.equal(safeActivity("Implement OAuth with credentials"), "Working on code");
assert.equal(safeBasename("/private/project/src/auth.ts"), "auth.ts");
assert.equal(safeLanguage("typescript"), "typescript");
assert.equal(safeLanguage("cat /etc/passwd"), "");
assert.equal(safeBranch("feature/auth"), "feature/auth");
assert.equal(safeBranch("/Users/private"), "");
assert.equal(safeModel("zai-org/GLM-5.3"), "GLM 5.3");
assert.equal(safeModel("openai/o1"), "O1");
assert.equal(safeModel("qwen/qwen3"), "Qwen3");
for (const unsafe of [
  "Implement OAuth authentication using John's credentials",
  "token=abc123",
  "rm -rf /private/project",
  "console.log(sourceCode)",
  "123456",
  "Implement OAuth 2",
  "Use John's production credentials 2",
  "Deploy payment API 2",
  "Implement GPT integration 2",
]) assert.equal(safeModel(unsafe), "");

const activity = buildDiscordActivity(source, defaultVisibility(), {
  opencode: "opencode",
});
assert.deepEqual(activity, {
  details: "GLM 5.3",
  state: "Editing code",
  timestamps: { start: 100 },
  assets: { large_image: "opencode", large_text: "GLM 5.3" },
});

const unsafeActivity = buildDiscordActivity({
  kind: "opencode",
  active: true,
  state: {
    model: "Use John's credentials in production",
    activity: "Run `cat /etc/passwd` with token=abc123",
  },
}, defaultVisibility(), { opencode: "opencode" });
assert.equal(unsafeActivity.details, "OpenCode");
assert.equal(unsafeActivity.state, "Thinking...");

assert.equal(buildDiscordActivity(source, { ...defaultVisibility(), showModel: false }).details, "OpenCode");
assert.equal(buildDiscordActivity(source, { ...defaultVisibility(), showActivity: false }).state, undefined);
assert.equal(buildDiscordActivity(source, { ...defaultVisibility(), showAgent: false }).assets, undefined);

const vscodeDefaults = {
  kind: "vscode",
  active: true,
  state: {
    project: "/private/project",
    file: "/private/project/src/auth.ts",
    language: "typescript",
    branch: "feature/auth",
    editing: true,
    startedAt: 100,
  },
};
assert.equal(buildDiscordActivity(vscodeDefaults, { ...defaultVisibility(), showProject: false }).details, "VS Code");
assert.equal(buildDiscordActivity(vscodeDefaults, { ...defaultVisibility(), showFile: false }).state, "typescript");
assert.equal(buildDiscordActivity(vscodeDefaults, { ...defaultVisibility(), showLanguage: false }).state, "auth.ts");
assert.equal(buildDiscordActivity({ ...vscodeDefaults, state: { ...vscodeDefaults.state, language: undefined } }, defaultVisibility()).state, "auth.ts · Editing");
assert.equal(buildDiscordActivity({ ...vscodeDefaults, state: { ...vscodeDefaults.state, language: "cat /etc/passwd" } }, defaultVisibility()).state, "auth.ts · Editing");
assert.equal(buildDiscordActivity({ ...vscodeDefaults, state: { ...vscodeDefaults.state, language: undefined } }, { ...defaultVisibility(), showLanguage: false }).state, "auth.ts");
assert.equal(buildDiscordActivity(vscodeDefaults, { ...defaultVisibility(), showBranch: true }).state.includes("Branch: feature/auth"), true);
assert.equal(buildDiscordActivity(vscodeDefaults, { ...defaultVisibility(), showDirty: true }).state.includes("Unsaved changes"), true);

const hidden = buildDiscordActivity(source, {
  ...defaultVisibility(),
  showModel: false,
  showActivity: false,
  showAgent: false,
  showProject: false,
  showFile: false,
  showLanguage: false,
  showBranch: false,
  showDirty: false,
}, { opencode: "opencode" });
assert.equal(hidden, null);
assert.equal(buildDiscordActivity(vscodeDefaults, {
  showModel: false,
  showActivity: false,
  showAgent: false,
  showProject: false,
  showFile: false,
  showLanguage: false,
  showBranch: false,
  showDirty: false,
}, { vscode: "vscode" }), null);

const vscode = buildDiscordActivity(vscodeDefaults, {
  ...defaultVisibility(),
  showBranch: true,
  showDirty: true,
}, { vscode: "vscode" });
assert.equal(vscode.details, "project");
assert.equal(vscode.state, "auth.ts · typescript · Branch: feature/auth · Unsaved changes");

console.log("PASS: presence defaults, toggles, allowlist, and final payload privacy");
