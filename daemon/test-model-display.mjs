import assert from "node:assert/strict";
import { friendlyModelName } from "./model-display.mjs";

assert.equal(friendlyModelName("zai-org/GLM-5.3"), "GLM 5.3");
assert.equal(friendlyModelName("deepseek/deepseek-v4-pro"), "DeepSeek V4 Pro");
assert.equal(friendlyModelName("anthropic/claude-3-5-sonnet"), "Claude 3 5 Sonnet");
assert.equal(friendlyModelName("qwen/qwen2.5-coder-32b"), "Qwen2.5 Coder 32b");
assert.equal(friendlyModelName("acme/my_custom-model"), "Acme My Custom Model");
assert.equal(friendlyModelName(" \u0000 "), undefined);
assert.equal(friendlyModelName(undefined), undefined);
assert.equal(friendlyModelName({ model: "x" }), undefined);
console.log("PASS: deterministic model display normalization");
