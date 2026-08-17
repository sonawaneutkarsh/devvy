/**
 * Converts a publisher-provided model identifier into a short display label.
 * It is intentionally local, deterministic, and conservative: unknown names
 * are cleaned rather than guessed.
 */
function clean(value) {
  return typeof value === "string"
    ? value.replace(/[\u0000-\u001f\u007f]/g, "").trim()
    : "";
}

function words(value) {
  return value
    .replace(/[_/:-]+/g, " ")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/\s+/g, " ")
    .trim()
    .split(" ")
    .filter(Boolean);
}

function title(word) {
  if (/^(glm|gpt|llama|qwen|claude|gemini|mistral|deepseek|codex)$/i.test(word)) {
    const lower = word.toLowerCase();
    if (lower === "glm") return "GLM";
    if (lower === "gpt") return "GPT";
    if (lower === "llama") return "LLaMA";
    if (lower === "deepseek") return "DeepSeek";
    return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
  }
  if (/^v\d+(?:\.\d+)?$/i.test(word)) return `V${word.slice(1)}`;
  if (/^\d+(?:\.\d+)+$/.test(word)) return word;
  return word.length <= 4 && /^[A-Z0-9]+$/.test(word)
    ? word
    : word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
}

export function friendlyModelName(value) {
  const raw = clean(value);
  if (!raw) return undefined;

  // A provider namespace is not useful on Discord for these well-known
  // providers. Do not remove arbitrary first path components.
  let name = raw;
  const match = name.match(/^([^/]+)\/(.+)$/);
  if (match && /^(zai-org|zai|deepseek|anthropic|openai|google|meta|mistralai|qwen)$/i.test(match[1])) {
    name = match[2];
  }
  const tokens = words(name);
  if (!tokens.length) return undefined;

  return tokens.map(title).join(" ");
}
