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

// two sessions both busy
await hooks["chat.message"]({ sessionID: "s1", model: { providerID: "x", modelID: "a" } });
await hooks["chat.message"]({ sessionID: "s2", model: { providerID: "x", modelID: "b" } });
await new Promise((r) => setTimeout(r, 600));
console.log("both busy active:", captured[captured.length - 1].active);

// idle s1 only -> still busy because s2
await hooks.event({ event: { type: "session.idle", properties: { sessionID: "s1" } } });
await new Promise((r) => setTimeout(r, 600));
console.log("s1 idle, s2 busy active:", captured[captured.length - 1].active);

// idle s2 -> grace
await hooks.event({ event: { type: "session.idle", properties: { sessionID: "s2" } } });
await new Promise((r) => setTimeout(r, 600));
console.log("both idle immediately active:", captured[captured.length - 1].active);

await new Promise((r) => setTimeout(r, 16000));
console.log("both idle after grace active:", captured[captured.length - 1].active);

if (captured[captured.length - 1].active !== false) {
  console.log("FAIL: expected inactive after both idle + grace");
  process.exit(1);
}

console.log("PASS: multi-session status handled");
await hooks.dispose();
process.exit(0);
