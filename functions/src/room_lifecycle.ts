import { Timestamp } from 'firebase-admin/firestore';

/** TTL deletes later; authorization must reject expired or invalid deadlines now. */
export function roomHasExpired(expireAt: unknown, now = Date.now()): boolean {
  return !(expireAt instanceof Timestamp) || expireAt.toMillis() <= now;
}
