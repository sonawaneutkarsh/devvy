import { friendlyModelName } from "./model-display.mjs";

export const MODE_LABELS = new Set([
  "Thinking", "Editing", "Planning", "Running", "Reviewing", "Searching",
  "Waiting", "Waiting for prompt", "Idle",
]);
const MODE_ALIASES = new Map([
  ["thinking", "Thinking"],
  ["thinking...", "Thinking"],
  ["editing", "Editing"],
  ["editing code", "Editing"],
  ["planning", "Planning"],
  ["running", "Running"],
  ["running commands", "Running"],
  ["reviewing", "Reviewing"],
  ["reviewing changes", "Reviewing"],
  ["searching", "Searching"],
  ["searching code", "Searching"],
  ["reading files", "Searching"],
  ["waiting", "Waiting"],
  ["waiting for response", "Waiting"],
  ["waiting for prompt", "Waiting for prompt"],
  ["working on code", "Thinking"],
  ["idle", "Idle"],
  ["session error", "Idle"],
]);

const DEFAULT_VISIBILITY = {
  showModel: true,
  showActivity: true,
  showAgent: true,
  showProject: true,
  showFile: true,
  showLanguage: true,
  showBranch: false,
  showDirty: false,
};
const MODEL_FAMILY_PATTERN = /^(?:glm|gpt|llama|qwen|claude|gemini|mistral|deepseek|codex|kimi)\d*$/;
const MODEL_VARIANTS = new Set([
  "air", "base", "chat", "code", "coder", "flash", "haiku", "instruct", "large", "max",
  "mini", "nano", "nova", "opus", "pro", "reasoning", "sol", "sonnet", "small", "thinking",
  "turbo",
]);

export function presenceVisibility(config) {
  const value = config?.presence;
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ...DEFAULT_VISIBILITY };
  }
  return Object.fromEntries(Object.entries(DEFAULT_VISIBILITY).map(([key, fallback]) => [
    key, typeof value[key] === "boolean" ? value[key] : fallback,
  ]));
}

function clean(value) {
  return typeof value === "string"
    ? value.replace(/[\u0000-\u001f\u007f]/g, "").trim()
    : "";
}

export function safeBasename(value, max = 64) {
  const text = clean(value);
  if (!text) return "";
  const name = text.split(/[\\/]/).filter(Boolean).pop() || "";
  return name.length > max ? name.slice(0, max) : name;
}

export function safeLanguage(value) {
  const text = clean(value);
  return /^[A-Za-z][A-Za-z0-9+#._-]{0,31}$/.test(text) ? text : "";
}

export function safeBranch(value) {
  const text = clean(value);
  if (!text || text.startsWith("/") || text.startsWith("\\") || text.includes("..")) return "";
  return /^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$/.test(text) ? text : "";
}

export function safeModel(value) {
  const model = friendlyModelName(value);
  if (!model || model.length > 64 || /[\\/@`$=<>\n\r]/.test(model)) return "";
  if (!/^[A-Za-z0-9][A-Za-z0-9 .+_-]*$/.test(model)) return "";
  const tokens = model.toLowerCase().split(/\s+/);
  if (tokens.length > 6 || !(MODEL_FAMILY_PATTERN.test(tokens[0]) || /^o\d+$/.test(tokens[0]))) return "";
  // Every suffix must be a known model variant or a version token. This is a
  // classifier, not a formatting/keyword filter, so prompt prose is rejected.
  if (tokens.slice(1).some((token) => !MODEL_VARIANTS.has(token)
    && !/^\d+(?:\.\d+)*$/.test(token)
    && !/^v\d+(?:\.\d+)*$/.test(token)
    && !/^[a-z]\d+$/.test(token))) return "";
  return model;
}

export function safeMode(value, fallback = "Thinking") {
  const text = clean(value).toLowerCase();
  return MODE_ALIASES.get(text) || (MODE_LABELS.has(value) ? value : fallback);
}

// Retain the old export for isolated clients while making its output high-level.
export function safeActivity(value, fallback = "Thinking") {
  return safeMode(value, fallback);
}

export function defaultVisibility() {
  return { ...DEFAULT_VISIBILITY };
}

function timestamp(value) {
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : undefined;
}

function addAssets(out, key, text, assets, visibility) {
  if (!visibility.showAgent) return;
  const large = typeof assets?.[key] === "string" ? assets[key].trim() : "";
  if (/^[A-Za-z0-9_-]{1,64}$/.test(large)) {
    out.assets = { large_image: large, large_text: text };
  }
}

function setIdentity(out, project, model, agent, visibility) {
  const displayModel = visibility.showModel ? safeModel(model) : "";
  const displayProject = visibility.showProject ? safeBasename(project) : "";
  if (displayProject) out.details = displayProject;
  else if (visibility.showAgent) out.details = agent;
  return displayModel;
}

function setSafeMode(out, source, visibility, displayModel) {
  const mode = source.active
    ? safeMode(source.state?.mode ?? source.state?.activity, "Thinking")
    : safeMode(source.state?.mode ?? source.state?.activity, "Waiting for prompt");
  const parts = [];
  if (visibility.showActivity) parts.push(mode);
  if (displayModel) parts.push(displayModel);
  if (parts.length) out.state = parts.join(" • ");
}

export function buildDiscordActivity(source, visibility = defaultVisibility(), assets = {}) {
  if (!source?.state || !["opencode", "commandcode", "vscode"].includes(source.kind)) return null;
  const state = source.state;
  const out = {};
  if (source.kind === "opencode" || source.kind === "commandcode") {
    const agent = source.kind === "opencode" ? "OpenCode" : "Command Code";
    const displayModel = setIdentity(out, state.project, state.model, agent, visibility);
    setSafeMode(out, source, visibility, displayModel);
    const startedAt = visibility.showActivity && source.active && timestamp(state.startedAt);
    if (startedAt) out.timestamps = { start: startedAt };
    addAssets(out, source.kind, displayModel || out.details || agent, assets, visibility);
    return Object.keys(out).length ? out : null;
  }

  const project = visibility.showProject ? safeBasename(state.project) : "";
  if (project) out.details = project;
  else if (visibility.showAgent) out.details = "VS Code";
  const mode = safeMode(state.mode ?? state.activity, source.active ? "Editing" : "Waiting for prompt");
  const parts = [];
  if (visibility.showActivity) parts.push(mode);
  if (visibility.showLanguage) {
    const language = safeLanguage(state.language);
    if (language) parts.push(language);
  }
  if (parts.length) out.state = parts.join(" • ").slice(0, 128);
  const startedAt = visibility.showActivity && timestamp(state.startedAt);
  if (startedAt) out.timestamps = { start: startedAt };
  addAssets(out, "vscode", "VS Code", assets, visibility);
  return Object.keys(out).length ? out : null;
}
