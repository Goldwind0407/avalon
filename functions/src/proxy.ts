// A stand-in for a player whose phone has gone quiet, so the others are not
// left waiting. It plays plainly, from what that seat may know (its role,
// the seats its role shows it, its own Lady results, the public record),
// and hands the seat back the moment the player is heard from again.
// Pure functions only (no Firestore), like rules.ts.

import * as rules from './rules';
import { GameState, Rng } from './rules';

/** A phone not heard from for this long is away (it reports every 20 s). */
export const AWAY_AFTER_MS = 60 * 1000;

/** A result stays on the table this long before a stand-in moves on. */
export const RESULT_VIEW_MS = 6 * 1000;

/** App protocol from which a phone reports that it is there. */
export const PRESENCE_PROTOCOL = 4;

export const isAway = (lastSeenMs: number | null, now: number): boolean =>
  lastSeenMs == null || now - lastSeenMs > AWAY_AFTER_MS;

const RESULTS: readonly rules.Phase[] =
  ['voteResult', 'questResult', 'ladyResult', 'excaliburResult', 'finished'];

/** The table shows something everyone should get to look at. */
export const showsResult = (s: GameState): boolean => RESULTS.includes(s.phase);

/** Whether the game is waiting for [seat] to do something. */
export function pending(s: GameState, seat: number): boolean {
  switch (s.phase) {
    case 'identity': return !s.confirmed.includes(seat);
    case 'team':
    case 'voteResult':
    case 'questResult': return seat === s.leader;
    case 'discussion': return seat === rules.currentSpeaker(s);
    case 'vote': return !s.voted.includes(seat);
    case 'quest': return s.team.includes(seat) && !s.played.includes(seat);
    case 'lady':
    case 'ladyResult': return seat === s.ladyHolder;
    case 'excalibur':
    case 'excaliburResult': return seat === s.excaliburHolder;
    case 'assassination': return s.roles[seat] === 'assassin';
    default: return false; // free discussion runs on the clock
  }
}

/**
 * Seats [seat] knows to be evil right now: by role, or from its own Lady
 * results. With the Lancelots in the game this follows the switch cards,
 * which are public: an evil player knows where the evil Lancelot sits and
 * so that he plays for good while switched, and a Lady result from before
 * a switch may have been about a Lancelot, so it is no longer relied on.
 * (Merlin sees the evil Lancelot as evil but cannot tell him apart, so his
 * list stays as dealt.)
 */
export function knownEvil(s: GameState, seat: number): Set<number> {
  const role = s.roles[seat];
  const known = new Set<number>(
    role === 'percival' ? [] : rules.visibleSeats(s.roles, seat));
  const lancelot = rules.knownLancelot(s.roles, seat);
  if (lancelot != null && s.lancelotSwitched) known.delete(lancelot);
  for (const r of s.reveals) {
    if (r.seat !== seat || r.kind !== 'lady' || !r.evil) continue;
    // used after quest r.quest: any card turned over since then is at
    // index r.quest or later
    const switchedSince = s.expansions.lancelot > 0 &&
      s.loyalty.slice(r.quest, s.history.length + 1).some((card) => card === true);
    if (!switchedSince) known.add(r.target);
  }
  return known;
}

/** Failed quests [seat] was on. */
const taint = (s: GameState, seat: number): number =>
  s.history.filter((q) => q.fails > 0 && q.team.includes(seat)).length;

const seats = (s: GameState): number[] => s.roles.map((_, i) => i);

/** The lowest-scoring of [options]. */
function pick(options: number[], score: (seat: number) => number): number {
  let best = options[0], low = Infinity;
  for (const seat of options) {
    const value = score(seat);
    if (value < low) { low = value; best = seat; }
  }
  return best;
}

function team(s: GameState, seat: number, rng: Rng): { team: number[]; holder: number | null } {
  const evil = rules.evilNow(s, seat);
  const known = knownEvil(s, seat);
  const needsTwo = rules.failsRequired(s.roles.length, s.history.length + 1) === 2;
  const score = new Map<number, number>();
  for (const other of seats(s)) {
    if (other === seat) continue;
    // a good leader leaves out who he knows is evil; an evil one keeps his
    // allies off the team (one exposed player is enough) unless the quest
    // takes two Fails
    const ally = known.has(other) ? (evil && needsTwo ? -5 : 100) : 0;
    score.set(other, ally + taint(s, other) * 10 + rng());
  }
  const others = [...score.keys()].sort((a, b) => score.get(a)! - score.get(b)!);
  const members = [seat, ...others.slice(0, rules.requiredTeam(s) - 1)];
  return { team: members, holder: s.expansions.excalibur ? members[1] : null };
}

