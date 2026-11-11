// Avalon rules, ported one-to-one from lib/features/game/game_model.dart.
// Pure functions only (no Firestore), so they can be unit tested directly.
// Keep the two in sync: functions/test/rules.test.ts mirrors the Dart tests.

export type RoleKey =
  | 'merlin'
  | 'percival'
  | 'loyal'
  | 'assassin'
  | 'morgana'
  | 'mordred'
  | 'oberon'
  | 'minion'
  | 'lancelotGood'
  | 'lancelotEvil';

export type Phase =
  | 'identity'
  | 'team'
  | 'discussion'
  | 'freeDiscussion'
  | 'vote'
  | 'voteResult'
  | 'quest'
  | 'questResult'
  | 'lady'
  | 'ladyResult'
  | 'excalibur'
  | 'excaliburResult'
  | 'assassination'
  | 'finished';

/** Roles the host can add on top of Merlin and the Assassin. */
export const OPTIONAL_ROLES: readonly RoleKey[] = [
  'percival',
  'morgana',
  'mordred',
  'oberon',
];

const EVIL: ReadonlySet<RoleKey> = new Set<RoleKey>([
  'assassin',
  'morgana',
  'mordred',
  'oberon',
  'minion',
  'lancelotEvil',
]);

export const isLancelot = (role: RoleKey): boolean =>
  role === 'lancelotGood' || role === 'lancelotEvil';

/**
 * Optional expansions chosen before the game.
 *  lady       Lady of the Lake: after quests 2-4 the holder examines a loyalty.
 *  lancelot   0 off; 1 loyalty cards turned over from quest 3; 2 five cards
 *             dealt face up at the start (Lancelots then must play their side).
 *  excalibur  the leader hands Excalibur to a team member, who may flip one
 *             other member's quest card.
 */
export interface Expansions {
  lady: boolean;
  lancelot: 0 | 1 | 2;
  excalibur: boolean;
}
export const NO_EXPANSIONS: Expansions = { lady: false, lancelot: 0, excalibur: false };
export function expansionSettings(value: unknown): Expansions {
  if (value == null) return { ...NO_EXPANSIONS };
  const v = value as Expansions;
  if (typeof v !== 'object' || typeof v.lady !== 'boolean' ||
      typeof v.excalibur !== 'boolean' || ![0, 1, 2].includes(v.lancelot)) {
    throw new GameError('invalid-argument', '擴充設定不正確');
  }
  return { lady: v.lady, lancelot: v.lancelot, excalibur: v.excalibur };
}
export const anyExpansion = (e: Expansions) => e.lady || e.lancelot > 0 || e.excalibur;

export const isEvil = (role: RoleKey): boolean => EVIL.has(role);

export const MIN_PLAYERS = 5;
export const MAX_PLAYERS = 10;

export function evilCount(players: number): number {
  if (players === 5 || players === 6) return 2;
  if (players >= 7 && players <= 9) return 3;
  if (players === 10) return 4;
  return 0;
}

const QUEST_SIZES: Record<number, number[]> = {
  5: [2, 3, 2, 3, 3],
  6: [2, 3, 4, 3, 4],
  7: [2, 3, 3, 4, 4],
};

/** Team size of quest number [questIndex] (0-based). */
export function questSize(players: number, questIndex: number): number {
  const sizes = QUEST_SIZES[players] ?? [3, 4, 4, 5, 5];
  return sizes[Math.min(questIndex, 4)];
}

/** Fail cards needed to sink quest number [questNumber] (1-based). */
export function failsRequired(players: number, questNumber: number): number {
  return players >= 7 && questNumber === 4 ? 2 : 1;
}

/** Why this role setup cannot start, or null when it can. */
export function configIssue(
  players: number,
  optional: readonly RoleKey[],
  expansions: Expansions = NO_EXPANSIONS,
): string | null {
  if (players < MIN_PLAYERS || players > MAX_PLAYERS) return '需要 5～10 位玩家';
  if (optional.some((r) => !OPTIONAL_ROLES.includes(r))) return '包含未知角色';
  if (new Set(optional).size !== optional.length) return '角色重複';
  const special: RoleKey[] = ['merlin', 'assassin', ...optional, ...lancelots(expansions)];
  const evil = special.filter(isEvil).length;
  const good = special.length - evil;
  if (evil > evilCount(players)) return '邪惡角色超過本局邪惡陣營名額';
  if (good > players - evilCount(players)) return '正義角色超過本局正義陣營名額';
  return null;
}

