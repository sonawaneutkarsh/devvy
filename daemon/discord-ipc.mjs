import net from "node:net";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const OP = {
  HANDSHAKE: 0,
  FRAME: 1,
  CLOSE: 2,
  PING: 3,
  PONG: 4,
};

function tmpPrefix() {
  if (process.env.DISCORD_IPC_DIR) {
    return process.env.DISCORD_IPC_DIR;
  }
  const raw =
    process.env.XDG_RUNTIME_DIR ??
    process.env.TMPDIR ??
    process.env.TMP ??
    process.env.TEMP ??
    path.sep + "tmp";
  try {
    return fs.realpathSync(raw);
  } catch {
    return raw;
  }
}

function socketPaths(pipeId) {
  const prefix = tmpPrefix();
  const ids = pipeId === undefined ? Array.from({ length: 10 }, (_, i) => i) : [pipeId];
  return ids.map((id) => path.join(prefix, `discord-ipc-${id}`));
}

function connectSocket(socketPath) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    const onError = () => {
      socket.removeListener("connect", onConnect);
      socket.destroy();
      reject(new Error(`Failed to connect to ${socketPath}`));
    };
    const onConnect = () => {
      socket.removeListener("error", onError);
      resolve(socket);
    };
    socket.once("connect", onConnect);
    socket.once("error", onError);
  });
}

export class DiscordIpc {
  constructor({ clientId, pipeId, log = () => {} }) {
    this.clientId = clientId;
    this.pipeId = pipeId;
    this.log = log;
    this.socket = undefined;
    this.ready = false;
    this.buffer = Buffer.alloc(0);
    this.reconnectTimer = undefined;
    this.backoff = 1000;
    this.manualClose = false;
    this.onReadyHandler = () => {};
  }

  onReady(handler) {
    this.onReadyHandler = handler;
  }

  async start() {
    this.manualClose = false;
    await this.connect();
  }

  async connect() {
    if (this.socket) return;
    const paths = socketPaths(this.pipeId);
    let socket;
    for (const socketPath of paths) {
      if (process.platform !== "win32") {
        const dir = path.dirname(socketPath);
        if (!fs.existsSync(dir)) continue;
      }
      try {
        socket = await connectSocket(socketPath);
        this.log(`connected to ${socketPath}`);
        break;
      } catch {
        // try next socket
      }
    }
    if (!socket) {
      this.scheduleReconnect();
      return;
    }
    if (this.manualClose) {
      socket.destroy();
      return;
    }

    this.socket = socket;
    this.ready = false;

    socket.on("data", (chunk) => this.handleData(chunk));
    socket.on("error", (err) => this.log(`socket error: ${err.message}`));
    socket.on("close", () => {
      this.log("socket closed");
      this.socket = undefined;
      this.ready = false;
      this.buffer = Buffer.alloc(0);
      if (!this.manualClose) this.scheduleReconnect();
    });

    this.send(
      {
        v: 1,
        client_id: this.clientId,
      },
      OP.HANDSHAKE,
    );
  }

  scheduleReconnect() {
    if (this.reconnectTimer || this.manualClose) return;
    this.log(`reconnecting in ${this.backoff}ms`);
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = undefined;
      this.backoff = Math.min(this.backoff * 2, 30000);
      this.connect();
    }, this.backoff);
  }

  handleData(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);

    while (true) {
      if (this.buffer.length < 8) return;

      const op = this.buffer.readUInt32LE(0);
      const length = this.buffer.readUInt32LE(4);
      if (this.buffer.length < length + 8) return;

      const payload = this.buffer.subarray(8, length + 8);
      this.buffer = this.buffer.subarray(length + 8);

      let message;
      try {
        message = payload.length ? JSON.parse(payload.toString()) : null;
      } catch {
        this.log("malformed payload ignored");
        continue;
      }

      this.handleMessage(op, message);
    }
  }

  handleMessage(op, message) {
    switch (op) {
      case OP.FRAME: {
        if (message?.cmd === "DISPATCH" && message.evt === "READY") {
          this.ready = true;
          this.backoff = 1000;
          this.log("READY");
          this.onReadyHandler();
        }
        break;
      }
      case OP.CLOSE: {
        this.log("close frame from Discord");
        this.ready = false;
        const socket = this.socket;
        this.socket = undefined;
        if (socket && !socket.destroyed) socket.destroy();
        if (!this.manualClose) this.scheduleReconnect();
        break;
      }
      case OP.PING: {
        this.send(message, OP.PONG);
        break;
      }
      default:
        break;
    }
  }

  send(message, op = OP.FRAME) {
    if (!this.socket || this.socket.destroyed) return false;
    const payload = Buffer.from(JSON.stringify(message ?? {}));
    const packet = Buffer.alloc(8);
    packet.writeUInt32LE(op, 0);
    packet.writeUInt32LE(payload.length, 4);
    this.socket.write(Buffer.concat([packet, payload]));
    return true;
  }

  setActivity(activity) {
    if (!this.ready) return;
    this.send({
      cmd: "SET_ACTIVITY",
      args: {
        pid: process.pid,
        activity,
      },
      nonce: crypto.randomUUID(),
    });
  }

  clearActivity() {
    if (!this.ready) return;
    this.send({
      cmd: "SET_ACTIVITY",
      args: {
        pid: process.pid,
      },
      nonce: crypto.randomUUID(),
    });
  }

  async stop() {
    this.manualClose = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = undefined;
    }
    if (!this.socket) return;
    const socket = this.socket;
    this.socket = undefined;
    this.ready = false;
    socket.destroy();
  }
}
