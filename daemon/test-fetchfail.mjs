import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pluginPath = path.join(__dirname, "..", "integrations", "opencode", "discord-presence.ts");
const { default: plugin } = await import(`file://${pluginPath}`);

let failFetch = true;
let fetchCount = 0;
globalThis.fetch = async () => {
  fetchCount += 1;
  if (failFetch) throw new Error("daemon down");
  return { ok: true };
};

const input = {
  client: { app: { log: async () => {} } },
  directory: "/test/project",
};

const hooks = await plugin.server(input);

await hooks["chat.message"]({ sessionID: "s1", model: { providerID: "x", modelID: "y" } });
await new Promise((r) => setTimeout(r, 600));
console.log("fetch attempted while down:", fetchCount > 0);

// daemon comes back
failFetch = false;
await new Promise((r) => setTimeout(r, 5200));
console.log("fetch recovered count:", fetchCount);

await hooks.dispose();
console.log("PASS: fetch failure handled without crash");
process.exit(0);
