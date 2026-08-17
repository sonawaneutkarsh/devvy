import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { DiscordIpc } from "./discord-ipc.mjs";
import { compareWithinKind } from "./arbitration.mjs";
import {
  presenceVisibility,
  buildDiscordActivity,
} from "./presence.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const config = JSON.parse(fs.readFileSync(path.join(__dirname, "config.json"), "utf8"));
const PORT = process.env.PRESENCE_PORT ? Number(process.env.PRESENCE_PORT) : (config.port ?? 17377);
const HOST = "127.0.0.1";
const TTL_MS = 15000, SWEEP_MS = 2000, MIN_IPC_INTERVAL_MS = 2000;
const IDLE_TIMEOUTS = {
  opencode: config.opencodeIdleTimeoutMs ?? 15000,
  commandcode: config.commandcodeIdleTimeoutMs ?? 15000,
  vscode: config.vscodeIdleTimeoutMs ?? 10000,
};
const ASSETS = config.assets && typeof config.assets === "object" ? config.assets : {};
const VISIBILITY = presenceVisibility(config);

function log(message) { process.stdout.write(`[${new Date().toISOString()}] ${message}\n`); }
function sourceKey(source) {
  // lastSeen, lastActiveAt, and lastFocusedAt deliberately do not belong here:
  // heartbeat-only updates must not cause Discord churn or arbitration changes.
  return JSON.stringify([source.sourceId, source.active, source.focused, source.state]);
}

const sources = new Map();
let lastEffectiveKey = null, lastIpcAt = 0, flushTimer;

function effectiveSource() {
  const now = Date.now();
  const chosen = { opencode: null, commandcode: null, vscode: null };
  for (const source of sources.values()) {
    if (!(source.active || now - source.lastActiveAt < IDLE_TIMEOUTS[source.kind])) continue;
    if (compareWithinKind(source, chosen[source.kind])) chosen[source.kind] = source;
  }
  return chosen.opencode ?? chosen.commandcode ?? chosen.vscode ?? null;
}
function discordActivity(source) {
  if (!source) return null;
  return buildDiscordActivity(source, VISIBILITY, ASSETS);
}
function applyActivity(key, activity, source) {
  lastEffectiveKey = key; lastIpcAt = Date.now();
  if (activity) {
    ipc.setActivity(activity);
    log(`SET_ACTIVITY ${activity.details} | ${activity.state} | source=${source.kind}`);
  } else { ipc.clearActivity(); log("CLEAR_ACTIVITY"); }
}
function scheduleFlush() {
  if (flushTimer) return;
  flushTimer = setTimeout(() => {
    flushTimer = undefined;
    maybePushActivity();
  }, Math.max(0, MIN_IPC_INTERVAL_MS - (Date.now() - lastIpcAt)));
  flushTimer.unref?.();
}
function maybePushActivity() {
  const source = effectiveSource(), activity = discordActivity(source);
  const key = activity ? JSON.stringify(activity) : "clear";
  if (key === lastEffectiveKey) return;
  if (Date.now() - lastIpcAt < MIN_IPC_INTERVAL_MS) return scheduleFlush();
  applyActivity(key, activity, source);
}
function validState(body) {
  return body && typeof body === "object" && typeof body.sourceId === "string" &&
    ["opencode", "commandcode", "vscode"].includes(body.kind) &&
    typeof body.active === "boolean" &&
    (body.focused === undefined || typeof body.focused === "boolean") &&
    body.state && typeof body.state === "object";
}
function handleState(body) {
  if (!validState(body)) return false;
  const now = Date.now(), previous = sources.get(body.sourceId);
  const becomesActive = body.active && !previous?.active;
  const focusedNow = body.focused === true;
  const source = {
    kind: body.kind, sourceId: body.sourceId, active: body.active, focused: focusedNow,
    state: body.state, lastSeen: now,
    // Preserve these on heartbeats. This is the critical anti-flip-flop rule.
    lastActiveAt: becomesActive ? now : (previous?.lastActiveAt ?? now),
    busyAt: becomesActive ? now : (previous?.busyAt ?? now),
    lastFocusedAt: focusedNow && !previous?.focused ? now : previous?.lastFocusedAt,
  };
  sources.set(body.sourceId, source);
  if (!previous || sourceKey(source) !== sourceKey(previous)) maybePushActivity();
  return true;
}
function sweep() {
  const now = Date.now();
  for (const [id, source] of sources) {
    if (now - source.lastSeen > TTL_MS) { sources.delete(id); log(`source expired: kind=${source.kind}`); }
  }
  maybePushActivity();
}

const ipc = new DiscordIpc({ clientId: config.clientId, log });
ipc.onReady(() => { lastEffectiveKey = null; maybePushActivity(); });
const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${HOST}:${PORT}`);
  if (req.method === "GET" && url.pathname === "/healthz") {
    res.writeHead(200, {"content-type":"application/json"});
    res.end(JSON.stringify({
      ok: true,
      service: "devvy",
      launchAgent: "com.rich.discord-presence",
    }));
    return;
  }
  if (req.method === "PUT" && url.pathname === "/state") {
    let raw = "";
    req.on("data", chunk => { raw += chunk; if (raw.length > 64 * 1024) req.destroy(); });
    req.on("end", () => {
      let body; try { body = JSON.parse(raw); } catch {
        res.writeHead(400, {"content-type":"application/json"}); res.end('{"ok":false,"error":"invalid json"}'); return;
      }
      const ok = handleState(body);
      res.writeHead(ok ? 200 : 400, {"content-type":"application/json"});
      res.end(JSON.stringify(ok ? {ok:true} : {ok:false,error:"invalid state"}));
    }); return;
  }
  res.writeHead(404, {"content-type":"application/json"}); res.end('{"ok":false,"error":"not found"}');
});
server.on("error", err => {
  if (err?.code === "EADDRINUSE") { log(`port ${PORT} already in use; another daemon owns it, exiting cleanly`); ipc.stop(); process.exit(0); }
  log(`server error: ${err?.message || err}`); process.exit(1);
});
server.listen(PORT, HOST, () => {
  log(`presence daemon listening on http://${HOST}:${PORT}`);
  ipc.start().catch(err => log(`discord connect failed: ${err?.message || err}`));
});
setInterval(sweep, SWEEP_MS).unref();
function shutdown() {
  if (flushTimer) clearTimeout(flushTimer);
  ipc.stop(); server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 1000).unref();
}
process.on("SIGINT", shutdown); process.on("SIGTERM", shutdown);
