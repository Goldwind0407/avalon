// Cloud Functions: the referee for online games.
//
// Devices never write game state directly (see firestore.rules). Every
// move is a callable function that checks who is calling, applies the rules
// from rules.ts inside a transaction, and writes three kinds of documents:
//
//   rooms/{code}                public table state, readable by the players
//   rooms/{code}/private/{uid}  one player's role and what they can see
//   rooms/{code}/secret/state   all roles, unrevealed votes and quest cards

import { randomInt, randomUUID } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import {
  FieldValue,
  Timestamp,
  Transaction,
  getFirestore,
} from 'firebase-admin/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import * as rules from './rules';
import { GameError, GameState, RoleKey } from './rules';
import * as proxy from './proxy';
import { voiceIceServers } from './voice_ice';
import { GAME_DOCS_LEAD_MS, gameDocsRenewalDue, roomHasExpired } from './room_lifecycle';

initializeApp();
// Callable functions must be reachable by the app; who is calling is
// checked inside every function with the Firebase sign-in token (uidOf).
setGlobalOptions({ region: 'asia-east1', maxInstances: 20, invoker: 'public' });
const db = getFirestore();

/** Rooms are kept for a day; set a TTL policy on `expireAt` to clean up. */
const ROOM_LIFETIME_MS = 24 * 60 * 60 * 1000;
const rng: rules.Rng = () => randomInt(0, 2 ** 32) / 2 ** 32;

interface Player {
  uid: string;
  name: string;
  supportsDiscussion?: boolean;
  /** App protocol: 3 understands the expansions; 4 reports its presence;
   *  5 shows what is said at the table and can play with computers. */
  protocol?: number;
  /** A computer player (its uid is `bot:<persona>`, which nobody can sign
   *  in as). [persona] names who it is in the app's cast. */
  bot?: boolean;
  persona?: string;
}

/** App protocol from which computers can sit at the table. */
const BOTS_PROTOCOL = 5;
const BOT_LEVELS = ['novice', 'normal', 'expert'] as const;
/** Lines kept per game; past this the table goes quiet rather than grow. */
const TALK_LIMIT = 800;
const LINE_LENGTH = 120;
const isBot = (room: Room, seat: number) => room.players[seat]?.bot === true;
const hasBots = (room: Room) => room.players.some((p) => p.bot);
const BOTS_UPDATE = '這個房間有電腦玩家，請先更新 App 再加入';

interface Room {
  code: string;
  hostUid: string;
  status: 'lobby' | 'playing';
  players: Player[];
  playerUids: string[];
  voiceRoomId: string;
  expireAt?: Timestamp;
  optionalRoles: RoleKey[];
  discussion?: rules.DiscussionSettings;
  expansions?: rules.Expansions;
  /** Increases every time a new game is dealt in this room. */
  gen: number;
  /** Increases on every change, so devices can tell updates apart. */
  step: number;
  game: Omit<GameState, (typeof rules.SECRET_KEYS)[number]> | null;
  /** Something everyone should be told (e.g. a player left mid-game). */
  notice?: string | null;
  /** The step at which [notice] was written, so devices show it once. */
  noticeStep?: number;
  /** When the players' private documents of the current game expire. */
  privateExpireAt?: Timestamp;
  /** Seats whose phone has gone quiet; a stand-in plays for them. */
  away?: number[];
  updatedAt?: Timestamp;
  /** How well the computers play, and the seed of this game's table. */
  botLevel?: (typeof BOT_LEVELS)[number];
  botSeed?: number;
  /** What has been said in this game, for everyone to read: the computers'
   *  lines (as their server words them) and the lines people typed. */
  talk?: Record<string, unknown>[];
}

const roomRef = (code: string) => db.collection('rooms').doc(code);
const protocolOf = (req: CallableRequest): number =>
  typeof req.data?.protocolVersion === 'number' ? req.data.protocolVersion : 1;
const EXPANSION_UPDATE = '這個房間使用了擴充規則，請先更新 App 再加入';
const secretRef = (code: string) => roomRef(code).collection('secret').doc('state');
const privateRef = (code: string, uid: string) =>
  roomRef(code).collection('private').doc(uid);
/** Written by each phone every 20 s (firestore.rules); read only here. */
const presenceRef = (code: string, uid: string) =>
  roomRef(code).collection('presence').doc(uid);

