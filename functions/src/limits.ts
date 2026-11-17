// How often one signed-in player may do the things that cost us or could
// be abused: opening rooms, and trying room codes that do not exist (room
// codes are six digits, so guessing them is the way into a stranger's
// lobby). Pure functions only, like rules.ts.

export interface Limit {
  /** At most this many within [windowMs]. */
  max: number;
  windowMs: number;
}

export const LIMITS = {
  /** Rooms opened. */
  create: { max: 10, windowMs: 60 * 60 * 1000 },
  /** Codes tried that lead nowhere. */
  miss: { max: 20, windowMs: 10 * 60 * 1000 },
} as const satisfies Record<string, Limit>;

export type LimitKind = keyof typeof LIMITS;

/** The times still inside the window, oldest first (malformed ones dropped). */
export function recent(times: unknown, now: number, limit: Limit): number[] {
  if (!Array.isArray(times)) return [];
  return times
    .filter((t): t is number => typeof t === 'number' && t > now - limit.windowMs && t <= now)
    .sort((a, b) => a - b);
}

/** Whether one more is allowed now. */
export const allowed = (times: unknown, now: number, limit: Limit): boolean =>
  recent(times, now, limit).length < limit.max;

/** How long until one more is allowed (0 when it already is). */
export function waitMs(times: unknown, now: number, limit: Limit): number {
  const kept = recent(times, now, limit);
  if (kept.length < limit.max) return 0;
  return kept[kept.length - limit.max] + limit.windowMs - now;
}
