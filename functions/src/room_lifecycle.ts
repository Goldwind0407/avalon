import { Timestamp } from 'firebase-admin/firestore';

/** TTL deletes later; authorization must reject expired or invalid deadlines now. */
export function roomHasExpired(expireAt: unknown, now = Date.now()): boolean {
  return !(expireAt instanceof Timestamp) || expireAt.toMillis() <= now;
}

/** Renew a game's private documents once their deadline is this close. */
export const GAME_DOCS_RENEW_MARGIN_MS = 12 * 60 * 60 * 1000;

/**
 * Whether the players' private documents need their TTL deadline pushed
 * out: the room is renewed on every move, these only when they come
 * within [GAME_DOCS_RENEW_MARGIN_MS] of expiring (or the deadline is
 * missing or malformed), so a busy room does not rewrite them each move.
 */
export function gameDocsRenewalDue(deadline: unknown, now = Date.now()): boolean {
  return !(deadline instanceof Timestamp) ||
    deadline.toMillis() - now < GAME_DOCS_RENEW_MARGIN_MS;
}
