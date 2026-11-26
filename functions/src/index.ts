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
import * as limits from './limits';
import * as proxy from './proxy';
import { cloudflareIceServers, voiceIceServers } from './voice_ice';
import { DAILY_REPORTS, REPORT_LIFETIME_MS, cleanPerfReport } from './perf_report';
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
/** The whole of a finished game, for everyone who played it to look back
 *  on (roles, every card, what the Lady showed, the computers' reasons). */
const reviewRef = (code: string, room: Room) =>
  roomRef(code).collection('reviews').doc(gameDocId(room));

/** Finished games of a room with computers, for them to remember (server
 *  only: every role and card, as at the end). */
const pastRef = (code: string, room: Room) =>
  roomRef(code).collection('pastGames').doc(gameDocId(room));

/**
 * A finished game's id under its room: the room's own id with the deal
 * number. A code is used again once its room is gone, while what was kept
 * of the old room's games lasts a while longer (TTL), and deals count from
 * the start in every room: by number alone, a new room's first game would
 * write over the old room's.
 */
const gameDocId = (room: Room) => `${room.voiceRoomId}-${room.gen}`;
/** How many finished games the computers are told about. */
const PAST_GAMES = 5;

/** Written by each phone every 20 s (firestore.rules); read only here. */
const presenceRef = (code: string, uid: string) =>
  roomRef(code).collection('presence').doc(uid);

/** What one player has been doing lately, for [limits] (server only). */
const limitRef = (uid: string) => db.collection('limits').doc(uid);

/** Refuses when [uid] has done [kind] too often lately. */
/** What [uid] has done lately, read inside [tx] (before its writes). */
async function readLimits(tx: Transaction, uid: string) {
  return (await tx.get(limitRef(uid))).data() ?? {};
}

/** Refuses when [data] (from [readLimits]) shows [kind] done too often. */
function checkLimit(data: Record<string, unknown>, kind: limits.LimitKind) {
  const wait = limits.waitMs(data[kind], Date.now(), limits.LIMITS[kind]);
  if (wait > 0) {
    throw new HttpsError('resource-exhausted',
      kind === 'create'
        ? `建立房間太頻繁，請 ${Math.ceil(wait / 60000)} 分鐘後再試`
        : `輸入錯誤的房號太多次，請 ${Math.ceil(wait / 60000)} 分鐘後再試`);
  }
}

/** Counts one more [kind] for [uid], in the transaction that checked it,
 *  so requests sent at once cannot all slip under the limit. */
function countLimit(tx: Transaction, uid: string, data: Record<string, unknown>,
  kind: limits.LimitKind) {
  const limit = limits.LIMITS[kind];
  const now = Date.now();
  tx.set(limitRef(uid), {
    [kind]: [...limits.recent(data[kind], now, limit), now].slice(-limit.max),
    // forgotten a day after the last use (TTL on expireAt)
    expireAt: Timestamp.fromMillis(now + 24 * 60 * 60 * 1000),
  }, { merge: true });
}

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

/**
 * Online play is for signed-in Google accounts (REQUIRE_GOOGLE=true):
 * anonymous accounts cost nothing to make, so limits per account would not
 * hold. Without the setting (the emulators, tests) anyone signed in plays.
 */
function requireAccount(req: CallableRequest) {
  const provider = (req.auth?.token as { firebase?: { sign_in_provider?: string } } | undefined)
    ?.firebase?.sign_in_provider;
  if (process.env.REQUIRE_GOOGLE === 'true' && provider === 'anonymous') {
    throw new HttpsError('permission-denied', '多機遊玩需要先用 Google 登入，請更新 App 後再試');
  }
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
  requireAccount(req);
  return db.runTransaction(async (tx) => {
    const used = await readLimits(tx, uid);
    checkLimit(used, 'create');
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
      countLimit(tx, uid, used, 'create');
      return { code };
    }
    throw new HttpsError('resource-exhausted', '暫時無法建立房間，請稍後再試');
  });
});

export const joinRoom = onCall(async (req) => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  const name = cleanName(req.data?.name);
  const joined = await joinRoomNow(req, uid, code, name);
  // a code that leads nowhere is counted (in the same transaction) and
  // only then refused, so the count is kept
  if (joined === null) throw new HttpsError('not-found', '找不到這個房間');
  return joined;
});