/** Tells the table that [seat] is back and plays for themselves again. */
function welcomeBack(room: Room, seat: number) {
  if (!room.away?.includes(seat)) return false;
  room.away = room.away.filter((x) => x !== seat);
  room.notice = `${seat + 1} 號 ${room.players[seat].name} 回來了，交還本人操作`;
  room.noticeStep = room.step + 1; // the step touch() is about to write
  return true;
}

function uidOf(req: CallableRequest): string {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', '請先登入');
  return uid;
}

function str(value: unknown, field: string): string {
  if (typeof value !== 'string') throw new HttpsError('invalid-argument', `缺少 ${field}`);
  return value;
}

function cleanName(value: unknown): string {
  const name = str(value, 'name').trim();
  if (name.length < 1 || name.length > 16) {
    throw new HttpsError('invalid-argument', '暱稱需為 1～16 個字');
  }
  return name;
}

function cleanCode(value: unknown): string {
  const code = str(value, 'code').trim();
  if (!/^\d{6}$/.test(code)) throw new HttpsError('invalid-argument', '房號是 6 位數字');
  return code;
}

/** Turns rule violations into errors the app can show. */
async function guarded<T>(work: () => Promise<T>): Promise<T> {
  try {
    return await work();
  } catch (e) {
    if (e instanceof GameError) throw new HttpsError(e.code, e.message);
    throw e;
  }
}

async function loadRoom(tx: Transaction, code: string): Promise<Room> {
  const snap = await tx.get(roomRef(code));
  if (!snap.exists) throw new HttpsError('not-found', '找不到這個房間');
  const room = snap.data() as Room;
  if (roomHasExpired(room.expireAt)) {
    throw new HttpsError('failed-precondition', '房間已到期');
  }
  return room;
}

function seatOf(room: Room, uid: string): number {
  const seat = room.playerUids.indexOf(uid);
  if (seat < 0) throw new HttpsError('permission-denied', '你不在這個房間裡');
  return seat;
}

/** When a room (and its private and secret documents) may be deleted. */
const expiry = () => Timestamp.fromMillis(Date.now() + ROOM_LIFETIME_MS);

function touch(room: Room, { renew = true } = {}) {
  return {
    ...room,
    step: room.step + 1,
    updatedAt: FieldValue.serverTimestamp(),
    expireAt: renew ? expiry()
      : room.expireAt instanceof Timestamp ? room.expireAt : Timestamp.fromMillis(0),
  };
}

// ───────────────────────── lobby ─────────────────────────

export const createRoom = onCall(async (req) => {
  const uid = uidOf(req);
  const name = cleanName(req.data?.name);
  return db.runTransaction(async (tx) => {
    for (let attempt = 0; attempt < 20; attempt++) {
      const code = String(randomInt(100000, 1000000));
      const ref = roomRef(code);
      if ((await tx.get(ref)).exists) continue;
      const room: Room = {
        code,
        hostUid: uid,
        status: 'lobby',
        players: [{ uid, name, supportsDiscussion: protocolOf(req) >= 2, protocol: protocolOf(req) }],
        playerUids: [uid],
        voiceRoomId: randomUUID(),
        optionalRoles: [],
        discussion: { ...rules.FREE_DISCUSSION, enabled: protocolOf(req) >= 2 },
        expansions: { ...rules.NO_EXPANSIONS },
        gen: 0,
        step: 0,
        game: null,
      };
      tx.set(ref, touch(room));
      return { code };
    }
    throw new HttpsError('resource-exhausted', '暫時無法建立房間，請稍後再試');
  });
});

export const joinRoom = onCall(async (req) => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  const name = cleanName(req.data?.name);
  return db.runTransaction(async (tx) => {
    const room = await loadRoom(tx, code);
    const seat = room.playerUids.indexOf(uid);
    const protocol = protocolOf(req);
    const supportsDiscussion = protocol >= 2;
    if (room.discussion?.enabled && !supportsDiscussion) {
      throw new HttpsError('failed-precondition', '這個房間已開啟依序發言，請先更新 App 再加入');
    }
    if (rules.anyExpansion(rules.expansionSettings(room.expansions)) && protocol < 3) {
      throw new HttpsError('failed-precondition', EXPANSION_UPDATE);
    }
    if (hasBots(room) && protocol < BOTS_PROTOCOL) {
      throw new HttpsError('failed-precondition', BOTS_UPDATE);
    }
    // Coming back to a room you are already in (reopened the app, lost
    // connection) just takes you back to your seat.
    if (seat >= 0) {
      if (welcomeBack(room, seat) ||
          room.players[seat].supportsDiscussion !== supportsDiscussion ||
          room.players[seat].protocol !== protocol) {
        room.players[seat].supportsDiscussion = supportsDiscussion;
        room.players[seat].protocol = protocol;
        tx.set(roomRef(code), touch(room));
      }
      return { code, seat };
    }
    if (room.status !== 'lobby') throw new HttpsError('failed-precondition', '遊戲已經開始，無法加入');
    if (room.players.length >= rules.MAX_PLAYERS) {
      throw new HttpsError('failed-precondition', '房間已滿（最多 10 人）');
    }
    room.players.push({ uid, name, supportsDiscussion, protocol });
    room.playerUids.push(uid);
    tx.set(roomRef(code), touch(room));
    return { code, seat: room.players.length - 1 };
  });
});

