import type {ModApi} from '@commandcode/harness';

const DAEMON_URL =
  typeof process !== 'undefined' && process.env?.PRESENCE_DAEMON_URL
    ? process.env.PRESENCE_DAEMON_URL
    : 'http://127.0.0.1:17377';

const HEARTBEAT_MS = 5000;
const DEBOUNCE_MS = 500;

function basename(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const parts = String(value).split(/[\\/]/);
  return parts[parts.length - 1] || undefined;
}

function stripControl(value: string): string {
  return value.replace(/[\u0000-\u001f\u007f]/g, '');
}

function truncate(value: string, max: number): string {
  if (value.length <= max) return value;
  return value.slice(0, max - 1) + '…';
}

function normalizeModel(model: unknown): string | undefined {
  if (!model) return undefined;
  if (typeof model === 'string') return model;
  if (typeof model === 'object') {
    const m = model as {model?: unknown; modelID?: unknown; id?: unknown; name?: unknown};
    const candidate = m.model ?? m.modelID ?? m.id ?? m.name;
    if (typeof candidate === 'string' && candidate) return candidate;
  }
  return undefined;
}

function toolLabel(toolName: unknown): string | undefined {
  if (typeof toolName !== 'string' || !toolName) return undefined;
  switch (toolName) {
    case 'read_file':
      return 'Searching';
    case 'grep':
    case 'glob':
      return 'Searching';
    case 'write_file':
    case 'edit_file':
      return 'Editing';
    case 'shell_command':
      return 'Running';
    default:
      return undefined;
  }
}

export default function (cmd: ModApi): void {
  const project = basename(cmd.cwd) || 'Command Code';
  const sourceId = `commandcode:${process.pid}`;

  let active = false;
  let busySince: number | undefined;
  let lastModel: string | undefined;
  let mode: string | undefined;
  let heartbeat: ReturnType<typeof setInterval> | undefined;
  let debounceTimer: ReturnType<typeof setTimeout> | undefined;

  function computeState() {
    return {
      app: 'Command Code',
      project,
      model: lastModel ? truncate(stripControl(lastModel), 128) : undefined,
      mode: mode || (active ? 'Thinking' : 'Waiting for prompt'),
      startedAt: busySince,
    };
  }

  async function send(): Promise<void> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 2000);
    const body = {
      sourceId,
      kind: 'commandcode',
      ts: Date.now(),
      active,
      state: computeState(),
    };
    try {
      await fetch(`${DAEMON_URL}/state`, {
        method: 'PUT',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify(body),
        signal: controller.signal,
      });
    } catch {
      // daemon may be restarting; the heartbeat retries
    } finally {
      clearTimeout(timeout);
    }
  }

  function scheduleSend(): void {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      debounceTimer = undefined;
      void send();
    }, DEBOUNCE_MS);
  }

  function startHeartbeat(): void {
    if (heartbeat) return;
    heartbeat = setInterval(() => {
      void send();
    }, HEARTBEAT_MS);
    heartbeat.unref?.();
  }

  function stopHeartbeat(): void {
    if (heartbeat) clearInterval(heartbeat);
    heartbeat = undefined;
  }

  function setActive(value: boolean): void {
    if (value) {
      active = true;
      if (!busySince) busySince = Date.now();
    } else {
      active = false;
      busySince = undefined;
      mode = undefined;
    }
    scheduleSend();
  }

  cmd.on('run_start', () => setActive(true));

  cmd.on('run_end', () => setActive(false));

  cmd.on('model_request_start', (event) => {
    const model = normalizeModel(event?.model);
    if (model) lastModel = model;
    mode = 'Thinking';
    setActive(true);
  });

  cmd.on('tool_running', (event) => {
    const label = toolLabel(event?.toolName);
    if (label) mode = label;
    setActive(true);
  });

  cmd.on('session_start', () => {
    startHeartbeat();
    void send();
  });

  cmd.on('session_shutdown', () => {
    active = false;
    busySince = undefined;
    mode = undefined;
    stopHeartbeat();
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = undefined;
    void send();
  });

  startHeartbeat();
}
