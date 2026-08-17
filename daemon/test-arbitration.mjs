import assert from "node:assert/strict";
import { compareWithinKind } from "./arbitration.mjs";

function vscode(sourceId, focused, busyAt, lastFocusedAt) {
  return {
    kind: "vscode",
    sourceId,
    active: true,
    focused,
    busyAt,
    lastActiveAt: busyAt,
    lastFocusedAt,
  };
}

const focused = vscode("vscode:focused", true, 100, 100);
const unfocusedNewer = vscode("vscode:unfocused", false, 200, undefined);
assert.equal(compareWithinKind(unfocusedNewer, focused), false);
assert.equal(compareWithinKind(focused, unfocusedNewer), true);

// Heartbeat recency is not used to displace a focused window.
assert.equal(compareWithinKind({ ...unfocusedNewer, busyAt: 999 }, focused), false);

const focusedLater = vscode("vscode:focused-later", true, 50, 300);
assert.equal(compareWithinKind(focusedLater, focused), true);
assert.equal(compareWithinKind({ ...focusedLater, focused: false }, { ...focused, focused: false }), true);

// Non-VS Code arbitration retains the existing active/recency semantics.
assert.equal(compareWithinKind({
  kind: "opencode", sourceId: "opencode:new", active: true, busyAt: 200, lastActiveAt: 200,
}, {
  kind: "opencode", sourceId: "opencode:old", active: true, busyAt: 100, lastActiveAt: 100,
}), true);

console.log("PASS: focused VS Code arbitration and non-VS recency");