export const leaveRoom = onCall(async (req) => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  return db.runTransaction(async (tx) => {
    // Cleanup is deliberately allowed for expired or already deleted rooms.
    // Only this authenticated caller's private data/presence may be removed.
    const snap = await tx.get(roomRef(code));
    tx.delete(privateRef(code, uid));
    tx.delete(presenceRef(code, uid));
    tx.delete(roomRef(code).collection('voice').doc(uid));
    if (!snap.exists) return { left: true, ended: false };
    const room = snap.data() as Room;
    const seat = room.playerUids.indexOf(uid);
    if (seat < 0) return { left: true, ended: false };
    const expired = roomHasExpired(room.expireAt);
    const name = room.players[seat].name;
    // Seats are fixed while cards are dealt, so a player leaving ends the
    // game for everyone and the room goes back to the lobby.
    const ended = room.status !== 'lobby' && room.game?.phase !== 'finished';
    if (room.status !== 'lobby') {
      room.status = 'lobby';
      room.game = null;
      tx.delete(secretRef(code));
    }
    room.players.splice(seat, 1);
    room.playerUids.splice(seat, 1);
    room.away = []; // seats have moved
    room.talk = [];
    // a room of computers alone is nobody's room
    if (room.players.every((p) => p.bot)) {
      tx.delete(roomRef(code));
      return { left: true, ended };
    }
    if (room.hostUid === uid) room.hostUid = room.players.find((p) => !p.bot)!.uid;
    room.notice = ended ? `${name} 離開了房間，對局已中止` : `${name} 離開了房間`;
    room.noticeStep = room.step + 1; // the step touch() is about to write
    tx.set(roomRef(code), touch(room, { renew: !expired }));
    return { left: true, ended };
  });
});

/** Optional self-hosted TURN. No secret is needed for the default STUN mode. */
export const voiceIce = onCall(async (req) => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  await db.runTransaction(async tx => {
    const room = await loadRoom(tx, code);
    seatOf(room, uid);
  });
  try {
    return { iceServers: voiceIceServers(uid, {
      urls: process.env.VOICE_TURN_URLS,
      secret: process.env.VOICE_TURN_SECRET,
    }) };
  } catch (_) {
    throw new HttpsError('failed-precondition', '語音中繼伺服器設定不完整');
  }
});

export const setRoles = onCall(async (req) => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  const roles = req.data?.roles;
  if (!Array.isArray(roles) || roles.some((r) => !rules.OPTIONAL_ROLES.includes(r))) {
    throw new HttpsError('invalid-argument', '角色設定錯誤');
  }
  return db.runTransaction(async (tx) => {
    const room = await loadRoom(tx, code);
    if (room.hostUid !== uid) throw new HttpsError('permission-denied', '只有房主可以設定角色');
    if (room.status !== 'lobby') throw new HttpsError('failed-precondition', '遊戲進行中無法更改角色');
    room.optionalRoles = rules.OPTIONAL_ROLES.filter((r) => roles.includes(r));
    tx.set(roomRef(code), touch(room));
    return { ok: true };
  });
});

