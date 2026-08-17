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

// Start busy
await hooks["chat.message"]({ sessionID: "s1", model: { providerID: "x", modelID: "y" } });
await new Promise((r) => setTimeout(r, 600));

// Go idle
await hooks.event({ event: { type: "session.idle", properties: { sessionID: "s1" } } });
await new Promise((r) => setTimeout(r, 600));
console.log("after idle, active:", captured[captured.length - 1].active);

// Re-busy after 5s (within 15s grace)
await new Promise((r) => setTimeout(r, 5000));
await hooks["chat.message"]({ sessionID: "s1", model: { providerID: "x", modelID: "y" } });
await new Promise((r) => setTimeout(r, 600));
console.log("after re-busy, active:", captured[captured.length - 1].active);

// Wait past what would have been the original grace timer (15s)
await new Promise((r) => setTimeout(r, 16000));
console.log("after 16s, active:", captured[captured.length - 1].active);

if (captured[captured.length - 1].active !== true) {
  console.log("FAIL: presence cleared despite re-busy during grace");
  process.exit(1);
}

console.log("PASS: grace re-busy race handled");
await hooks.dispose();
process.exit(0);