function approves(s: GameState, seat: number, rng: Rng): boolean {
  if (s.rejections >= 4) return true; // a fifth rejection loses the game
  const known = knownEvil(s, seat);
  if (rules.evilNow(s, seat)) {
    return s.team.some((x) => x === seat || known.has(x)) || rng() < 0.5;
  }
  return !s.team.some((x) => known.has(x) || (x !== seat && taint(s, x) > 0));
}

function card(s: GameState, seat: number, rng: Rng): boolean {
  if (!rules.evilNow(s, seat)) return true;
  if (rules.mustFail(s, seat)) return false;
  const known = knownEvil(s, seat);
  const evilOnTeam = s.team.filter((x) => x === seat || known.has(x)).length;
  // one Fail where two are needed sinks nothing and gives the team away
  if (rules.failsRequired(s.roles.length, s.history.length + 1) > evilOnTeam) return true;
  // the first quest is often left alone
  return s.history.length === 0 ? rng() < 0.5 : false;
}

function ladyTarget(s: GameState, seat: number, rng: Rng): number | null {
  const open = seats(s).filter((x) => !s.ladyPast.includes(x));
  if (open.length === 0) return null;
  const known = knownEvil(s, seat);
  // good looks where the record points; evil looks at anyone but an ally
  return rules.evilNow(s, seat)
    ? pick(open, (x) => (known.has(x) ? 10 : 0) + rng())
    : pick(open, (x) => -taint(s, x) + rng());
}

/** Whoever voted most like someone who knows where evil sits. */
function merlinGuess(s: GameState, seat: number, rng: Rng): number {
  const evil = new Set<number>([seat, ...rules.visibleSeats(s.roles, seat)]);
  const options = seats(s).filter((x) => !evil.has(x));
  return pick(options.length ? options : seats(s).filter((x) => x !== seat), (x) => {
    let like = 0;
    for (const p of s.proposals) {
      if (p.attempt >= 5) continue; // everyone approves the fifth
      const dirty = p.team.some((m) => evil.has(m));
      if (dirty) like += p.votes[x] ? -1 : 1;
      else if (p.leader === x) like += 1;
    }
    return -like + rng() * 0.5;
  });
}

/**
 * Does what the game is waiting for [seat] to do. Moving on from a result
 * is done only when [mayContinue]: the others need time to look at it.
 * Returns whether anything was done.
 */
export function act(
  s: GameState, seat: number, rng: Rng, names: readonly string[],
  now: number, mayContinue: boolean,
): boolean {
  if (!pending(s, seat)) return false;
  switch (s.phase) {
    case 'identity':
      rules.confirmIdentity(s, seat);
      return true;
    case 'team': {
      const choice = team(s, seat, rng);
      rules.proposeTeam(s, seat, choice.team, now, choice.holder);
      return true;
    }
    case 'discussion':
      return rules.endSpeech(s, seat, s.speechVersion, now);
    case 'vote':
      rules.vote(s, seat, approves(s, seat, rng));
      return true;
    case 'quest':
      rules.playQuest(s, seat, card(s, seat, rng), rng);
      return true;
    case 'lady': {
      const target = ladyTarget(s, seat, rng);
      if (target == null) return false;
      rules.useLady(s, seat, target);
      return true;
    }
    case 'excalibur':
      rules.useExcalibur(s, seat, null, rng); // leaves the cards as played
      return true;
    case 'assassination':
      rules.assassinate(s, seat, merlinGuess(s, seat, rng), names);
      return true;
    case 'voteResult':
      if (mayContinue) rules.continueVote(s);
      return mayContinue;
    case 'questResult':
      if (mayContinue) rules.continueQuest(s);
      return mayContinue;
    case 'ladyResult':
      if (mayContinue) rules.continueLady(s, seat);
      return mayContinue;
    case 'excaliburResult':
      if (mayContinue) rules.continueExcalibur(s, seat, rng);
      return mayContinue;
    default:
      return false;
  }
}

/**
 * Plays for every seat in [away] until the game waits for someone who is
 * there, or shows a result. Returns how many moves were made.
 */
export function standIn(
  s: GameState, away: readonly number[], rng: Rng, names: readonly string[],
  now: number, sinceChangeMs: number,
): number {
  let moves = 0;
  for (let i = 0; i < 60; i++) {
    const seat = away.find((x) => pending(s, x));
    if (seat == null) break;
    // only the first move of a call may leave a result behind, and only
    // once it has been on the table long enough
    const mayContinue = moves === 0 && sinceChangeMs >= RESULT_VIEW_MS;
    if (!act(s, seat, rng, names, now, mayContinue)) break;
    moves++;
    if (showsResult(s)) break;
  }
  return moves;
}