/** Deals a new game (also used for "play again" once a game has ended). */
export const startGame = onCall((req) =>
  guarded(async () => {
    const uid = uidOf(req);
    const code = cleanCode(req.data?.code);
    return db.runTransaction(async (tx) => {
      const room = await loadRoom(tx, code);
      if (room.hostUid !== uid) throw new HttpsError('permission-denied', '只有房主可以開始遊戲');
      if (room.status === 'playing' && room.game?.phase !== 'finished') {
        throw new HttpsError('failed-precondition', '遊戲正在進行中');
      }
      if (hasBots(room) && !botServer()) {
        throw new HttpsError('failed-precondition', '電腦玩家的伺服器尚未設定，請先移除電腦玩家');
      }
      const state = rules.newGame(room.players.length, room.optionalRoles, rng, room.discussion,
        rules.expansionSettings(room.expansions));
      room.botSeed = randomInt(0, 2 ** 30);
      room.talk = [];
      const { open, secret } = rules.split(state);
      room.status = 'playing';
      room.gen += 1;
      room.game = open;
      room.away = [];
      room.privateExpireAt = Timestamp.fromMillis(expiry().toMillis() + GAME_DOCS_LEAD_MS);
      tx.set(roomRef(code), touch(room));
      tx.set(secretRef(code), { gen: room.gen, ...secret, expireAt: expiry() });
      room.playerUids.forEach((playerUid, seat) => {
        if (isBot(room, seat)) return; // nobody reads a computer's card
        tx.set(privateRef(code, playerUid), {
          gen: room.gen,
          seat,
          role: state.roles[seat],
          visible: rules.visibleSeats(state.roles, seat),
          lancelot: rules.knownLancelot(state.roles, seat),
          reveals: [],
          expireAt: room.privateExpireAt,
        });
      });
      return { gen: room.gen };
    });
  }),
);

/** Sends everyone back to the lobby so the host can change seats or roles. */
export const backToLobby = onCall(async (req) => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  return db.runTransaction(async (tx) => {
    const room = await loadRoom(tx, code);
    if (room.hostUid !== uid) throw new HttpsError('permission-denied', '只有房主可以返回大廳');
    room.status = 'lobby';
    room.game = null;
    room.away = [];
    room.talk = [];
    tx.set(roomRef(code), touch(room));
    tx.delete(secretRef(code));
    return { ok: true };
  });
});

// ───────────────────────── game moves ─────────────────────────

type Move =
  | 'endSpeech'
  | 'confirmIdentity'
  | 'proposeTeam'
  | 'vote'
  | 'continueVote'
  | 'playQuest'
  | 'continueQuest'
  | 'useLady'
  | 'continueLady'
  | 'useExcalibur'
  | 'continueExcalibur'
  | 'assassinate';

async function applyMove(
  tx: Transaction,
  code: string,
  uid: string,
  move: (state: GameState, seat: number, room: Room) => void | boolean,
) {
  const room = await loadRoom(tx, code);
  if (room.status !== 'playing' || !room.game) {
    throw new HttpsError('failed-precondition', '遊戲尚未開始');
  }
  const seat = seatOf(room, uid);
  const state = await loadState(tx, code, room);
  const revealed = state.reveals.length;
  if (move(state, seat, room) === false) return;
  // a move from a seat that was being played for: its player is back
  welcomeBack(room, seat);
  saveState(tx, code, room, state, revealed);
}

async function loadState(tx: Transaction, code: string, room: Room): Promise<GameState> {
  const secretSnap = await tx.get(secretRef(code));
  const secret = secretSnap.data();
  if (!secret || secret.gen !== room.gen) throw new HttpsError('internal', '遊戲資料不一致');
  return rules.join(room.game!, {
    roles: secret.roles,
    pendingVotes: secret.pendingVotes ?? {},
    pendingCards: secret.pendingCards ?? {},
    loyaltyDeck: secret.loyaltyDeck ?? [],
    reveals: secret.reveals ?? [],
    cardLog: secret.cardLog ?? {},
  });
}

/** Writes [state] back; [revealed] is how many reveals it had when loaded. */
function saveState(
  tx: Transaction, code: string, room: Room, state: GameState, revealed: number,
) {
  const split = rules.split(state);
  room.game = split.open;
  // The room and the secret state are renewed on every move; the players'
  // private documents (their roles) must outlive them. Renewing rewrites
  // each one whole from the secret state, so even one already deleted
  // comes back complete rather than as a bare deadline.
  const roomDeadline = expiry();
  const rebuilt = gameDocsRenewalDue(room.privateExpireAt, roomDeadline.toMillis());
  if (rebuilt) {
    room.privateExpireAt = Timestamp.fromMillis(roomDeadline.toMillis() + GAME_DOCS_LEAD_MS);
    room.playerUids.forEach((playerUid, playerSeat) => {
      if (isBot(room, playerSeat)) return;
      tx.set(privateRef(code, playerUid), {
        gen: room.gen,
        seat: playerSeat,
        role: state.roles[playerSeat],
        visible: rules.visibleSeats(state.roles, playerSeat),
        lancelot: rules.knownLancelot(state.roles, playerSeat),
        reveals: state.reveals.filter((x) => x.seat === playerSeat),
        expireAt: room.privateExpireAt,
      });
    });
  }
  tx.set(roomRef(code), touch(room));
  tx.set(secretRef(code), { gen: room.gen, ...split.secret, expireAt: expiry() });
  // what the Lady or Excalibur showed goes only to the player who used it
  // (already in place where the documents were just rebuilt)
  if (!rebuilt) {
    for (const r of state.reveals.slice(revealed)) {
      if (isBot(room, r.seat)) continue;
      tx.set(privateRef(code, room.playerUids[r.seat]), {
        reveals: state.reveals.filter((x) => x.seat === r.seat),
      }, { merge: true });
    }
  }
}

