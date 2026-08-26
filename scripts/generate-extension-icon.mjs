// Generates the original Devvy extension icon (vscode-extension/icon.png).
//
// Provenance: this artwork is generated entirely by this script at build time.
// No third-party images, fonts, or assets are used. The design is an original
// geometric mark: three colored input streams converge into a single white
// presence dot inside a status ring, representing Devvy's aggregator
// architecture (VS Code + OpenCode + Command Code -> one daemon -> Discord).
// The icon is licensed under the same MIT license as the rest of Devvy.
//
// Usage: node scripts/generate-extension-icon.mjs [output-path]
import zlib from "node:zlib";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SIZE = 256;
const SCALE = 3; // supersample factor for anti-aliasing
const N = SIZE * SCALE;

const BG = [32, 38, 63]; // #20263F deep indigo
const LINE_COLORS = [
  [78, 205, 196], // teal
  [247, 179, 43], // amber
  [255, 107, 107], // coral
];
const WHITE = [255, 255, 255];
const CORNER_RADIUS = 48;
const RECT_MIN = 8;
const RECT_MAX = SIZE - RECT_MIN;

function roundedRectInside(x, y) {
  const cx = Math.max(Math.abs(x - SIZE / 2) - (SIZE / 2 - RECT_MIN - CORNER_RADIUS), 0);
  const cy = Math.max(Math.abs(y - SIZE / 2) - (SIZE / 2 - RECT_MIN - CORNER_RADIUS), 0);
  return Math.hypot(cx, cy) <= CORNER_RADIUS
    && x >= RECT_MIN && x <= RECT_MAX && y >= RECT_MIN && y <= RECT_MAX;
}

function distToSegment(x, y, [x1, y1], [x2, y2]) {
  const dx = x2 - x1, dy = y2 - y1;
  const lengthSq = dx * dx + dy * dy;
  const t = Math.max(0, Math.min(1, ((x - x1) * dx + (y - y1) * dy) / lengthSq));
  return Math.hypot(x - (x1 + t * dx), y - (y1 + t * dy));
}

const HUB = { x: 170, y: 128 };
const LINES = [
  { from: [34, 74], to: [138, 116], half: 7.5 },
  { from: [30, 128], to: [132, 128], half: 7.5 },
  { from: [34, 182], to: [138, 140], half: 7.5 },
];

function colorAt(x, y) {
  if (!roundedRectInside(x, y)) return null;
  for (const [index, line] of LINES.entries()) {
    if (distToSegment(x, y, line.from, line.to) <= line.half) {
      return LINE_COLORS[index];
    }
  }
  const distToHub = Math.hypot(x - HUB.x, y - HUB.y);
  if (distToHub <= 30) return WHITE;
  if (Math.abs(distToHub - 46) <= 4.5) return WHITE;
  return BG;
}

function render() {
  const pixels = Buffer.alloc(SIZE * SIZE * 4);
  for (let py = 0; py < SIZE; py++) {
    for (let px = 0; px < SIZE; px++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let sy = 0; sy < SCALE; sy++) {
        for (let sx = 0; sx < SCALE; sx++) {
          const sample = colorAt(px * SCALE + sx + 0.5, py * SCALE + sy + 0.5);
          if (sample) {
            r += sample[0]; g += sample[1]; b += sample[2]; a += 1;
          }
        }
      }
      const count = SCALE * SCALE;
      const offset = (py * SIZE + px) * 4;
      pixels[offset] = Math.round(r / count);
      pixels[offset + 1] = Math.round(g / count);
      pixels[offset + 2] = Math.round(b / count);
      pixels[offset + 3] = Math.round((a / count) * 255);
    }
  }
  return pixels;
}

// Minimal dependency-free PNG writer (RGBA8, non-interlaced).
const CRC_TABLE = new Int32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c;
});

function crc32(buf) {
  let crc = -1;
  for (const byte of buf) crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ -1) >>> 0;
}

function chunk(type, data) {
  const out = Buffer.alloc(data.length + 12);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, "ascii");
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

function encodePng(pixels) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(SIZE, 0);
  ihdr.writeUInt32BE(SIZE, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type RGBA
  const raw = Buffer.alloc(SIZE * (SIZE * 4 + 1));
  for (let y = 0; y < SIZE; y++) {
    raw[y * (SIZE * 4 + 1)] = 0; // filter: none
    pixels.copy(raw, y * (SIZE * 4 + 1) + 1, y * SIZE * 4, (y + 1) * SIZE * 4);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const outPath = process.argv[2]
  ?? path.join(__dirname, "..", "vscode-extension", "icon.png");
fs.writeFileSync(outPath, encodePng(render()));
console.log(`Wrote ${outPath} (${SIZE}x${SIZE} RGBA PNG)`);
