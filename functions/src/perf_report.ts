/**
 * How smoothly the web game draws on a player's device (sent now and then by
 * lib/core/web_perf_web.dart). Only these fields are kept, each checked and
 * bounded; nothing in it says who the player is.
 */
export interface PerfReport {
  renderer: 'wasm' | 'js';
  isolated: boolean;
  light: boolean;
  gaveUp: boolean;
  fps: number;
  latePct: number;
  p95: number;
  worst: number;
  slowSeconds: number;
  seconds: number;
  dpr: number;
  width: number;
  height: number;
  standalone: boolean;
  ua: string;
  page: string;
  /** The release played (tool/prepare_pwa.py); null when not given. */
  release: string | null;
  /** The same, step by step: 'menu', 'deal', 'interlude' or a game phase. */
  stages: Record<string, StageFrames>;
  /** The longest stops (a tenth of a second and more), and where. */
  stalls: Stall[];
  /** Frames that took at least 50, 100, 250, 500 and 1000 ms. */
  over: Record<string, number>;
}

const OVERS = ['50', '100', '250', '500', '1000'];
function cleanOver(v: unknown): Record<string, number> | null {
  if (v === undefined) return {};
  if (typeof v !== 'object' || v === null || Array.isArray(v)) return null;
  const f = v as Record<string, unknown>;
  if (Object.keys(f).some((k) => !OVERS.includes(k))) return null;
  const over: Record<string, number> = {};
  for (const k of Object.keys(f)) {
    const n = num(f[k], 0, 1000000);
    if (n === null) return null;
    over[k] = n;
  }
  return over;
}

/** A stop of the screen; [before]: what happened shortly before it, each
 *  as `what@ms` (ms from the stop's start; negative is before it). */
export interface Stall { stage: string; ms: number; before: string[] }
const NOTE = /^[\w:.\-]{1,40}@-?\d{1,5}$/;

export interface StageFrames {
  fps: number;
  latePct: number;
  seconds: number;
  stalls: number;
}

const STAGE = /^[a-zA-Z]{1,20}$/;
const MAX_STAGES = 24, MAX_STALLS = 8;

/** Reports kept a day at most; past this the rest of the day is dropped. */
export const DAILY_REPORTS = 2000;
/** How long a report is kept (TTL on `expireAt`). */
export const REPORT_LIFETIME_MS = 30 * 24 * 60 * 60 * 1000;

const num = (v: unknown, min: number, max: number): number | null =>
  typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max ? v : null;
const bool = (v: unknown): boolean | null => (typeof v === 'boolean' ? v : null);
const text = (v: unknown, max: number): string | null =>
  typeof v === 'string' ? v.slice(0, max) : null;

function cleanStages(v: unknown): Record<string, StageFrames> | null {
  if (typeof v !== 'object' || v === null || Array.isArray(v)) return null;
  const entries = Object.entries(v as Record<string, unknown>);
  if (entries.length > MAX_STAGES) return null;
  const stages: Record<string, StageFrames> = {};
  for (const [stage, s] of entries) {
    if (!STAGE.test(stage) || typeof s !== 'object' || s === null) return null;
    const f = s as Record<string, unknown>;
    const frames = {
      fps: num(f.fps, 0, 1000),
      latePct: num(f.latePct, 0, 100),
      seconds: num(f.seconds, 0, 100000),
      stalls: num(f.stalls, 0, 100000),
    };
    if (Object.values(frames).some((x) => x === null)) return null;
    stages[stage] = frames as StageFrames;
  }
  return stages;
}

function cleanStalls(v: unknown): Stall[] | null {
  if (!Array.isArray(v) || v.length > MAX_STALLS) return null;
  const stalls = v.map((s) => {
    const f = (typeof s === 'object' && s !== null ? s : {}) as Record<string, unknown>;
    const stage = typeof f.stage === 'string' && STAGE.test(f.stage) ? f.stage : null;
    const ms = num(f.ms, 0, 600000);
    const before = f.before === undefined ? [] : f.before;
    const notes = Array.isArray(before) && before.length <= 6 &&
      before.every((n) => typeof n === 'string' && NOTE.test(n)) ? before as string[] : null;
    return stage === null || ms === null || notes === null ? null : { stage, ms, before: notes };
  });
  return stalls.some((s) => s === null) ? null : (stalls as Stall[]);
}

/** The report in [data], or null when anything in it is missing or off. */
export function cleanPerfReport(data: unknown): PerfReport | null {
  if (typeof data !== 'object' || data === null) return null;
  const d = data as Record<string, unknown>;
  const report = {
    renderer: d.renderer === 'wasm' || d.renderer === 'js' ? d.renderer : null,
    isolated: bool(d.isolated),
    light: bool(d.light),
    gaveUp: bool(d.gaveUp),
    fps: num(d.fps, 0, 1000),
    latePct: num(d.latePct, 0, 100),
    p95: num(d.p95, 0, 1000),
    worst: num(d.worst, 0, 1000),
    slowSeconds: num(d.slowSeconds, 0, 100000),
    seconds: num(d.seconds, 0, 100000),
    dpr: num(d.dpr, 0, 10),
    width: num(d.width, 0, 10000),
    height: num(d.height, 0, 10000),
    standalone: bool(d.standalone),
    ua: text(d.ua, 300),
    // the screen only (`#/online`), never a query or anything after it
    page: text(d.page, 40)?.split('?')[0] ?? null,
    stages: cleanStages(d.stages),
    stalls: cleanStalls(d.stalls),
    over: cleanOver(d.over),
  };
  if (Object.values(report).some((v) => v === null)) return null;
  // optional: older pages do not send it
  const release = typeof d.release === 'string' && /^[0-9a-f]{16}$/.test(d.release) ? d.release : null;
  return { ...report, release } as PerfReport;
}
