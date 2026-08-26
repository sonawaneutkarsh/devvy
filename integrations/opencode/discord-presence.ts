import type {
  PluginModule,
  PluginInput,
  Hooks,
} from "@opencode-ai/plugin";

type PluginEvent = Parameters<NonNullable<Hooks["event"]>>[0]["event"];

declare const process:
  | { env?: Record<string, string | undefined> }
  | undefined;

const DAEMON_URL =
  typeof process !== "undefined" && process.env?.PRESENCE_DAEMON_URL
    ? process.env.PRESENCE_DAEMON_URL
    : "http://127.0.0.1:17377";
const HEARTBEAT_MS = 5000;
const DEBOUNCE_MS = 500;

type SessionRecord = {
  status?: "idle" | "busy" | "retry";
  updatedAt: number;
};

type ModelRef = {
  providerID: string;
  modelID: string;
};

type ModelLike = {
  providerID?: unknown;
  modelID?: unknown;
  id?: unknown;
};

function basename(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const parts = String(value).split(/[\\/]/);
  return parts[parts.length - 1] || undefined;
}

function stableId(value: string): string {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) hash = Math.imul(hash ^ value.charCodeAt(i), 16777619);
  return (hash >>> 0).toString(36);
}

function formatModel(providerID: string | undefined, modelID: string | undefined): string | undefined {
  // The daemon owns display normalization. Keep the original identifier here.
  return modelID || providerID;
}

function modelRef(value: unknown): ModelRef | undefined {
  if (!value || typeof value !== "object") return undefined;
  const model = value as ModelLike;
  const providerID = typeof model.providerID === "string" ? model.providerID : "";
  const modelID = typeof model.modelID === "string"
    ? model.modelID
    : (typeof model.id === "string" ? model.id : "");
  if (!providerID && !modelID) return undefined;
  return { providerID, modelID };
}

function toolLabel(tool: string): string {
  switch (tool) {
    case "edit":
    case "write":
    case "patch":
      return "Editing";
    case "bash":
    case "shell":
    case "exec":
      return "Running";
    case "read":
    case "grep":
    case "glob":
    case "find":
      return "Searching";
    default:
      return "Thinking";
  }
}

