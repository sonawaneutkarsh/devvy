import net from "node:net";
import fs from "node:fs";
import path from "node:path";

const OP = {
  HANDSHAKE: 0,
  FRAME: 1,
  CLOSE: 2,
  PING: 3,
  PONG: 4,
};

const dir = process.argv[2];
const socketPath = path.join(dir, "discord-ipc-0");
const logPath = path.join(dir, "server.log");

function log(message) {
  fs.appendFileSync(logPath, `[${new Date().toISOString()}] ${message}\n`);
}

fs.mkdirSync(dir, { recursive: true });
try {
  fs.unlinkSync(socketPath);
} catch {}

const server = net.createServer((socket) => {
  let buffer = Buffer.alloc(0);
  log("client connected");

  socket.on("data", (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    while (buffer.length >= 8) {
      const op = buffer.readUInt32LE(0);
      const length = buffer.readUInt32LE(4);
      if (buffer.length < length + 8) break;
      const payload = buffer.subarray(8, length + 8);
      buffer = buffer.subarray(length + 8);
      const msg = JSON.parse(payload.toString());
      log(`RX op=${op} cmd=${msg.cmd || ""} evt=${msg.evt || ""}`);

      if (op === OP.HANDSHAKE) {
        log(`HANDSHAKE client_id=${msg.client_id}`);
        const ready = {
          cmd: "DISPATCH",
          evt: "READY",
          data: { config: { cdn_host: "cdn.discordapp.com" } },
        };
        socket.write(frame(OP.FRAME, ready));
      } else if (op === OP.FRAME && msg.cmd === "SET_ACTIVITY") {
        const activity = msg.args?.activity;
        if (activity) {
          log(
            `ACTIVITY details=${activity.details} state=${activity.state}`,
          );
          const large = activity.assets?.large_image;
          if (large) log(`ACTIVITY_ASSETS large=${large} text=${activity.assets?.large_text ?? ""}`);
        } else {
          log("ACTIVITY cleared");
        }
        socket.write(frame(OP.FRAME, { cmd: "SET_ACTIVITY", evt: null, data: {} }));
      } else if (op === OP.FRAME && msg.cmd === "SUBSCRIBE") {
        socket.write(frame(OP.FRAME, { cmd: "SUBSCRIBE", evt: null, data: {} }));
      } else if (op === OP.PING) {
        socket.write(frame(OP.PONG, msg));
      }
    }
  });

  socket.on("close", () => log("client disconnected"));
  socket.on("error", (err) => log(`socket error ${err.message}`));
});

function frame(op, msg) {
  const payload = Buffer.from(JSON.stringify(msg));
  const header = Buffer.alloc(8);
  header.writeUInt32LE(op, 0);
  header.writeUInt32LE(payload.length, 4);
  return Buffer.concat([header, payload]);
}

server.listen(socketPath, () => {
  log(`mock discord listening on ${socketPath}`);
});