function joinRoomNow(req: CallableRequest, uid: string, code: string, name: string) {
  return db.runTransaction(async (tx) => {
    const used = await readLimits(tx, uid);
    checkLimit(used, 'miss');
    const snap = await tx.get(roomRef(code));
    if (!snap.exists) {
      countLimit(tx, uid, used, 'miss');
      return null;
    }
    const room = snap.data() as Room;
    if (roomHasExpired(room.expireAt)) {
      throw new HttpsError('failed-precondition', '房間已到期');
    }
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
    // a new seat takes a Google account; coming back to one's own does not
    requireAccount(req);
    if (room.status !== 'lobby') throw new HttpsError('failed-precondition', '遊戲已經開始，無法加入');
    if (room.players.length >= rules.MAX_PLAYERS) {
      throw new HttpsError('failed-precondition', '房間已滿（最多 10 人）');
    }
    room.players.push({ uid, name, supportsDiscussion, protocol });
    room.playerUids.push(uid);
    tx.set(roomRef(code), touch(room));
    return { code, seat: room.players.length - 1 };
  });
}

/**
 * The rooms where the caller still has a seat, most recently active
 * first: how a phone that dropped out (or a new phone, signed in to the
 * same account) finds its way back without the code.
 */
export const myRooms = onCall(async (req) => {
  const uid = uidOf(req);
  const found = await db.collection('rooms')
    .where('playerUids', 'array-contains', uid).limit(10).get();
  const rooms = found.docs
    .map((d) => d.data() as Room)
    .filter((room) => !roomHasExpired(room.expireAt))
    .sort((a, b) => (b.updatedAt?.toMillis() ?? 0) - (a.updatedAt?.toMillis() ?? 0))
    .slice(0, 3)
    .map((room) => ({
      code: room.code,
      status: room.status,
      players: room.players.length,
      host: room.players.find((p) => p.uid === room.hostUid)?.name ?? '',
      finished: room.game?.phase === 'finished',
    }));
  return { rooms };
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

/** Optional managed or self-hosted TURN for valid room members. */
export const voiceIce = onCall(async (req) => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  await db.runTransaction(async tx => {
    const room = await loadRoom(tx, code);
    seatOf(room, uid);
  });
  const keyId = process.env.VOICE_CLOUDFLARE_TURN_KEY_ID?.trim();
  const token = process.env.VOICE_CLOUDFLARE_TURN_TOKEN?.trim();
  if (keyId && token) {
    try {
      return { iceServers: await cloudflareIceServers(keyId, token) };
    } catch {
      console.warn('Cloudflare TURN credentials unavailable; using the configured ICE fallback.');
    }
  }
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
    botReasons: secret.botReasons ?? {},
  });
}

/** Writes [state] back; [revealed] is how many reveals it had when loaded. */
function saveState(
  tx: Transaction, code: string, room: Room, state: GameState, revealed: number,
) {
  const split = rules.split(state);
  if (state.phase === 'finished' && room.game?.phase !== 'finished') {
    const players = room.players.map((p) =>
      ({ uid: p.uid, name: p.name, bot: p.bot === true, persona: p.persona ?? null }));
    // the game, as it ended, for the players to look back on
    tx.set(reviewRef(code, room), {
      gen: room.gen,
      roomId: room.voiceRoomId,
      players,
      // who may read it: the people who played it, not whoever is in the
      // room later
      uids: room.players.filter((p) => !p.bot).map((p) => p.uid),
      state,
      talk: room.talk ?? [],
      botLevel: room.botLevel ?? 'normal',
      endedAt: Date.now(),
      expireAt: Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000),
    });
    // and for the computers to remember
    if (hasBots(room)) {
      tx.set(pastRef(code, room), {
        gen: room.gen, roomId: room.voiceRoomId, players, state, talk: room.talk ?? [],
        expireAt: expiry(),
      });
    }
  }
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
function botRequest(
  code: string, room: Room, state: GameState, away: readonly number[], past?: unknown[],
) {
  return {
    // only when read (with the first quest, or when asked for): absent, the
    // computers keep what they took in, or ask for it again (needPast)
    ...(past ? { past } : {}),
    room: code,
    gen: room.gen,
    seed: room.botSeed ?? 0,
    level: room.botLevel ?? 'normal',
    // a person who is away is played for until back, but stays a person
    // (with their account, for the computers' memory of them)
    players: room.players.map((p, seat) => ({
      uid: p.uid, name: p.name, bot: p.bot === true, away: away.includes(seat),
      persona: p.persona ?? null,
    })),
    state,
    cards: state.cardLog,
    talk: room.talk ?? [],
  };
}

