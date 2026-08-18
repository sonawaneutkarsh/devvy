import assert from "node:assert/strict";
import {
  buildDiscordActivity,
  defaultVisibility,
  presenceVisibility,
  safeActivity,
  safeBasename,
  safeLanguage,
  safeMode,
  safeModel,
} from "./presence.mjs";

const visibility = defaultVisibility();
const source = {
  kind: "opencode",
  active: true,
  state: {
    model: "zai-org/GLM-5.3",
    mode: "Thinking",
    project: "/private/project",
    file: "/private/project/src/auth.ts",
    branch: "feature/auth",
    startedAt: 100,
  },
};

assert.deepEqual(presenceVisibility(undefined), visibility);
assert.equal(presenceVisibility({ presence: { showFile: false, showDirty: "yes" } }).showProject, true);
assert.equal(safeBasename("/private/project/src/auth.ts"), "auth.ts");
assert.equal(safeBasename("/private/project"), "project");
assert.equal(safeLanguage("typescript"), "typescript");
assert.equal(safeLanguage("cat /etc/passwd"), "");
assert.equal(safeModel("zai-org/GLM-5.3"), "GLM 5.3");
assert.equal(safeModel("openai/gpt-5.6"), "GPT 5.6");
assert.equal(safeModel("openai/gpt-5.6-luna"), "GPT 5.6 Luna");
assert.equal(safeModel("Implement OAuth using John's credentials"), "");

for (const [input, expected] of [
  ["Thinking...", "Thinking"],
  ["Editing code", "Editing"],
  ["Planning", "Planning"],
  ["Running commands", "Running"],
  ["Reviewing changes", "Reviewing"],
  ["Waiting for response", "Waiting"],
  ["Waiting for prompt", "Waiting for prompt"],
  ["Idle", "Idle"],
]) assert.equal(safeMode(input), expected);
assert.equal(safeMode("Implement authentication with John's credentials"), "Thinking");
assert.equal(safeActivity("Editing code"), "Editing");

const activity = buildDiscordActivity(source, visibility, { opencode: "opencode" });
assert.deepEqual(activity, {
  details: "project",
  state: "Thinking • GLM 5.3",
  timestamps: { start: 100 },
  assets: { large_image: "opencode", large_text: "GLM 5.3" },
});
assert(!JSON.stringify(activity).includes("/private/project"));
assert(!JSON.stringify(activity).includes("auth.ts"));
assert(!JSON.stringify(activity).includes("feature/auth"));

for (const mode of ["Editing", "Planning", "Running", "Reviewing"]) {
  const result = buildDiscordActivity({ ...source, state: { ...source.state, mode } }, visibility);
  assert.equal(result.state, `${mode} • GLM 5.3`);
}

const waiting = buildDiscordActivity({
  ...source,
  active: false,
  state: { ...source.state, mode: undefined },
}, visibility);
assert.equal(waiting.details, "project");
assert.equal(waiting.state, "Idle • GLM 5.3");

const unknownModel = buildDiscordActivity({
  ...source,
  state: { ...source.state, model: "Use John's production credentials" },
}, visibility);
assert.equal(unknownModel.details, "project");
assert.equal(unknownModel.state, "Thinking");
assert(!JSON.stringify(unknownModel).includes("credentials"));

const luna = buildDiscordActivity({
  ...source,
  state: { ...source.state, model: "openai/gpt-5.6-luna", mode: "Thinking" },
}, visibility);
assert.equal(luna.state, "Thinking • GPT 5.6 Luna");

const promptState = buildDiscordActivity({
  ...source,
  state: { ...source.state, mode: "Fix payment system using token=abc123" },
}, visibility);
assert.equal(promptState.state, "Thinking • GLM 5.3");
assert(!JSON.stringify(promptState).includes("payment"));
assert(!JSON.stringify(promptState).includes("token"));

const vscode = buildDiscordActivity({
  kind: "vscode",
  active: true,
  state: {
    project: "/private/project",
    file: "/private/project/src/auth.ts",
    language: "typescript",
    mode: "Editing",
    branch: "feature/auth",
    editing: true,
    startedAt: 100,
  },
}, visibility, { vscode: "vscode" });
assert.deepEqual(vscode, {
  details: "project",
  state: "Editing • typescript",
  timestamps: { start: 100 },
  assets: { large_image: "vscode", large_text: "VS Code" },
});
assert(!JSON.stringify(vscode).includes("/private/project"));
assert(!JSON.stringify(vscode).includes("auth.ts"));
assert(!JSON.stringify(vscode).includes("feature/auth"));

assert.equal(buildDiscordActivity({
  kind: "vscode",
  active: false,
  state: { project: "/private/project" },
}, visibility).state, "Idle");
assert.equal(buildDiscordActivity(source, { ...visibility, showModel: false }).state, "Thinking");
assert.equal(buildDiscordActivity(source, { ...visibility, showProject: false }).details, "OpenCode");
assert.equal(buildDiscordActivity(source, {
  ...visibility,
  showModel: false,
  showActivity: false,
  showAgent: false,
  showProject: false,
}, {}), null);

console.log("PASS: high-level modes, project basenames, model allowlist, and privacy");
