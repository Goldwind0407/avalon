// Cloud Functions: the referee for online games.
//
// Devices never write to Firestore directly (see firestore.rules). Every
// move is a callable function that checks who is calling, applies the rules
// from rules.ts inside a transaction, and writes three kinds of documents:
//
//   rooms/{code}                public table state, readable by the players
//   rooms/{code}/private/{uid}  one player's role and what they can see
//   rooms/{code}/secret/state   all roles, unrevealed votes and quest cards

import { randomInt } from 'node:crypto';
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

initializeApp();
setGlobalOptions({ region: 'asia-east1', maxInstances: 20 });
const db = getFirestore();

/** Rooms are kept for a day; set a TTL policy on `expireAt` to clean up. */
const ROOM_LIFETIME_MS = 24 * 60 * 60 * 1000;
const rng: rules.Rng = () => randomInt(0, 2 ** 32) / 2 ** 32;

interface Player {
  uid: string;
  name: string;
}

interface Room {
  code: string;
  hostUid: string;
  status: 'lobby' | 'playing';
  players: Player[];
  playerUids: string[];
  optionalRoles: RoleKey[];
  /** Increases every time a new game is dealt in this room. */
  gen: number;
  /** Increases on every change, so devices can tell updates apart. */
  step: number;
  game: Omit<GameState, (typeof rules.SECRET_KEYS)[number]> | null;
}

const roomRef = (code: string) => db.collection('rooms').doc(code);
const secretRef = (code: string) => roomRef(code).collection('secret').doc('state');
const privateRef = (code: string, uid: string) =>
  roomRef(code).collection('private').doc(uid);

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
  return snap.data() as Room;
}

function seatOf(room: Room, uid: string): number {
  const seat = room.playerUids.indexOf(uid);
  if (seat < 0) throw new HttpsError('permission-denied', '你不在這個房間裡');
  return seat;
}

function touch(room: Room) {
  return {
    ...room,
    step: room.step + 1,
    updatedAt: FieldValue.serverTimestamp(),
    expireAt: Timestamp.fromMillis(Date.now() + ROOM_LIFETIME_MS),
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
        players: [{ uid, name }],
        playerUids: [uid],
        optionalRoles: [],
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
    // Coming back to a room you are already in (reopened the app, lost
    // connection) just takes you back to your seat.
    if (seat >= 0) return { code, seat };
    if (room.status !== 'lobby') throw new HttpsError('failed-precondition', '遊戲已經開始，無法加入');
    if (room.players.length >= rules.MAX_PLAYERS) {
      throw new HttpsError('failed-precondition', '房間已滿（最多 10 人）');
    }
    room.players.push({ uid, name });
    room.playerUids.push(uid);
    tx.set(roomRef(code), touch(room));
    return { code, seat: room.players.length - 1 };
  });
});

export const leaveRoom = onCall(async (req) => {
  const uid = uidOf(req);
  const code = cleanCode(req.data?.code);
  return db.runTransaction(async (tx) => {
    const room = await loadRoom(tx, code);
    const seat = room.playerUids.indexOf(uid);
    if (seat < 0) return { left: true };
    // Seats are fixed once cards are dealt; leaving mid-game would break it.
    if (room.status !== 'lobby') return { left: false };
    room.players.splice(seat, 1);
    room.playerUids.splice(seat, 1);
    if (room.players.length === 0) {
      tx.delete(roomRef(code));
      return { left: true };
    }
    if (room.hostUid === uid) room.hostUid = room.playerUids[0];
    tx.set(roomRef(code), touch(room));
    return { left: true };
  });
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
      const state = rules.newGame(room.players.length, room.optionalRoles, rng);
      const { open, secret } = rules.split(state);
      room.status = 'playing';
      room.gen += 1;
      room.game = open;
      tx.set(roomRef(code), touch(room));
      tx.set(secretRef(code), { gen: room.gen, ...secret });
      room.playerUids.forEach((playerUid, seat) => {
        tx.set(privateRef(code, playerUid), {
          gen: room.gen,
          seat,
          role: state.roles[seat],
          visible: rules.visibleSeats(state.roles, seat),
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
    tx.set(roomRef(code), touch(room));
    tx.delete(secretRef(code));
    return { ok: true };
  });
});

// ───────────────────────── game moves ─────────────────────────

type Move =
  | 'confirmIdentity'
  | 'proposeTeam'
  | 'vote'
  | 'continueVote'
  | 'playQuest'
  | 'continueQuest'
  | 'assassinate';

async function applyMove(
  tx: Transaction,
  code: string,
  uid: string,
  move: (state: GameState, seat: number, room: Room) => void,
) {
  const room = await loadRoom(tx, code);
  if (room.status !== 'playing' || !room.game) {
    throw new HttpsError('failed-precondition', '遊戲尚未開始');
  }
  const seat = seatOf(room, uid);
  const secretSnap = await tx.get(secretRef(code));
  const secret = secretSnap.data();
  if (!secret || secret.gen !== room.gen) throw new HttpsError('internal', '遊戲資料不一致');
  const state = rules.join(room.game, {
    roles: secret.roles,
    pendingVotes: secret.pendingVotes ?? {},
    pendingCards: secret.pendingCards ?? {},
  });
  move(state, seat, room);
  const split = rules.split(state);
  room.game = split.open;
  tx.set(roomRef(code), touch(room));
  tx.set(secretRef(code), { gen: room.gen, ...split.secret });
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
        switch (kind) {
          case 'confirmIdentity':
            return rules.confirmIdentity(state, seat);
          case 'proposeTeam':
            return rules.proposeTeam(state, seat, data.team);
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
          case 'assassinate':
            return rules.assassinate(
              state,
              seat,
              data.target,
              room.players.map((p) => p.name),
            );
          default:
            throw new HttpsError('invalid-argument', '未知的操作');
        }
      }),
    );
    return { ok: true };
  }),
);