/** Words without which a line says nothing about a Lady check. */
const LADY_WORDS = /湖|女神|查|驗/;

/**
 * The Lady results [text], typed by [uid] in room [code], claims: as the
 * computers' server reads it. Empty without that server (a test setup);
 * null when it is set up but cannot be reached, so cannot tell.
 */
async function ladyClaimsOf(code: string, uid: string, text: string):
  Promise<{ target: number; evil: boolean }[] | null> {
  const server = botServer();
  if (!server) return [];
  const room = (await roomRef(code).get()).data() as Room | undefined;
  const seat = room?.playerUids.indexOf(uid) ?? -1;
  if (!room || seat < 0) return [];
  try {
    const response = await fetch(`${server.url}/speech`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-bot-secret': server.secret },
      body: JSON.stringify({ text, names: room.players.map((p) => p.name), seat }),
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) return null;
    const answer = (await response.json()) as { lady?: unknown };
    if (!Array.isArray(answer.lady)) return null;
    return answer.lady.filter((c): c is { target: number; evil: boolean } =>
      typeof c?.target === 'number' && typeof c?.evil === 'boolean');
  } catch (e) {
    console.error('computer players: unreachable for speech', e);
    return null;
  }
}

type BotAnswer = { say: any[]; moves: any[]; needPast: boolean };

/** The room's games before deal [gen], newest first, for the computers'
 *  memory (in [tx] when given). */
async function pastGames(code: string, roomId: string, gen: number, tx?: Transaction) {
  // this room's own games (not those of an earlier room with the same
  // code), newest first, sorted and cut short by the database (index in
  // firestore.indexes.json): a room that played many games reads only a
  // few. A few more than needed, for any past their time but not yet
  // cleared away (TTL is not immediate).
  const query = roomRef(code).collection('pastGames')
    .where('roomId', '==', roomId).where('gen', '<', gen)
    .orderBy('gen', 'desc').limit(PAST_GAMES + 3);
  const kept = tx ? await tx.get(query) : await query.get();
  const now = Date.now();
  return kept.docs
    .map((d) => d.data())
    .filter((g) => !(g.expireAt instanceof Timestamp && g.expireAt.toMillis() <= now))
    .slice(0, PAST_GAMES)
    .map(({ expireAt: _, roomId: __, ...game }) => game);
}

async function askBots(body: unknown): Promise<BotAnswer | null> {
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
    const answer = (await response.json()) as { say?: unknown; moves?: unknown; needPast?: unknown };
    return {
      say: Array.isArray(answer.say) ? answer.say : [],
      moves: Array.isArray(answer.moves) ? answer.moves : [],
      needPast: answer.needPast === true,
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
  // someone who was away may be back by now: they play for themselves
  const returned = await welcomeBackThoseHere(tx, code, room);
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
      // the proposal being voted on: it goes on the record with the last vote
      const proposal = state.proposals.length;
      if (perform(room, state, m.seat, m.move, m) === false) continue;
      done++;
      const why = m.move === 'vote' ? m.why : null;
      if (why && typeof why === 'object' && typeof why.reason === 'string' &&
          why.reason.length <= 40 && Array.isArray(why.doubt) && why.doubt.length <= 10 &&
          why.doubt.every((d: unknown) => typeof d === 'number')) {
        state.botReasons[`${proposal}/${m.seat}`] = {
          approve: m.approve === true,
          reason: why.reason,
          risk: typeof why.risk === 'number' ? why.risk : 0,
          doubt: why.doubt,
        };
      }
    } catch (e) {
      if (!(e instanceof GameError) && !(e instanceof HttpsError)) throw e;
      console.error('computer players: move refused', m.move, (e as Error).message);
    }
    if (proxy.showsResult(state)) break;
  }
  if (done === 0 && !returned) return 0;
  room.talk = talk;
  saveState(tx, code, room, state, revealed);
  return done;
}

/**
 * Takes the players marked away who have reported in since (read inside
 * [tx], before its writes) off the list; returns whether anyone was.
 */
async function welcomeBackThoseHere(tx: Transaction, code: string, room: Room) {
  const away = room.away ?? [];
  if (away.length === 0) return false;
  const now = Date.now();
  const seen = await Promise.all(
    away.map((seat) => tx.get(presenceRef(code, room.playerUids[seat]))));
  let back = false;
  away.forEach((seat, i) => {
    const at = seen[i].data()?.at;
    if (!proxy.isAway(at instanceof Timestamp ? at.toMillis() : null, now)) {
      back = welcomeBack(room, seat) || back;
    }
  });
  return back;
}

