import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pluginPath = path.join(__dirname, "..", "integrations", "opencode", "discord-presence.ts");
const { default: plugin } = await import(`file://${pluginPath}`);

const captured = [];
globalThis.fetch = async (url, options) => {
  captured.push({
    url,
    method: options?.method,
    body: JSON.parse(options?.body),
  });
  return { ok: true };
};

const client = {
  app: {
    log: async () => {},
  },
};

const input = {
  client,
  directory: "/test/project",
  worktree: "/test/project",
};

function event(type, properties) {
  return { type, properties };
}

function findLast() {
  return captured[captured.length - 1];
}

async function settle(ms) {
  await new Promise((r) => setTimeout(r, ms));
}

const hooks = await plugin.server(input);

function scenario(name, fn) {
  captured.length = 0;
  console.log(`\n=== ${name} ===`);
  return fn();
}

await scenario("session created", async () => {
  await hooks.event({ event: event("session.created", {
    info: { id: "s1", title: "Use John's credentials in production" },
    prompt: "send the private source code",
  }) });
  await settle(600);
  const body = findLast()?.body;
  console.log(JSON.stringify(body));
  if (JSON.stringify(body).includes("credentials") || JSON.stringify(body).includes("private source")) {
    throw new Error("session data leaked into publisher state");
  }
});

await scenario("session status busy", async () => {
  await hooks.event({ event: event("session.status", { sessionID: "s1", status: { type: "busy" } }) });
  await settle(600);
  console.log(JSON.stringify(findLast()?.body));
  if (findLast()?.body?.state?.mode !== "Thinking") throw new Error("busy state was not high-level Thinking");
  if (findLast()?.body?.connected !== true) throw new Error("OpenCode connection flag missing");
});

await scenario("chat.message detects model", async () => {
  await hooks["chat.message"]({ sessionID: "s1", model: { providerID: "anthropic", modelID: "claude-sonnet-4-5" } });
  await settle(600);
  console.log(JSON.stringify(findLast()?.body));
});

await scenario("tool execute before", async () => {
  await hooks["tool.execute.before"]({
    tool: "edit",
    sessionID: "s1",
    args: { command: "cat /etc/passwd", source: "const token = 'secret'" },
  });
  await settle(600);
  const body = findLast()?.body;
  console.log(JSON.stringify(body));
  if (JSON.stringify(body).includes("passwd") || JSON.stringify(body).includes("secret")) {
    throw new Error("tool arguments leaked into publisher state");
  }
  if (body.state.mode !== "Editing") throw new Error("editing state was not high-level");
});

await scenario("file edited", async () => {
  await hooks.event({ event: event("file.edited", { file: "/abs/path/auth.ts" }) });
  await settle(600);
  console.log(JSON.stringify(findLast()?.body));
  if (findLast()?.body?.state?.mode !== "Editing") throw new Error("file edit state was not high-level");
});

await scenario("todo planning", async () => {
  await hooks.event({ event: event("todo.updated", {
    items: [{ title: "Use John's credentials to fix payment production" }],
  }) });
  await settle(600);
  const body = findLast()?.body;
  console.log(JSON.stringify(body));
  if (body.state.mode !== "Planning") throw new Error("planning state was not high-level");
  if (JSON.stringify(body).includes("credentials") || JSON.stringify(body).includes("payment")) {
    throw new Error("todo text leaked into publisher state");
  }
});

await scenario("session idle then grace", async () => {
  await hooks.event({ event: event("session.idle", { sessionID: "s1" }) });
  await settle(600);
  console.log("immediately after idle:", JSON.stringify(findLast()?.body));
  if (findLast()?.body?.state?.mode !== "Idle") throw new Error("idle state was not Idle");
  await settle(15000);
  console.log("after grace:", JSON.stringify(findLast()?.body));
});

await scenario("session error", async () => {
  await hooks.event({ event: event("session.error", { sessionID: "s1" }) });
  await settle(600);
  console.log(JSON.stringify(findLast()?.body));
});

await scenario("dispose", async () => {
  await hooks["chat.message"]({ sessionID: "s1", model: { providerID: "x", modelID: "y" } });
  await settle(600);
  await hooks.dispose();
  console.log("final:", JSON.stringify(findLast()?.body));
  console.log("active after dispose:", findLast()?.body?.active);
});

process.exit(0);