/** Continue buttons belong to the leader; the host can step in if needed. */
function mayAdvance(room: Room, state: GameState, seat: number) {
  if (seat !== state.leader && room.playerUids[seat] !== room.hostUid) {
    throw new HttpsError('permission-denied', '請等待隊長繼續');
  }
}

export const move = onCall((req) =>
  guarded(async () => {
    const uid = uidOf(req);
    const code = cleanCode(req.data?.code);
    const kind = str(req.data?.move, 'move') as Move;
    const data = req.data ?? {};
    await db.runTransaction((tx) =>
      applyMove(tx, code, uid, (state, seat, room) => {
        if (kind !== 'endSpeech' && data.generation !== undefined && data.generation !== room.gen) {
          throw new HttpsError('failed-precondition', '這局已更新，請依目前畫面重新操作');
        }
        if (kind !== 'endSpeech' && (
          (data.historyLength !== undefined && data.historyLength !== state.history.length) ||
          (data.rejections !== undefined && data.rejections !== state.rejections)
        )) {
          throw new HttpsError('failed-precondition', '這輪已更新，請依目前畫面重新操作');
        }
        if (kind === 'endSpeech' && data.generation !== room.gen) return false;
        return perform(room, state, seat, kind, data);
      }),
    );
    return { ok: true, serverNow: Date.now() };
  }),
);

/** One move by [seat], whoever is making it: the rules decide. */
function perform(
  room: Room, state: GameState, seat: number, kind: Move, data: Record<string, any>,
): void | boolean {
  switch (kind) {
    case 'endSpeech':
      return rules.endSpeech(state, seat, data.expectedVersion);
    case 'confirmIdentity':
      return rules.confirmIdentity(state, seat);
    case 'proposeTeam':
      return rules.proposeTeam(state, seat, data.team, Date.now(), data.excalibur ?? null);
    case 'vote':
      return rules.vote(state, seat, data.approve);
    case 'continueVote':
      mayAdvance(room, state, seat);
      return rules.continueVote(state);
    case 'playQuest':
      return rules.playQuest(state, seat, data.success, rng);
    case 'continueQuest':
      mayAdvance(room, state, seat);
      return rules.continueQuest(state);
    case 'useLady':
      return rules.useLady(state, seat, data.target);
    case 'continueLady':
      return rules.continueLady(state, seat);
    case 'useExcalibur':
      return rules.useExcalibur(state, seat, data.target ?? null, rng);
    case 'continueExcalibur':
      return rules.continueExcalibur(state, seat, rng);
    case 'assassinate':
      return rules.assassinate(state, seat, data.target, room.players.map((p) => p.name));
    default:
      throw new HttpsError('invalid-argument', '未知的操作');
  }
}

// ───────────────────────── computer players ─────────────────────────
//
// A computer sits in the room like a player, but its moves come from the
// computer players' server (bot_server/, the app's own solo reasoning),
// asked by `nudge`. That server is told everything about the game and
// answers for the computer seats only; every move it sends back goes
// through the same rules as a person's.

/** Where the computer players' server is, if it has been set up. */
function botServer(): { url: string; secret: string } | null {
  const url = (process.env.BOT_SERVER_URL ?? '').trim().replace(/\/+$/, '');
  const secret = process.env.BOT_SERVER_SECRET ?? '';
  return /^https?:\/\//.test(url) && secret.length >= 16 ? { url, secret } : null;
}

const CONTINUES: readonly Move[] =
  ['continueVote', 'continueQuest', 'continueLady', 'continueExcalibur'];

/** What the computers' server is sent: the whole game, the record so far. */
function botRequest(code: string, room: Room, state: GameState, away: readonly number[]) {
  return {
    room: code,
    gen: room.gen,
    seed: room.botSeed ?? 0,
    level: room.botLevel ?? 'normal',
    // a player who is away is played for like a computer until they are back
    players: room.players.map((p, seat) =>
      ({ name: p.name, bot: p.bot === true || away.includes(seat), persona: p.persona ?? null })),
    state,
    cards: state.cardLog,
    talk: room.talk ?? [],
  };
}