/** The plain stand-in (proxy.ts) for the players marked away, if the game
 *  is still where it was ([step]). Returns how many moves it made. */
/**
 * How long a game may stand still on a computer seat, with the computers'
 * server out of reach, before the plain stand-in moves for it (a passing
 * blip is waited out; a server that is down does not stop the game).
 */
const BOT_FALLBACK_MS = 20 * 1000;

async function standInPlainly(tx: Transaction, code: string, step: number): Promise<number> {
  const snap = await tx.get(roomRef(code));
  const room = snap.data() as Room | undefined;
  if (!room || room.step !== step || room.status !== 'playing' || !room.game ||
      roomHasExpired(room.expireAt)) {
    return 0;
  }
  const now = Date.now();
  const sinceChange = room.updatedAt instanceof Timestamp ? now - room.updatedAt.toMillis() : Infinity;
  const bots = sinceChange >= BOT_FALLBACK_MS
    ? room.playerUids.map((_, seat) => seat).filter((seat) => isBot(room, seat))
    : [];
  if (!room.away?.length && bots.length === 0) return 0;
  const state = await loadState(tx, code, room);
  const revealed = state.reveals.length;
  const returned = await welcomeBackThoseHere(tx, code, room);
  const seats = [...(room.away ?? []), ...bots];
  const botMoved = bots.some((seat) => proxy.pending(state, seat));
  const moves = proxy.standIn(
    state, seats, rng, room.players.map((p) => p.name), now, sinceChange);
  if (moves > 0 && botMoved) {
    room.notice = '電腦玩家的伺服器暫時連不上，電腦先用簡易方式出手';
    room.noticeStep = room.step + 1;
  }
  if (moves > 0 || returned) saveState(tx, code, room, state, revealed);
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
 * The Lady's holder tells the table what the check showed (true or not:
 * the holder may lie), once, while the result is on the table. It goes on
 * the record for everyone, the computers included.
 */