const plugin: PluginModule = {
  id: "dev.rich.discord-presence",

  async server(input: PluginInput): Promise<Hooks> {
    const directory = input.directory || input.worktree || "";
    const sourceId = `opencode:${stableId(directory)}`;
    const project = basename(directory) || "OpenCode";
    const log = (message: string) => {
      try {
        const result = input.client.app.log({
          body: {
            service: "discord-presence",
            level: "info",
            message,
          },
        });
        if (result && typeof result.catch === "function") {
          result.catch(() => {});
        }
      } catch {
        // logging must never break the plugin
      }
    };
    log(`loaded source=${sourceId}`);

    const sessions = new Map<string, SessionRecord>();
    let lastModel: ModelRef | undefined;
    let mode: string | undefined;
    let active = false;
    let busySince: number | undefined;
    let debounceTimer: ReturnType<typeof setTimeout> | undefined;
    let heartbeat: ReturnType<typeof setInterval> | undefined;
    let disposed = false;

    function busyCount(): number {
      let count = 0;
      for (const session of sessions.values()) {
        if (session.status === "busy" || session.status === "retry") count += 1;
      }
      return count;
    }

    function computeState() {
      return {
        app: "OpenCode",
        project,
        model: formatModel(lastModel?.providerID, lastModel?.modelID),
        mode: mode || (active ? "Thinking" : "Idle"),
        startedAt: busySince,
      };
    }

    async function send(): Promise<void> {
      if (disposed) return;
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 2000);
      const body = {
        sourceId,
        kind: "opencode",
        connected: true,
        ts: Date.now(),
        active,
        state: computeState(),
      };
      try {
        await fetch(`${DAEMON_URL}/state`, {
          method: "PUT",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(body),
          signal: controller.signal,
        });
      } catch {
        // Daemon may be restarting; the heartbeat retries.
      } finally {
        clearTimeout(timeout);
      }
    }

    function scheduleSend(): void {
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(send, DEBOUNCE_MS);
    }

    function recomputeBusy(): void {
      const busy = busyCount() > 0;
      active = busy;
      if (busy) {
        if (!busySince) busySince = Date.now();
      } else {
        busySince = undefined;
        mode = undefined;
      }
    }

    function setSession(sessionID: string, patch: Partial<SessionRecord>): void {
      const current = sessions.get(sessionID) || { updatedAt: 0 };
      sessions.set(sessionID, { ...current, ...patch, updatedAt: Date.now() });
    }

    function pruneSessions(): void {
      const cutoff = Date.now() - 10 * 60 * 1000;
      for (const [id, session] of sessions) {
        if (session.status !== "busy" && session.status !== "retry" && session.updatedAt < cutoff) {
          sessions.delete(id);
        }
      }
    }

    function handleEvent(event: PluginEvent): void {
      switch (event.type) {
        case "session.created":
        case "session.updated": {
          const info = event.properties.info;
          if (!info?.id) break;
          setSession(info.id, {});
          scheduleSend();
          break;
        }
        case "session.status": {
          const status = event.properties.status?.type;
          const sessionID = event.properties.sessionID;
          if (!sessionID) break;
          setSession(sessionID, { status });
          recomputeBusy();
          scheduleSend();
          break;
        }
        case "session.idle": {
          const sessionID = event.properties.sessionID;
          if (!sessionID) break;
          setSession(sessionID, { status: "idle" });
          mode = undefined;
          recomputeBusy();
          scheduleSend();
          break;
        }
        case "session.error": {
          const sessionID = event.properties.sessionID;
          if (sessionID) setSession(sessionID, { status: "idle" });
          recomputeBusy();
          mode = "Idle";
          scheduleSend();
          break;
        }
        case "todo.updated": {
          // A todo may contain user prompt text; it is intentionally not sent.
          if (active) mode = "Planning";
          scheduleSend();
          break;
        }
        case "file.edited": {
          mode = "Editing";
          scheduleSend();
          break;
        }
        case "message.updated": {
          const info = event.properties.info;
          if (info?.role === "user") {
            lastModel = modelRef(info.model) || lastModel;
          } else if (info?.role === "assistant") {
            lastModel = modelRef({ providerID: info.providerID, modelID: info.modelID }) || lastModel;
          }
          scheduleSend();
          break;
        }
        case "message.part.updated": {
          const part = event.properties.part;
          if (part?.type === "patch" && Array.isArray(part.files) && part.files.length > 0) {
            mode = "Editing";
          }
          scheduleSend();
          break;
        }
        default:
          break;
      }
    }

    heartbeat = setInterval(() => {
      pruneSessions();
      void send();
    }, HEARTBEAT_MS);

    return {
      event: async ({ event }) => {
        handleEvent(event);
      },

      "chat.message": async ({ sessionID, model }) => {
        lastModel = modelRef(model) || lastModel;
        if (sessionID) setSession(sessionID, { status: "busy" });
        recomputeBusy();
        scheduleSend();
      },

      // The SDK model passed here is the model selected for the actual request.
      // It uses `id`, while chat.message uses `modelID` in older plugin hooks.
      "chat.params": async ({ sessionID, model }) => {
        lastModel = modelRef(model) || lastModel;
        if (sessionID) setSession(sessionID, { status: "busy" });
        recomputeBusy();
        scheduleSend();
      },

      "tool.execute.before": async ({ tool, sessionID }) => {
        mode = toolLabel(tool);
        if (sessionID) setSession(sessionID, { status: "busy" });
        recomputeBusy();
        scheduleSend();
      },

      "tool.execute.after": async () => {
        mode = undefined;
        scheduleSend();
      },

      dispose: async () => {
        if (heartbeat) clearInterval(heartbeat);
        if (debounceTimer) clearTimeout(debounceTimer);
        active = false;
        await send();
        disposed = true;
      },
    };
  },
};

export default plugin;
