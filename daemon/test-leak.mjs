import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pluginPath = path.join(__dirname, "..", "integrations", "opencode", "discord-presence.ts");
const { default: plugin } = await import(`file://${pluginPath}`);

let capturedCount = 0;
globalThis.fetch = async () => {
  capturedCount += 1;
  return { ok: true };
};

const input = {
  client: { app: { log: async () => {} } },
  directory: "/test/project",
  worktree: "/test/project",
};

const hooks = await plugin.server(input);

await hooks["chat.message"]({ sessionID: "s1", model: { providerID: "x", modelID: "y" } });
await new Promise((r) => setTimeout(r, 600));
const afterStart = capturedCount;
console.log("captures after start:", afterStart);

await hooks.dispose();
const afterDispose = capturedCount;
console.log("captures after dispose:", afterDispose);

await new Promise((r) => setTimeout(r, 6000));
const afterWait = capturedCount;
console.log("captures after 6s wait (should equal afterDispose):", afterWait);

if (afterWait !== afterDispose) {
  console.log("FAIL: heartbeat continued after dispose");
  process.exit(1);
}

console.log("PASS: timers stopped on dispose");
process.exit(0);