export const announceLady = onCall(async (req) => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  const evil = req.data?.evil;
  if (typeof evil !== 'boolean') throw new HttpsError('invalid-argument', '請選擇要公布的結果');
  return db.runTransaction(async (tx) => {
    const room = await loadRoom(tx, code);
    const seat = seatOf(room, uid);
    const game = room.game;
    if (room.status !== 'playing' || !game || game.phase !== 'ladyResult') {
      throw new HttpsError('failed-precondition', '現在不能公布查驗結果');
    }
    if (req.data?.generation !== undefined && req.data.generation !== room.gen) {
      throw new HttpsError('failed-precondition', '這局已更新，請依目前畫面重新操作');
    }
    const check = game.ladyChecks[game.ladyChecks.length - 1];
    if (!check || check.holder !== seat) {
      throw new HttpsError('permission-denied', '只有湖中女神持有者可以公布');
    }
    // a good player tells the truth about it (house rule); evil may lie
    const state = await loadState(tx, code, room);
    if (rules.misreportsLady(state, seat, [{ target: check.target, evil }])) {
      throw new HttpsError('failed-precondition', '好人不能謊報湖中女神的結果');
    }
    const talk = room.talk ?? [];
    const said = talk.some((l) => l.g === room.gen && (l.lady as { quest?: number } | undefined)?.quest === check.quest);
    if (said) return { ok: true };
    if (talk.length >= TALK_LIMIT) throw new HttpsError('failed-precondition', '這局的發言已經太多了');
    talk.push({
      by: seat, q: game.history.length + 1, a: game.rejections + 1, g: room.gen,
      team: [], switched: game.lancelotSwitched === true,
      text: `我用湖中女神查驗了${check.target + 1}號，他是${evil ? '邪惡' : '正義'}陣營。`,
      lady: { target: check.target, evil, quest: check.quest },
    });
    room.talk = talk;
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
  // the deal and speaking turn the line was typed in: without them a line
  // that arrives late could be hung on a later turn (apps before these
  // were sent are asked to update)
  const generation = req.data?.generation, expectedVersion = req.data?.expectedVersion;
  if (typeof generation !== 'number' || typeof expectedVersion !== 'number') {
    throw new HttpsError('failed-precondition', '請更新 App 後再發言');
  }
  // what the line says about Lady checks, read the way the computers read
  // it (only for a line that may be about one)
  const claims = LADY_WORDS.test(text) ? await ladyClaimsOf(code, uid, text) : [];
  return db.runTransaction(async (tx) => {
    const room = await loadRoom(tx, code);
    const seat = seatOf(room, uid);
    const game = room.game;
    if (room.status !== 'playing' || !game) throw new HttpsError('failed-precondition', '遊戲尚未開始');
    if (generation !== room.gen) {
      throw new HttpsError('failed-precondition', '這局已更新，請依目前畫面重新操作');
    }
    const speaker = game.phase === 'discussion'
      ? (game.leader + 1 + game.speechIndex) % room.players.length : null;
    if (seat !== speaker) throw new HttpsError('failed-precondition', '輪到你發言時才能送出');
    // a line typed in an earlier turn (it took long to arrive) is not
    // hung on this one
    if (expectedVersion !== game.speechVersion) {
      throw new HttpsError('failed-precondition', '這次發言已經結束了');
    }
    // a good player does not misreport a Lady result of their own, typed
    // any more than announced (house rule; the app checks it too)
    if (LADY_WORDS.test(text)) {
      const state = await loadState(tx, code, room);
      const checked = state.reveals.some((r) => r.seat === seat && r.kind === 'lady');
      if (checked && !rules.evilNow(state, seat)) {
        if (claims === null) {
          throw new HttpsError('unavailable', '暫時無法確認湖中女神的說法，請稍後再送');
        }
        if (rules.misreportsLady(state, seat, claims)) {
          throw new HttpsError('failed-precondition', '好人不能謊報湖中女神的結果');
        }
      }
    }
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
      // whether each person is still here (a computer never reports: its
      // presence is not read, which would cost a read for nothing)
      const watched = room.playerUids.map((_, seat) => seat).filter((seat) =>
        seat !== caller && !isBot(room, seat) &&
        (room.players[seat].protocol ?? 1) >= proxy.PRESENCE_PROTOCOL);
      const seen = await Promise.all(
        watched.map((seat) => tx.get(presenceRef(code, room.playerUids[seat]))));
      const away = watched.filter((seat, i) => {
        const at = seen[i].data()?.at;
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
      let past: unknown[] | undefined;
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
      const needed = state != null && asked.some((seat) => proxy.pending(state!, seat));
      // earlier games are for the computers' memory, which they take in as
      // a game begins: only read when they are asked during the first quest
      // (and again only if their server has lost them: needPast)
      if (needed && served && bots.length > 0 && state!.history.length === 0) {
        past = await pastGames(code, room.voiceRoomId, room.gen, tx);
      }
      const ask = needed
        ? {
          step: room.step + (written ? 1 : 0),
          roomId: room.voiceRoomId,
          body: botRequest(code, room, state!, served ? away : [], past),
        }
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
    const { step, body, roomId } = first.ask;
    let answer = await askBots(body);
    // the computers' server was restarted (or another instance answered)
    // after the first quest: it wants the earlier games again
    if (answer?.needPast && !('past' in body)) {
      answer = await askBots({ ...body, past: await pastGames(code, roomId, body.gen) });
    }
    if (!answer) {
      // the server cannot be reached: nobody is left waiting for a player
      // who is away, nor long for a computer seat (BOT_FALLBACK_MS)
      const stood = await db.runTransaction((tx) => standInPlainly(tx, code, step));
      return { moves: first.moves + stood };
    }
    if (answer.say.length === 0 && answer.moves.length === 0) return { moves: first.moves };
    const done = await db.runTransaction((tx) => applyBots(tx, code, step, answer));
    return { moves: first.moves + done };
  }),
);

/**
 * How smoothly the web game draws on a device (lib/core/web_perf_web.dart).
 * Needs no sign-in: it is sent from any page, even before signing in, and
 * says nothing about who sent it. Kept 30 days, at most [DAILY_REPORTS] a day.
 */
export const perfReport = onCall({ maxInstances: 2 }, async (req) => {
  const report = cleanPerfReport(req.data);
  if (!report) return { ok: false };
  const day = new Date().toISOString().slice(0, 10);
  const counter = db.doc(`perfDays/${day}`);
  const kept = await db.runTransaction(async (tx) => {
    const seen = ((await tx.get(counter)).data()?.count as number) ?? 0;
    if (seen >= DAILY_REPORTS) return false;
    const expireAt = Timestamp.fromMillis(Date.now() + REPORT_LIFETIME_MS);
    tx.set(counter, { count: seen + 1, expireAt });
    tx.create(db.collection('perfReports').doc(), {
      ...report, at: FieldValue.serverTimestamp(), expireAt,
    });
    return true;
  });
  return { ok: kept };
});

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