async function askBots(body: unknown): Promise<{ say: any[]; moves: any[] } | null> {
  const server = botServer();
  if (!server) return null;
  try {
    const response = await fetch(`${server.url}/step`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-bot-secret': server.secret },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) {
      console.error('computer players: HTTP', response.status, await response.text());
      return null;
    }
    const answer = (await response.json()) as { say?: unknown; moves?: unknown };
    return {
      say: Array.isArray(answer.say) ? answer.say : [],
      moves: Array.isArray(answer.moves) ? answer.moves : [],
    };
  } catch (e) {
    console.error('computer players: unreachable', e);
    return null;
  }
}

/**
 * Puts the computers' lines on the record and makes their moves, if the
 * game is still where it was when they were asked ([step]). Returns how
 * many lines and moves went in.
 */
async function applyBots(
  tx: Transaction, code: string, step: number, answer: { say: any[]; moves: any[] },
): Promise<number> {
  const snap = await tx.get(roomRef(code));
  const room = snap.data() as Room | undefined;
  if (!room || room.step !== step || room.status !== 'playing' || !room.game ||
      roomHasExpired(room.expireAt)) {
    return 0;
  }
  const state = await loadState(tx, code, room);
  const revealed = state.reveals.length;
  const sinceChange = room.updatedAt instanceof Timestamp
    ? Date.now() - room.updatedAt.toMillis() : Infinity;
  const talk = room.talk ?? [];
  // the seats the server may answer for: computers, and players marked away
  const played = (seat: number) => isBot(room, seat) || (room.away ?? []).includes(seat);
  let done = 0;
  for (const line of answer.say) {
    if (typeof line !== 'object' || line === null || !Number.isInteger(line.by) ||
        !played(line.by) || typeof line.text !== 'string' ||
        line.text.length === 0 || line.text.length > 400 ||
        JSON.stringify(line).length > 2000 || talk.length >= TALK_LIMIT) {
      continue;
    }
    talk.push({ ...line, bot: true, g: room.gen });
    done++;
  }
  for (const m of answer.moves) {
    if (typeof m !== 'object' || m === null || !Number.isInteger(m.seat) || !played(m.seat)) {
      continue;
    }
    // a result stays on the table long enough for people to look at it
    if (CONTINUES.includes(m.move) && (done > 0 || sinceChange < proxy.RESULT_VIEW_MS)) continue;
    try {
      if (perform(room, state, m.seat, m.move, m) === false) continue;
      done++;
    } catch (e) {
      if (!(e instanceof GameError) && !(e instanceof HttpsError)) throw e;
      console.error('computer players: move refused', m.move, (e as Error).message);
    }
    if (proxy.showsResult(state)) break;
  }
  if (done === 0) return 0;
  room.talk = talk;
  saveState(tx, code, room, state, revealed);
  return done;
}

/** The plain stand-in (proxy.ts) for the players marked away, if the game
 *  is still where it was ([step]). Returns how many moves it made. */
async function standInPlainly(tx: Transaction, code: string, step: number): Promise<number> {
  const snap = await tx.get(roomRef(code));
  const room = snap.data() as Room | undefined;
  if (!room || room.step !== step || room.status !== 'playing' || !room.game ||
      !room.away?.length || roomHasExpired(room.expireAt)) {
    return 0;
  }
  const state = await loadState(tx, code, room);
  const revealed = state.reveals.length;
  const now = Date.now();
  const sinceChange = room.updatedAt instanceof Timestamp ? now - room.updatedAt.toMillis() : Infinity;
  const moves = proxy.standIn(
    state, room.away, rng, room.players.map((p) => p.name), now, sinceChange);
  if (moves > 0) saveState(tx, code, room, state, revealed);
  return moves;
}

