import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let lastPayload;
const captured = [];
globalThis.fetch = async (url, options) => {
  const body = JSON.parse(options.body);
  captured.push(body);
  lastPayload = body;
  return { ok: true };
};

const handlers = new Map();
function emit(name, payload = { type: name }) {
  for (const cb of handlers.get(name) || []) cb(payload);
}

const mockCmd = {
  cwd: "/test/project",
  on(name, cb) {
    handlers.set(name, [...(handlers.get(name) || []), cb]);
    return { dispose() {} };
  },
};

const modPath = path.join(
  __dirname,
  "..",
  "integrations",
  "commandcode",
  "discord-presence.ts",
);
const { default: factory } = await import(`file://${modPath}`);
if (typeof factory !== "function") {
  console.log("FAIL: mod default export is not a function");
  process.exit(1);
}
factory(mockCmd);

async function settle(ms) {
  await new Promise((r) => setTimeout(r, ms));
}

function assert(cond, msg) {
  if (!cond) {
    console.log("FAIL: " + msg);
    console.log("last payload:", JSON.stringify(lastPayload));
    process.exit(1);
  }
}

// session start seeds an idle presence
emit("session_start");
await settle(600);
assert(lastPayload?.kind === "commandcode", "expected commandcode kind");
assert(lastPayload?.active === false, "expected idle at session start");
assert(lastPayload?.state?.project === "project", "project should be basename only");
assert(lastPayload?.state?.app === "Command Code", "app label should be Command Code");
assert(lastPayload?.connected === true, "connection flag should be true");
assert(
  !JSON.stringify(lastPayload?.state).includes("/Users/"),
  "absolute path leaked into state",
);

// run start marks active
captured.length = 0;
emit("run_start", { type: "run_start", sessionId: "s1" });
await settle(600);
assert(lastPayload?.active === true, "run_start should mark active");
assert(typeof lastPayload?.state?.startedAt === "number", "startedAt should be set");

// model_request_start records model (string)
captured.length = 0;
emit("model_request_start", { type: "model_request_start", model: "claude-sonnet-4-6" });
await settle(600);
assert(lastPayload?.state?.model === "claude-sonnet-4-6", "model string not captured");

// model as object is normalized
captured.length = 0;
emit("model_request_start", {
  type: "model_request_start",
  model: { modelID: "gpt-5.6-sol" },
});
await settle(600);
assert(lastPayload?.state?.model === "gpt-5.6-sol", "object model not normalized");

// tool_running sets a high-level mode
captured.length = 0;
emit("tool_running", { type: "tool_running", toolCallId: "t1", toolName: "edit_file", description: "edits X" });
await settle(600);
assert(lastPayload?.state?.mode === "Editing", "tool mode wrong");
assert(lastPayload?.active === true, "tool_running should keep active");

// run_end marks waiting and clears the transient mode
captured.length = 0;
emit("run_end", { type: "run_end", result: {} });
await settle(600);
assert(lastPayload?.active === false, "run_end should mark idle");
assert(lastPayload?.state?.mode === "Idle", "run_end should mark idle");

// privacy: no description, tool input, or command args leaked
const all = JSON.stringify(captured);
assert(!all.includes("edits X"), "tool description leaked");
assert(!all.includes("shell"), "unexpected tool detail leaked");

// session_shutdown clears timers and sends final idle
captured.length = 0;
emit("session_shutdown");
await settle(600);
assert(lastPayload?.active === false, "shutdown should send idle");
const before = captured.length;
await settle(6000);
assert(captured.length === before, "heartbeat kept running after session_shutdown");

console.log("PASS: Command Code mod exercised (metadata-only, timers stop)");
process.exit(0);
