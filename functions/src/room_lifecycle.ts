import { Timestamp } from 'firebase-admin/firestore';

/** TTL deletes later; authorization must reject expired or invalid deadlines now. */
export function roomHasExpired(expireAt: unknown, now = Date.now()): boolean {
  return !(expireAt instanceof Timestamp) || expireAt.toMillis() <= now;
}

/**
 * How long the players' private documents outlive the room: they are
 * renewed to this much past the room's deadline, and again once the room's
 * deadline comes within half of it, so a busy room rewrites them about
 * once an hour and they never expire while the room is still there.
 */
export const GAME_DOCS_LEAD_MS = 2 * 60 * 60 * 1000;

/**
 * Whether the players' private documents need renewing, given the room's
 * new deadline: when theirs is missing or malformed, or no longer at least
 * half of [GAME_DOCS_LEAD_MS] past the room's.
 */
export function gameDocsRenewalDue(deadline: unknown, roomDeadlineMs: number): boolean {
  return !(deadline instanceof Timestamp) ||
    deadline.toMillis() < roomDeadlineMs + GAME_DOCS_LEAD_MS / 2;
}