/** The host seats a computer in the lobby, or sends one away. */
export const setBot = onCall(async (req) => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  const persona = str(req.data?.persona, 'persona');
  if (!/^[a-z]{2,12}$/.test(persona)) throw new HttpsError('invalid-argument', '電腦玩家設定錯誤');
  const seated = req.data?.seated === true;
  const name = seated ? cleanName(req.data?.name) : '';
  return db.runTransaction(async (tx) => {
    const room = await loadRoom(tx, code);
    if (room.hostUid !== uid) throw new HttpsError('permission-denied', '只有房主可以安排電腦玩家');
    if (room.status !== 'lobby') throw new HttpsError('failed-precondition', '請先返回大廳');
    const botUid = `bot:${persona}`;
    const seat = room.playerUids.indexOf(botUid);
    if (!seated) {
      if (seat < 0) return { ok: true };
      room.players.splice(seat, 1);
      room.playerUids.splice(seat, 1);
    } else {
      if (seat >= 0) return { ok: true };
      if (!botServer()) throw new HttpsError('failed-precondition', '電腦玩家的伺服器尚未設定');
      if (room.players.some((p) => !p.bot && (p.protocol ?? 1) < BOTS_PROTOCOL)) {
        throw new HttpsError('failed-precondition', '請所有玩家更新 App 並重新加入房間後，再加入電腦玩家');
      }
      if (room.players.length >= rules.MAX_PLAYERS) {
        throw new HttpsError('failed-precondition', '房間已滿（最多 10 人）');
      }
      // a computer is never the reason a setting cannot be turned on
      room.players.push({ uid: botUid, name, bot: true, persona, supportsDiscussion: true });
      room.playerUids.push(botUid);
    }
    tx.set(roomRef(code), touch(room));
    return { ok: true };
  });
});

export const setBotLevel = onCall(async (req) => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  const level = req.data?.level;
  if (!BOT_LEVELS.includes(level)) throw new HttpsError('invalid-argument', '難度設定錯誤');
  return db.runTransaction(async (tx) => {
    const room = await loadRoom(tx, code);
    if (room.hostUid !== uid) throw new HttpsError('permission-denied', '只有房主可以設定電腦難度');
    if (room.status !== 'lobby') throw new HttpsError('failed-precondition', '請先返回大廳');
    room.botLevel = level;
    tx.set(roomRef(code), touch(room));
    return { ok: true };
  });
});

/**
 * A line typed by the player whose turn it is to speak. It goes on the
 * record as typed; the computers read it for themselves.
 */
export const say = onCall(async (req) => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  const text = str(req.data?.text, 'text').replace(/\s+/g, ' ').trim();
  if (text.length < 1 || text.length > LINE_LENGTH) {
    throw new HttpsError('invalid-argument', `發言需為 1～${LINE_LENGTH} 個字`);
  }
  return db.runTransaction(async (tx) => {
    const room = await loadRoom(tx, code);
    const seat = seatOf(room, uid);
    const game = room.game;
    if (room.status !== 'playing' || !game) throw new HttpsError('failed-precondition', '遊戲尚未開始');
    if (req.data?.generation !== undefined && req.data.generation !== room.gen) {
      throw new HttpsError('failed-precondition', '這局已更新，請依目前畫面重新操作');
    }
    const speaker = game.phase === 'discussion'
      ? (game.leader + 1 + game.speechIndex) % room.players.length : null;
    if (seat !== speaker) throw new HttpsError('failed-precondition', '輪到你發言時才能送出');
    const talk = room.talk ?? [];
    const mine = talk.filter((l) => l.by === seat && l.sv === game.speechVersion && l.bot !== true);
    if (mine.length >= 3 || talk.length >= TALK_LIMIT) {
      throw new HttpsError('failed-precondition', '這次發言已經說得夠多了');
    }
    talk.push({
      by: seat, q: game.history.length + 1, a: game.rejections + 1, g: room.gen,
      sv: game.speechVersion, team: game.team, switched: game.lancelotSwitched === true, text,
    });
    room.talk = talk;
    welcomeBack(room, seat);
    tx.set(roomRef(code), touch(room));
    return { ok: true };
  });
});

/**
 * Sent by a phone that has waited a while for the game to move. Whoever
 * has not been heard from for a minute is marked away and played for; a
 * player who is back is taken off the list. Being away is judged here,
 * from what each phone itself reports, never on the caller's word.
 */
