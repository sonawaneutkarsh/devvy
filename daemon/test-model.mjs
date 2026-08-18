import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pluginPath = path.join(__dirname, "..", "integrations", "opencode", "discord-presence.ts");
const { default: plugin } = await import(`file://${pluginPath}`);

const captured = [];
globalThis.fetch = async (url, options) => {
  captured.push(JSON.parse(options.body));
  return { ok: true };
};

const input = {
  client: { app: { log: async () => {} } },
  directory: "/test/project",
};

const hooks = await plugin.server(input);

function modelCheck(providerID, modelID) {
  return new Promise(async (resolve) => {
    captured.length = 0;
    await hooks["chat.message"]({ sessionID: "m1", model: { providerID, modelID } });
    await new Promise((r) => setTimeout(r, 600));
    resolve(captured[captured.length - 1].state.model);
  });
}

const cases = [
  ["anthropic", "claude-sonnet-4-5"],
  ["opencode-go", "kimi-k3"],
  ["x", "x/model-with.special+chars"],
];

for (const [p, m] of cases) {
  const result = await modelCheck(p, m);
  console.log(`${p}/${m} -> ${result}`);
}

// The current OpenCode SDK's authoritative pre-request hook uses model.id.
captured.length = 0;
await hooks["chat.params"]({
  sessionID: "luna-session",
  model: { providerID: "openai", id: "gpt-5.6-luna" },
}, {});
await new Promise((r) => setTimeout(r, 600));
const selectedModelBody = captured[captured.length - 1];
console.log("chat.params model:", selectedModelBody.state.model);
if (selectedModelBody.state.model !== "gpt-5.6-luna") {
  console.log("FAIL: authoritative chat.params model was not captured");
  process.exit(1);
}
if (JSON.stringify(selectedModelBody).includes("prompt")
  || JSON.stringify(selectedModelBody).includes("task")
  || JSON.stringify(selectedModelBody).includes("/test/project")) {
  console.log("FAIL: sensitive data leaked with model state");
  process.exit(1);
}

// privacy: file paths and file names are not sent to the daemon
captured.length = 0;
await hooks.event({ event: { type: "file.edited", properties: { file: "/test/project/src/auth.ts" } } });
await hooks["chat.message"]({ sessionID: "p1", model: { providerID: "x", modelID: "y" } });
await new Promise((r) => setTimeout(r, 600));
const body = captured[captured.length - 1];
console.log("state:", JSON.stringify(body.state));
if ("file" in body.state || JSON.stringify(body.state).includes("/test/project")) {
  console.log("FAIL: file path leaked");
  process.exit(1);
}
if (body.state.mode !== "Editing") {
  console.log("FAIL: editing mode was not propagated");
  process.exit(1);
}

console.log("PASS: model detection and privacy checks");
await hooks.dispose();
process.exit(0);
