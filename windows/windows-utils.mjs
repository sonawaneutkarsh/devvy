import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export function windowsArchitecture(env = process.env) {
  const value = String(env.PROCESSOR_ARCHITEW6432 || env.PROCESSOR_ARCHITECTURE || "").toUpperCase();
  if (value === "AMD64" || value === "X86_64") return "x86_64";
  if (value === "ARM64") return "arm64";
  return undefined;
}

export function windowsInstallDir(env = process.env) {
  const root = env.LOCALAPPDATA || path.join(env.USERPROFILE || "", "AppData", "Local");
  return path.win32.join(root, "Devvy");
}

export function bundledNodePath(installDir) {
  return path.win32.join(installDir, "runtime", "node.exe");
}

export function verifySha256(file, expected) {
  const hash = crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
  return hash.toLowerCase() === String(expected).trim().toLowerCase();
}