export const nudge = onCall((req) =>
  guarded(async () => {
    const uid = uidOf(req);
    const code = cleanCode(req.data?.code);
    const first = await db.runTransaction(async (tx) => {
      const room = await loadRoom(tx, code);
      const caller = seatOf(room, uid);
      if (room.status !== 'playing' || !room.game) return { moves: 0, ask: null };
      const now = Date.now();
      const seen = await Promise.all(
        room.playerUids.map((playerUid) => tx.get(presenceRef(code, playerUid))));
      const away = room.playerUids.map((_, seat) => seat).filter((seat) => {
        // the caller is plainly here; older apps do not report at all
        if (seat === caller || (room.players[seat].protocol ?? 1) < proxy.PRESENCE_PROTOCOL) {
          return false;
        }
        const at = seen[seat].data()?.at;
        return proxy.isAway(at instanceof Timestamp ? at.toMillis() : null, now);
      });
      const before = room.away ?? [];
      const left = away.filter((x) => !before.includes(x));
      const back = before.filter((x) => !away.includes(x));
      let moves = 0, revealed = 0;
      let state: GameState | null = null;
      const bots = room.playerUids.map((_, seat) => seat).filter((seat) => isBot(room, seat));
      // With the computer players' server set up, it plays for whoever is
      // away as well, with the same reasoning as a computer seat. Without
      // it (or when it cannot be reached, below) the plain stand-in does.
      const served = botServer() != null;
      if ((away.length > 0 || bots.length > 0) && room.game.phase !== 'finished') {
        state = await loadState(tx, code, room);
        revealed = state.reveals.length;
        if (!served) {
          const sinceChange = room.updatedAt instanceof Timestamp
            ? now - room.updatedAt.toMillis() : Infinity;
          moves = proxy.standIn(state, away, rng, room.players.map((p) => p.name), now, sinceChange);
        }
      }
      const written = moves > 0 || left.length > 0 || back.length > 0;
      // the game now waits for a seat the server plays: it is asked once
      // this transaction is through (never from inside it)
      const asked = served ? [...bots, ...away] : bots;
      const ask = state && asked.some((seat) => proxy.pending(state!, seat))
        ? { step: room.step + (written ? 1 : 0), body: botRequest(code, room, state, served ? away : []) }
        : null;
      if (!written) return { moves: 0, ask };
      room.away = away;
      const label = (seat: number) => `${seat + 1} 號 ${room.players[seat].name}`;
      if (left.length > 0) {
        room.notice = `${left.map(label).join('、')} 斷線了，暫時由電腦代理`;
        room.noticeStep = room.step + 1;
      } else if (back.length > 0) {
        room.notice = `${back.map(label).join('、')} 回來了，交還本人操作`;
        room.noticeStep = room.step + 1;
      }
      if (state && moves > 0) saveState(tx, code, room, state, revealed);
      else tx.set(roomRef(code), touch(room));
      return { moves, ask };
    });
    if (!first.ask) return { moves: first.moves };
    const { step, body } = first.ask;
    const answer = await askBots(body);
    if (!answer) {
      // the server cannot be reached: nobody is left waiting for a player
      // who is away (the computer seats wait for the server to come back)
      const stood = await db.runTransaction((tx) => standInPlainly(tx, code, step));
      return { moves: first.moves + stood };
    }
    if (answer.say.length === 0 && answer.moves.length === 0) return { moves: first.moves };
    const done = await db.runTransaction((tx) => applyBots(tx, code, step, answer));
    return { moves: first.moves + done };
  }),
);

export const serverTime = onCall((req) => {
  uidOf(req);
  return { serverNow: Date.now() };
});

export const setExpansions = onCall((req) => guarded(async () => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  const expansions = rules.expansionSettings(req.data?.expansions);
  return db.runTransaction(async (tx) => {
    const room = await loadRoom(tx, code);
    if (room.hostUid !== uid) throw new HttpsError('permission-denied', '只有房主可以設定擴充');
    if (room.status !== 'lobby') throw new HttpsError('failed-precondition', '請先返回大廳');
    if (rules.anyExpansion(expansions) && room.players.some((p) => !p.bot && (p.protocol ?? 1) < 3)) {
      throw new HttpsError('failed-precondition', '請所有玩家更新 App 並重新加入房間後，再開啟擴充');
    }
    room.expansions = expansions;
    tx.set(roomRef(code), touch(room));
    return { ok: true };
  });
}));

export const setDiscussion = onCall((req) => guarded(async () => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  const settings = rules.discussionSettings(req.data?.discussion);
  return db.runTransaction(async (tx) => {
    const room = await loadRoom(tx, code);
    if (room.hostUid !== uid) throw new HttpsError('permission-denied', '只有房主可以設定發言');
    if (room.status !== 'lobby') throw new HttpsError('failed-precondition', '請先返回大廳');
    if (settings.enabled && room.players.some((p) => !p.supportsDiscussion)) {
      throw new HttpsError('failed-precondition', '請所有玩家更新 App 並重新加入房間後，再開啟依序發言');
    }
    room.discussion = settings;
    tx.set(roomRef(code), touch(room));
    return { ok: true };
  });
}));
