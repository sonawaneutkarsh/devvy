export function compareWithinKind(candidate, incumbent) {
  if (!incumbent) return true;
  if (candidate.active !== incumbent.active) return candidate.active;

  if (candidate.kind === "vscode" && candidate.active && incumbent.active) {
    if (candidate.focused !== incumbent.focused) return candidate.focused;
    if (candidate.lastFocusedAt === undefined || incumbent.lastFocusedAt === undefined) {
      if (candidate.lastFocusedAt !== incumbent.lastFocusedAt) return candidate.lastFocusedAt !== undefined;
    }
    if (candidate.lastFocusedAt !== incumbent.lastFocusedAt) {
      return candidate.lastFocusedAt > incumbent.lastFocusedAt;
    }
  }

  // Activity transitions, not heartbeat arrival, determine normal recency.
  const a = candidate.active ? candidate.busyAt : candidate.lastActiveAt;
  const b = incumbent.active ? incumbent.busyAt : incumbent.lastActiveAt;
  if (a !== b) return a > b;
  return candidate.sourceId.localeCompare(incumbent.sourceId) < 0;
}