const lancelots = (e: Expansions): RoleKey[] =>
  e.lancelot > 0 ? ['lancelotGood', 'lancelotEvil'] : [];

export type Rng = () => number;

export function shuffle<T>(items: T[], rng: Rng): T[] {
  const a = [...items];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

export function dealRoles(
  players: number,
  optional: readonly RoleKey[],
  rng: Rng,
  expansions: Expansions = NO_EXPANSIONS,
): RoleKey[] {
  const issue = configIssue(players, optional, expansions);
  if (issue) throw new GameError('failed-precondition', issue);
  const deck: RoleKey[] = ['merlin', 'assassin', ...optional, ...lancelots(expansions)];
  while (deck.filter(isEvil).length < evilCount(players)) deck.push('minion');
  while (deck.length < players) deck.push('loyal');
  return shuffle(deck, rng);
}

/** Seats the player at [seat] gets to see at the start of the game. */
export function visibleSeats(roles: readonly RoleKey[], seat: number): number[] {
  const role = roles[seat];
  const visible: number[] = [];
  roles.forEach((other, i) => {
    if (i === seat) return;
    const merlinSees = role === 'merlin' && isEvil(other) && other !== 'mordred';
    const percivalSees =
      role === 'percival' && (other === 'merlin' || other === 'morgana');
    // Evil Lancelot is known to the other evil players but does not see them.
    const evilSees =
      isEvil(role) && role !== 'oberon' && role !== 'lancelotEvil' &&
      isEvil(other) && other !== 'oberon';
    if (merlinSees || percivalSees || evilSees) visible.push(i);
  });
  return visible;
}

export class GameError extends Error {
  constructor(
    readonly code: 'failed-precondition' | 'permission-denied' | 'invalid-argument',
    message: string,
  ) {
    super(message);
  }
}

export interface Quest {
  team: number[];
  fails: number;
  succeeded: boolean;
  /** The played cards in the order they are turned over (same on every device). */
  order: boolean[];
  /** Excalibur on this quest: who held it and whose card they flipped. */
  excalibur?: { holder: number; target: number | null } | null;
}

/** Something only one player learns (copied to their private document). */
export interface Reveal {
  seat: number;
  kind: 'lady' | 'excalibur';
  quest: number;
  target: number;
  /** lady: the target's loyalty at that moment. */
  evil?: boolean;
  /** excalibur: the card the target had played before it was flipped. */
  card?: boolean;
}

export interface DiscussionSettings {
  enabled: boolean;
  speechSeconds: number;
  freeSeconds: number;
  selectionFree: boolean;
}
export const FREE_DISCUSSION: DiscussionSettings = {
  enabled: false, speechSeconds: 45, freeSeconds: 0, selectionFree: true,
};
export function discussionSettings(value: unknown): DiscussionSettings {
  if (value == null) return { ...FREE_DISCUSSION };
  const v = value as DiscussionSettings;
  if (typeof v !== 'object' || typeof v.enabled !== 'boolean' ||
      typeof v.selectionFree !== 'boolean' || !Number.isInteger(v.speechSeconds) ||
      v.speechSeconds < 30 || v.speechSeconds > 90 || ![0, 60].includes(v.freeSeconds)) {
    throw new GameError('invalid-argument', '發言設定不正確');
  }
  return { enabled: v.enabled, speechSeconds: v.speechSeconds,
    freeSeconds: v.freeSeconds, selectionFree: v.selectionFree };
}
export interface Proposal {
  quest: number;
  attempt: number;
  leader: number;
  team: number[];
  votes: boolean[];
  approved: boolean;
}

/** Everything about a game in progress, public and secret parts together. */
export interface GameState {
  phase: Phase;
  leader: number;
  rejections: number;
  team: number[];
  /** Seats that have looked at their identity. */
  confirmed: number[];
  /** Seats that have put down a (face-down) vote in the current vote. */
  voted: number[];
  /** Every seat's vote, published once all have voted. */
  votes: boolean[] | null;
  /** Team members that have played a quest card. */
  played: number[];
  history: Quest[];
  proposals: Proposal[];
  discussion: DiscussionSettings;
  speechIndex: number;
  speechVersion: number;
  speechDeadline: number | null;
  winner: '正義' | '邪惡' | null;
  result: string;
  assassinTarget: number | null;
  /** All roles, published when the game ends. */
  revealedRoles: RoleKey[] | null;
  expansions: Expansions;
  /** Lancelot loyalty card on each quest (null = none turned over). */
  loyalty: (boolean | null)[];
  /** The Lancelots currently play for the other side. */
  lancelotSwitched: boolean;
  ladyHolder: number | null;
  /** Everyone who has held the Lady (they cannot be examined). */
  ladyPast: number[];
  ladyChecks: { holder: number; target: number; quest: number }[];
  /** Who holds Excalibur on the current team. */
  excaliburHolder: number | null;

  // ── secret: never sent to devices ──
  roles: RoleKey[];
  pendingVotes: Record<string, boolean>;
  pendingCards: Record<string, boolean>;
  /** Variant 1: loyalty cards still face down. */
  loyaltyDeck: boolean[];
  reveals: Reveal[];
}

export const SECRET_KEYS = ['roles', 'pendingVotes', 'pendingCards', 'loyaltyDeck', 'reveals'] as const;

export function newGame(
  players: number,
  optional: readonly RoleKey[],
  rng: Rng,
  settings: DiscussionSettings = FREE_DISCUSSION,
  expansionsValue: Expansions = NO_EXPANSIONS,
): GameState {
  const expansions = expansionSettings(expansionsValue);
  const roles = dealRoles(players, optional, rng, expansions);
  const leader = Math.floor(rng() * players);
  // 5 "no change" and 2 "switch" loyalty cards
  let loyaltyDeck: boolean[] = [];
  let loyalty: (boolean | null)[] = [null, null, null, null, null];
  if (expansions.lancelot > 0) {
    loyaltyDeck = shuffle([false, false, false, false, false, true, true], rng);
    if (expansions.lancelot === 2) {
      loyalty = loyaltyDeck.slice(0, 5);
      loyaltyDeck = [];
    }
  }
  // the Lady starts with the player on the first leader's right
  const ladyHolder = expansions.lady ? (leader - 1 + players) % players : null;
  const s: GameState = {
    phase: 'identity',
    leader,
    rejections: 0,
    team: [],
    confirmed: [],
    voted: [],
    votes: null,
    played: [],
    history: [],
    proposals: [],
    discussion: discussionSettings(settings),
    speechIndex: 0, speechVersion: 0, speechDeadline: null,
    winner: null,
    result: '',
    assassinTarget: null,
    revealedRoles: null,
    expansions,
    loyalty,
    lancelotSwitched: false,
    ladyHolder,
    ladyPast: ladyHolder == null ? [] : [ladyHolder],
    ladyChecks: [],
    excaliburHolder: null,
    roles,
    pendingVotes: {},
    pendingCards: {},
    loyaltyDeck,
    reveals: [],
  };
  beginQuest(s);
  return s;
}

/** A new quest starts: turn over a loyalty card when one is due. */
function beginQuest(s: GameState) {
  const q = s.history.length;
  if (q > 4) return;
  if (s.expansions.lancelot === 1 && q >= 2 && s.loyaltyDeck.length > 0) {
    s.loyalty[q] = s.loyaltyDeck.shift()!;
  }
  if (s.loyalty[q] === true) s.lancelotSwitched = !s.lancelotSwitched;
}

/** The side the player at [seat] plays for right now. */
export const evilNow = (s: GameState, seat: number): boolean =>
  isEvil(s.roles[seat]) !== (isLancelot(s.roles[seat]) && s.lancelotSwitched);

const playerCount = (s: GameState) => s.roles.length;
export const successes = (s: GameState) => s.history.filter((q) => q.succeeded).length;
export const failures = (s: GameState) => s.history.length - successes(s);
export const requiredTeam = (s: GameState) =>
  questSize(playerCount(s), s.history.length);

function requirePhase(s: GameState, phase: Phase) {
  if (s.phase !== phase) {
    throw new GameError('failed-precondition', '目前階段無法執行此操作');
  }
}

function checkSeat(s: GameState, seat: number) {
  if (!Number.isInteger(seat) || seat < 0 || seat >= playerCount(s)) {
    throw new GameError('invalid-argument', '座位不存在');
  }
}

function finish(s: GameState, side: '正義' | '邪惡', reason: string) {
  s.winner = side;
  s.result = reason;
  s.phase = 'finished';
  s.revealedRoles = [...s.roles];
}

function nextLeader(s: GameState) {
  s.leader = (s.leader + 1) % playerCount(s);
  s.team = [];
  s.excaliburHolder = null;
}

function nextQuest(s: GameState) {
  nextLeader(s);
  s.phase = 'team';
  beginQuest(s);
}

// Every action below mutates [s] in place and throws GameError when the
// move is not allowed. [seat] is the seat of the player making the move.

export function confirmIdentity(s: GameState, seat: number) {
  requirePhase(s, 'identity');
  checkSeat(s, seat);
  if (!s.confirmed.includes(seat)) s.confirmed.push(seat);
  if (s.confirmed.length === playerCount(s)) s.phase = 'team';
}

export function proposeTeam(
  s: GameState, seat: number, team: number[], now = Date.now(), excalibur: unknown = null,
) {
  requirePhase(s, 'team');
  if (seat !== s.leader) throw new GameError('permission-denied', '只有隊長可以提案');
  if (!Array.isArray(team)) throw new GameError('invalid-argument', '隊伍格式錯誤');
  const members = [...new Set(team)].sort((a, b) => a - b);
  if (
    members.length !== team.length ||
    members.length !== requiredTeam(s) ||
    members.some((i) => !Number.isInteger(i) || i < 0 || i >= playerCount(s))
  ) {
    throw new GameError('invalid-argument', '隊伍人數不正確');
  }
  if (s.expansions.excalibur &&
      (typeof excalibur !== 'number' || !members.includes(excalibur) || excalibur === seat)) {
    throw new GameError('invalid-argument', '請把王者之劍交給隊長以外的一名隊員');
  }
  s.excaliburHolder = s.expansions.excalibur ? (excalibur as number) : null;
  s.team = members;
  s.voted = [];
  s.votes = null;
  s.pendingVotes = {};
  s.speechIndex = 0;
  s.speechVersion++;
  s.phase = s.discussion.enabled ? 'discussion' : 'vote';
  s.speechDeadline = s.discussion.enabled ? now + s.discussion.speechSeconds * 1000 : null;
}

export const currentSpeaker = (s: GameState) =>
  s.phase === 'discussion' ? (s.leader + 1 + s.speechIndex) % playerCount(s) : null;

export function endSpeech(s: GameState, seat: number, expectedVersion: number, now = Date.now()) {
  checkSeat(s, seat);
  if (!Number.isInteger(expectedVersion)) throw new GameError('invalid-argument', '缺少發言版本');
  if (expectedVersion !== s.speechVersion ||
      !['discussion', 'freeDiscussion'].includes(s.phase)) return false;
  if (s.phase === 'freeDiscussion') {
    if (now < s.speechDeadline!) throw new GameError('failed-precondition', '自由討論尚未結束');
    s.speechVersion++; s.phase = 'vote'; s.speechDeadline = null; return true;
  }
  if (now < s.speechDeadline! && seat !== currentSpeaker(s)) {
    throw new GameError('permission-denied', '只有目前發言者可以過麥');
  }
  s.speechVersion++; s.speechIndex++;
  if (s.speechIndex < playerCount(s)) {
    s.speechDeadline = now + s.discussion.speechSeconds * 1000;
  } else if (s.discussion.freeSeconds > 0) {
    s.phase = 'freeDiscussion'; s.speechDeadline = now + s.discussion.freeSeconds * 1000;
  } else {
    s.phase = 'vote'; s.speechDeadline = null;
  }
  return true;
}

export function vote(s: GameState, seat: number, approve: boolean) {
  requirePhase(s, 'vote');
  checkSeat(s, seat);
  if (typeof approve !== 'boolean') throw new GameError('invalid-argument', '投票格式錯誤');
  if (s.voted.includes(seat)) throw new GameError('failed-precondition', '你已經投過票了');
  s.voted.push(seat);
  s.pendingVotes[String(seat)] = approve;
  if (s.voted.length === playerCount(s)) {
    s.votes = Array.from({ length: playerCount(s) }, (_, i) => s.pendingVotes[String(i)]);
    s.pendingVotes = {};
    s.phase = 'voteResult';
    s.proposals.push({ quest: s.history.length + 1, attempt: s.rejections + 1,
      leader: s.leader, team: [...s.team], votes: [...s.votes], approved: teamApproved(s) });
  }
}

export const teamApproved = (s: GameState) =>
  (s.votes ?? []).filter((v) => v).length > playerCount(s) / 2;

export function continueVote(s: GameState) {
  requirePhase(s, 'voteResult');
  const approved = teamApproved(s);
  s.voted = [];
  s.votes = null;
  if (approved) {
    s.rejections = 0;
    s.played = [];
    s.pendingCards = {};
    s.phase = 'quest';
    return;
  }
  s.rejections++;
  if (s.rejections === 5) {
    finish(s, '邪惡', '連續五次組隊遭否決，邪惡陣營獲勝。');
  } else {
    nextLeader(s);
    s.phase = 'team';
  }
}

export function playQuest(s: GameState, seat: number, success: boolean, rng: Rng) {
  requirePhase(s, 'quest');
  if (!s.team.includes(seat)) throw new GameError('permission-denied', '你不是這次任務的隊員');
  if (typeof success !== 'boolean') throw new GameError('invalid-argument', '任務牌格式錯誤');
  if (s.played.includes(seat)) throw new GameError('failed-precondition', '你已經出過牌了');
  if (!success && !evilNow(s, seat)) {
    throw new GameError('permission-denied', '正義玩家只能出成功');
  }
  if (success && mustFail(s, seat)) {
    throw new GameError('permission-denied', '邪惡方的蘭斯洛特必須出失敗');
  }
  s.played.push(seat);
  s.pendingCards[String(seat)] = success;
  if (s.played.length === s.team.length) {
    if (s.excaliburHolder != null) s.phase = 'excalibur';
    else resolveQuest(s, rng, null);
  }
}

/** Variant 2: a Lancelot on the evil side may only play Fail. */
export const mustFail = (s: GameState, seat: number): boolean =>
  s.expansions.lancelot === 2 && isLancelot(s.roles[seat]) && evilNow(s, seat);

function resolveQuest(s: GameState, rng: Rng, target: number | null) {
  const cards = s.team.map((i) => s.pendingCards[String(i)]);
  const fails = cards.filter((c) => !c).length;
  const succeeded = fails < failsRequired(playerCount(s), s.history.length + 1);
  s.history.push({
    team: [...s.team], fails, succeeded, order: shuffle(cards, rng),
    excalibur: s.excaliburHolder == null ? null : { holder: s.excaliburHolder, target },
  });
  s.pendingCards = {};
  s.phase = 'questResult';
}

/** Excalibur: flip one other team member's card ([target] null to pass). */
export function useExcalibur(s: GameState, seat: number, target: unknown, rng: Rng) {
  requirePhase(s, 'excalibur');
  if (seat !== s.excaliburHolder) {
    throw new GameError('permission-denied', '只有王者之劍持有者可以使用');
  }
  if (target == null) return resolveQuest(s, rng, null);
  if (typeof target !== 'number' || !s.team.includes(target) || target === seat) {
    throw new GameError('invalid-argument', '請選擇另一名隊員');
  }
  const card = s.pendingCards[String(target)];
  s.pendingCards[String(target)] = !card;
  s.reveals.push({ seat, kind: 'excalibur', quest: s.history.length + 1, target, card });
  s.phase = 'excaliburResult';
}

export function continueExcalibur(s: GameState, seat: number, rng: Rng) {
  requirePhase(s, 'excaliburResult');
  if (seat !== s.excaliburHolder) {
    throw new GameError('permission-denied', '請等待王者之劍持有者');
  }
  resolveQuest(s, rng, s.reveals[s.reveals.length - 1].target);
}

/** Lady of the Lake: the holder examines one player's loyalty. */
export function useLady(s: GameState, seat: number, target: unknown) {
  requirePhase(s, 'lady');
  if (seat !== s.ladyHolder) {
    throw new GameError('permission-denied', '只有湖中女神持有者可以查驗');
  }
  if (typeof target !== 'number') throw new GameError('invalid-argument', '請選擇玩家');
  checkSeat(s, target);
  if (s.ladyPast.includes(target)) {
    throw new GameError('invalid-argument', '持有過湖中女神的玩家不能被查驗');
  }
  const quest = s.history.length;
  s.ladyChecks.push({ holder: seat, target, quest });
  s.reveals.push({ seat, kind: 'lady', quest, target, evil: evilNow(s, target) });
  s.phase = 'ladyResult';
}

/** The examined player receives the Lady; the next quest begins. */
export function continueLady(s: GameState, seat: number) {
  requirePhase(s, 'ladyResult');
  if (seat !== s.ladyHolder) {
    throw new GameError('permission-denied', '請等待湖中女神持有者');
  }
  const target = s.ladyChecks[s.ladyChecks.length - 1].target;
  s.ladyHolder = target;
  s.ladyPast.push(target);
  nextQuest(s);
}

export function continueQuest(s: GameState) {
  requirePhase(s, 'questResult');
  s.played = [];
  if (failures(s) === 3) {
    finish(s, '邪惡', '三次任務失敗，邪惡陣營獲勝。');
  } else if (successes(s) === 3) {
    s.phase = 'assassination';
  } else if (s.ladyHolder != null && [2, 3, 4].includes(s.history.length)) {
    s.phase = 'lady';
  } else {
    nextQuest(s);
  }
}

export function assassinate(
  s: GameState,
  seat: number,
  target: number,
  names: readonly string[],
) {
  requirePhase(s, 'assassination');
  if (s.roles[seat] !== 'assassin') throw new GameError('permission-denied', '只有刺客可以刺殺');
  checkSeat(s, target);
  // Only the Assassin's own seat is refused: checking alignment here would
  // let a device probe hidden identities.
  if (target === seat) throw new GameError('invalid-argument', '請選擇其他玩家');
  const hit = s.roles[target] === 'merlin';
  s.assassinTarget = target;
  finish(
    s,
    hit ? '邪惡' : '正義',
    `刺客選擇 ${target + 1} 號 ${names[target]}，${hit ? '成功刺殺梅林。' : '未能找到梅林，正義陣營獲勝！'}`,
  );
}

/** Splits a state into what devices may read and what stays on the server. */
export function split(s: GameState) {
  const { roles, pendingVotes, pendingCards, loyaltyDeck, reveals, ...open } = s;
  return { open, secret: { roles, pendingVotes, pendingCards, loyaltyDeck, reveals } };
}

export function join(
  open: Omit<GameState, (typeof SECRET_KEYS)[number]>,
  secret: Pick<GameState, (typeof SECRET_KEYS)[number]>,
): GameState {
  const state = { ...open, ...secret };
  state.discussion ??= { ...FREE_DISCUSSION };
  state.proposals ??= [];
  state.speechIndex ??= 0;
  state.speechVersion ??= 0;
  state.speechDeadline ??= null;
  state.expansions ??= { ...NO_EXPANSIONS };
  state.loyalty ??= [null, null, null, null, null];
  state.lancelotSwitched ??= false;
  state.ladyHolder ??= null;
  state.ladyPast ??= [];
  state.ladyChecks ??= [];
  state.excaliburHolder ??= null;
  state.loyaltyDeck ??= [];
  state.reveals ??= [];
  return state;
}
