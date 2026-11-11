// End-to-end test: several "phones" sign in anonymously, play a whole game
// through the callable functions, and try to read things they must not see.
//
//   npm run test:emulator   against the local emulators (default)
//   npm run test:cloud      against the deployed project (AVALON_TARGET=cloud)
import { strict as assert } from 'node:assert';
import { after, before, describe, test } from 'node:test';
import { FirebaseApp, deleteApp, initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, signInAnonymously } from 'firebase/auth';
import {
  Firestore,
  connectFirestoreEmulator,
  doc,
  getDoc,
  getFirestore,
  collection, deleteDoc, getDocs, query, setDoc, Timestamp, updateDoc, where,
} from 'firebase/firestore';
import {
  Functions,
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} from 'firebase/functions';

const PROJECT = 'avalon-shadow-council';

interface Phone {
  app: FirebaseApp;
  uid: string;
  db: Firestore;
  fns: Functions;
  call: (name: string, data: Record<string, unknown>) => Promise<any>;
}

const CLOUD = process.env.AVALON_TARGET === 'cloud';
// the web app's public config (lib/firebase_options.dart)
const CLOUD_CONFIG = {
  apiKey: 'AIzaSyBX59ZuswRIrIvmhqdvd__44xl5MPyLR8A',
  appId: '1:1041864366616:web:01906d9135bce53515416d',
  projectId: PROJECT,
  authDomain: 'avalon-shadow-council.firebaseapp.com',
};

let counter = 0;
async function phone(): Promise<Phone> {
  const app = initializeApp(
    CLOUD ? CLOUD_CONFIG : { apiKey: 'fake', projectId: PROJECT, appId: 'test' },
    `phone${counter++}`,
  );
  const auth = getAuth(app);
  const db = getFirestore(app);
  const fns = getFunctions(app, 'asia-east1');
  if (!CLOUD) {
    connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
    connectFirestoreEmulator(db, '127.0.0.1', 8080);
    connectFunctionsEmulator(fns, '127.0.0.1', 5001);
  }
  const cred = await signInAnonymously(auth);
  return {
    app,
    uid: cred.user.uid,
    db,
    fns,
    call: async (name, data) => (await httpsCallable(fns, name)({ protocolVersion: 2, ...data })).data,
  };
}

async function denied(work: Promise<unknown>) {
  await assert.rejects(work, (e: any) => /permission/i.test(String(e?.code ?? e)));
}

async function refused(work: Promise<unknown>, pattern?: RegExp) {
  await assert.rejects(work, (e: any) => {
    if (pattern) assert.match(String(e?.message), pattern);
    return true;
  });
}

const room = async (p: Phone, code: string) =>
  (await getDoc(doc(p.db, 'rooms', code))).data() as any;

describe('online game end to end', () => {
  const phones: Phone[] = [];
  let outsider: Phone;
  let code = '';

  before(async () => {
    for (let i = 0; i < 5; i++) phones.push(await phone());
    outsider = await phone();
  });

  after(async () => {
    if (code) {
      // everyone leaves, which deletes the room
      for (const p of [...phones, outsider]) {
        await p.call('leaveRoom', { code }).catch(() => {});
      }
    }
    await Promise.all([...phones, outsider].map((p) => deleteApp(p.app)));
  });

  test('host creates a room and players join with the code', async () => {
    ({ code } = await phones[0].call('createRoom', { name: '亞瑟' }));
    assert.match(code, /^\d{6}$/);
    const names = ['蘭斯洛特', '高文', '崔斯坦', '貝德維爾'];
    for (let i = 1; i < 5; i++) {
      const { seat } = await phones[i].call('joinRoom', { code, name: names[i - 1] });
      assert.equal(seat, i);
    }
    // joining again just returns the same seat
    assert.equal((await phones[2].call('joinRoom', { code, name: 'x' })).seat, 2);
    const r = await room(phones[1], code);
    assert.equal(r.players.length, 5);
    assert.equal(r.status, 'lobby');
    assert.equal(r.discussion.enabled, true);
  });

  test('only host configures discussion in lobby; server clock is authenticated', async () => {
    await refused(outsider.call('joinRoom', { code, name: '舊版玩家', protocolVersion: 1 }), /更新/);
    const legacy = await outsider.call('createRoom', { name: '舊版房主', protocolVersion: 1 });
    try {
      assert.equal((await room(outsider, legacy.code)).discussion.enabled, false);
      await phones[0].call('joinRoom', { code: legacy.code, name: '新版玩家' });
      await refused(outsider.call('setDiscussion', { code: legacy.code, discussion: {
        enabled: true, speechSeconds: 45, freeSeconds: 0, selectionFree: true,
      } }), /更新/);
    } finally {
      await phones[0].call('leaveRoom', { code: legacy.code });
      await outsider.call('leaveRoom', { code: legacy.code });
    }
    const discussion = { enabled: true, speechSeconds: 30, freeSeconds: 0, selectionFree: false };
    await denied(phones[1].call('setDiscussion', { code, discussion }));
    await refused(phones[0].call('setDiscussion', { code,
      discussion: { ...discussion, speechSeconds: 5 } }));
    await phones[0].call('setDiscussion', { code, discussion });
    assert.deepEqual((await room(phones[1], code)).discussion, discussion);
    const clock = await phones[0].call('serverTime', {});
    assert.ok(Math.abs(clock.serverNow - Date.now()) < 10000);
  });

  test('only players of the room can read it', async () => {
    await denied(getDoc(doc(outsider.db, 'rooms', code)));
    await refused(phones[1].call('setRoles', { code, roles: ['percival'] }), /房主/);
    await phones[0].call('setRoles', { code, roles: ['percival', 'morgana'] });
    assert.deepEqual((await room(phones[3], code)).optionalRoles, ['percival', 'morgana']);
  });

  test('voice metadata is restricted to room members and the correct sessions', async () => {
    const a = phones[0], b = phones[1];
    const data = await room(a, code);
    assert.equal(typeof data.voiceRoomId, 'string');
    const people = (p: Phone, uid: string) => doc(p.db, 'rooms', code, 'voice', uid);
    const presence = (uid: string, session: string) => ({ uid, session,
      roomId: data.voiceRoomId, expireAt: Timestamp.fromMillis(Date.now() + 90000) });
    const as = 'aaaaaaaaaaaaaaaaaaaaaaaa', bs = 'bbbbbbbbbbbbbbbbbbbbbbbb';
    await setDoc(people(a, a.uid), presence(a.uid, as));
    await setDoc(people(b, b.uid), presence(b.uid, bs));
    await denied(setDoc(people(b, a.uid), presence(a.uid, as)));
    await denied(deleteDoc(people(b, a.uid)));
    await denied(getDocs(collection(outsider.db, 'rooms', code, 'voice')));
    await denied(setDoc(people(outsider, outsider.uid), presence(outsider.uid, as)));
    await denied(setDoc(people(a, a.uid), { ...presence(a.uid, as), roomId: 'old-room' }));
    await denied(setDoc(people(a, a.uid), { ...presence(a.uid, as),
      expireAt: Timestamp.fromMillis(Date.now() + 10000000) }));

    const signal = { from: a.uid, fromSession: as, to: b.uid, toSession: bs,
      roomId: data.voiceRoomId, attempt: 1, kind: 'offer',
      data: { type: 'offer', sdp: 'test-sdp' }, order: 0,
      expireAt: Timestamp.fromMillis(Date.now() + 300000) };
    const message = (p: Phone, id: string) => doc(p.db, 'rooms', code, 'voiceSignals', id);
    await setDoc(message(a, 'valid'), signal);
    assert.equal((await getDoc(message(b, 'valid'))).data()!.from, a.uid);
    assert.equal((await getDocs(query(collection(b.db, 'rooms', code, 'voiceSignals'),
      where('to', '==', b.uid)))).size, 1);
    await denied(getDoc(message(a, 'valid')));
    await denied(getDocs(collection(b.db, 'rooms', code, 'voiceSignals')));
    await denied(getDoc(message(outsider, 'valid')));
    await denied(updateDoc(message(b, 'valid'), { kind: 'answer' }));
    for (const patch of [
      { from: b.uid }, { fromSession: 'old-session' }, { toSession: 'old-session' },
      { to: outsider.uid }, { roomId: 'old-room' }, { kind: 'chat' },
      { data: { type: 'offer', sdp: 'x'.repeat(32001) } }, { unexpected: true },
    ]) await denied(setDoc(message(a, 'invalid'), { ...signal, ...patch }));
    await deleteDoc(message(b, 'valid'));
    // Updating a voice session invalidates messages from its predecessor.
    await setDoc(people(a, a.uid), presence(a.uid, 'cccccccccccccccccccccccc'));
    await denied(setDoc(message(a, 'stale'), signal));
    await deleteDoc(people(a, a.uid));
    await deleteDoc(people(b, b.uid));
    // The STUN-only production deployment intentionally omits this optional
    // TURN configuration endpoint. Exercise it in the local emulator.
    if (!CLOUD) {
      assert.deepEqual((await a.call('voiceIce', { code })).iceServers,
        [{ urls: 'stun:stun.l.google.com:19302' }]);
      await denied(outsider.call('voiceIce', { code }));
    }
  });

  test('each phone can read its own role only, never the secret', async () => {
    await refused(phones[1].call('startGame', { code }), /房主/);
    await phones[0].call('startGame', { code });
    const roles: string[] = [];
    for (const [seat, p] of phones.entries()) {
      const mine = (await getDoc(doc(p.db, 'rooms', code, 'private', p.uid))).data()!;
      assert.equal(mine.seat, seat);
      roles.push(mine.role);
      const other = phones[(seat + 1) % 5];
      await denied(getDoc(doc(p.db, 'rooms', code, 'private', other.uid)));
      await denied(getDoc(doc(p.db, 'rooms', code, 'secret', 'state')));
    }
    assert.deepEqual([...roles].sort(), ['assassin', 'loyal', 'merlin', 'morgana', 'percival']);
    const r = await room(phones[0], code);
    assert.equal(r.game.phase, 'identity');
    assert.equal(r.game.revealedRoles, null);
    assert.equal(JSON.stringify(r).includes('merlin'), false);
    (globalThis as any).roles = roles;
  });

  test('a whole game: votes stay hidden until everyone has voted', async () => {
    const roles: string[] = (globalThis as any).roles;
    const move = (seat: number, kind: string, data: Record<string, unknown> = {}) =>
      phones[seat].call('move', { code, move: kind, ...data });

    for (let i = 0; i < 5; i++) await move(i, 'confirmIdentity');
    let r = await room(phones[0], code);
    assert.equal(r.game.phase, 'team');

    // a non-leader cannot propose
    const leader: number = r.game.leader;
    await refused(move((leader + 1) % 5, 'proposeTeam', { team: [0, 1] }), /隊長/);

    await refused(phones[0].call('setDiscussion', { code, discussion: {
      enabled: false, speechSeconds: 45, freeSeconds: 0, selectionFree: true,
    } }), /大廳/);

    const speeches = async () => {
      for (let i = 1; i <= 5; i++) {
        const before = await room(phones[0], code);
        assert.equal(before.game.phase, 'discussion');
        const speaker = (before.game.leader + i) % 5;
        const data = { expectedVersion: before.game.speechVersion, generation: before.gen };
        await denied(move((speaker + 1) % 5, 'endSpeech', data));
        await move(speaker, 'endSpeech', { ...data, generation: before.gen - 1 });
        assert.equal((await room(phones[0], code)).game.speechVersion, data.expectedVersion);
        // Simultaneous clicks/expiry callbacks can advance only one seat.
        await Promise.all([move(speaker, 'endSpeech', data), move(speaker, 'endSpeech', data)]);
        assert.equal((await room(phones[0], code)).game.speechVersion, data.expectedVersion + 1);
      }
      assert.equal((await room(phones[0], code)).game.phase, 'vote');
    };

    // Keep an initial rejected proposal alongside later successful quests.
    await move(leader, 'proposeTeam', { team: [3, 4] });
    await speeches();
    for (let i = 0; i < 4; i++) await move(i, 'vote', { approve: false });
    assert.equal((await room(phones[0], code)).game.proposals.length, 0);
    await move(4, 'vote', { approve: true });
    r = await room(phones[0], code);
    assert.deepEqual(r.game.proposals[0], { quest: 1, attempt: 1,
      leader, team: [3, 4], votes: [false, false, false, false, true], approved: false });
    await move(leader, 'continueVote');

    // three quests that all succeed
    for (let q = 0; q < 3; q++) {
      r = await room(phones[0], code);
      const size = [2, 3, 2][q];
      const team = Array.from({ length: size }, (_, i) => i);
      await move(r.game.leader, 'proposeTeam', { team });
      await speeches();
      for (let i = 0; i < 4; i++) await move(i, 'vote', { approve: i !== 3 });
      r = await room(phones[0], code);
      assert.equal(r.game.votes, null, 'votes are not published yet');
      assert.equal(r.game.proposals.length, 1 + q, 'partial ballots are absent from proposal history');
      assert.deepEqual(r.game.voted, [0, 1, 2, 3]);
      await move(4, 'vote', { approve: true });
      r = await room(phones[0], code);
      assert.deepEqual(r.game.votes, [true, true, true, false, true]);
      assert.equal(r.game.proposals.at(-1).attempt, q === 0 ? 2 : 1);
      assert.equal(r.game.proposals.at(-1).quest, q + 1);
      await move(r.game.leader, 'continueVote');
      for (const seat of team) {
        if (roles[seat] === 'assassin' || roles[seat] === 'morgana') {
          // evil may play success too; good may not fail
        } else {
          await refused(move(seat, 'playQuest', { success: false }), /正義/);
        }
        await move(seat, 'playQuest', { success: true });
      }
      r = await room(phones[0], code);
      assert.equal(r.game.phase, 'questResult');
      assert.deepEqual(r.game.history.at(-1).order, team.map(() => true));
      await move(r.game.leader, 'continueQuest');
    }

    r = await room(phones[0], code);
    assert.equal(r.game.phase, 'assassination');
    const assassin = roles.indexOf('assassin');
    const notAssassin = (assassin + 1) % 5;
    await refused(move(notAssassin, 'assassinate', { target: assassin }), /刺客/);
    const merlin = roles.indexOf('merlin');
    await move(assassin, 'assassinate', { target: merlin });
    r = await room(phones[0], code);
    assert.equal(r.game.phase, 'finished');
    assert.equal(r.game.winner, '邪惡');
    assert.deepEqual(r.game.revealedRoles, roles);
  });

  test('the host can deal again and players cannot join a running game', async () => {
    await phones[0].call('startGame', { code });
    const r = await room(phones[0], code);
    assert.equal(r.gen, 2);
    assert.equal(r.game.phase, 'identity');
    await refused(outsider.call('joinRoom', { code, name: '路人' }), /已經開始/);
  });

  test('a player leaving mid-game ends it for everyone', async () => {
    const before = await room(phones[0], code);
    await setDoc(doc(phones[4].db, 'rooms', code, 'voice', phones[4].uid), {
      uid: phones[4].uid, session: 'leaving-session-12345678', roomId: before.voiceRoomId,
      expireAt: Timestamp.fromMillis(Date.now() + 90000),
    });
    const leaver = before.players[4].name;
    const result = await phones[4].call('leaveRoom', { code });
    assert.deepEqual(result, { left: true, ended: true });
    const r = await room(phones[0], code);
    assert.equal(r.status, 'lobby');
    assert.equal(r.game, null);
    assert.equal(r.players.length, 4);
    assert.equal(r.notice, `${leaver} 離開了房間，對局已中止`);
    assert.equal(r.noticeStep, r.step);
    assert.equal((await getDoc(doc(phones[0].db, 'rooms', code, 'voice', phones[4].uid))).exists(), false);
    // the seat is gone: the room can no longer be read from that phone
    await denied(getDoc(doc(phones[4].db, 'rooms', code)));
    // and the others can carry on: someone new can join the lobby
    const { seat } = await outsider.call('joinRoom', { code, name: '路人' });
    assert.equal(seat, 4);
  });

  test('the host leaving hands the room to the next player', async () => {
    await phones[0].call('leaveRoom', { code });
    const r = await room(phones[1], code);
    assert.equal(r.hostUid, phones[1].uid);
    assert.match(r.notice, /離開了房間$/);
  });
});

describe('expansions online', () => {
  const phones: Phone[] = [];
  let legacy: Phone;
  let code = '';
  const v3 = (p: Phone, name: string, data: Record<string, unknown> = {}) =>
    p.call(name, { protocolVersion: 3, code, ...data });
  const mine = async (p: Phone) =>
    (await getDoc(doc(p.db, 'rooms', code, 'private', p.uid))).data() as any;

  before(async () => {
    for (let i = 0; i < 5; i++) phones.push(await phone());
    legacy = await phone();
  });

  after(async () => {
    if (code) {
      for (const p of [...phones, legacy]) await p.call('leaveRoom', { code }).catch(() => {});
    }
    await Promise.all([...phones, legacy].map((p) => deleteApp(p.app)));
  });

  test('only the host turns expansions on, and old apps cannot join', async () => {
    ({ code } = await phones[0].call('createRoom', { name: '亞瑟', protocolVersion: 3 }));
    for (let i = 1; i < 5; i++) await v3(phones[i], 'joinRoom', { name: `騎士${i}` });
    // five phones: Lancelot needs seven players, so it stays off here
    const all = { lady: true, lancelot: 0, excalibur: true };
    await denied(v3(phones[1], 'setExpansions', { expansions: all }));
    await refused(v3(phones[0], 'setExpansions', { expansions: { ...all, lancelot: 5 } }));
    await v3(phones[0], 'setExpansions', { expansions: all });
    // vote straight after the proposal (no turn-based discussion)
    await v3(phones[0], 'setDiscussion', {
      discussion: { enabled: false, speechSeconds: 45, freeSeconds: 0, selectionFree: true },
    });
    assert.deepEqual((await room(phones[0], code)).expansions, all);
    await refused(legacy.call('joinRoom', { code, name: '舊版' }), /更新/);
  });

  test('Excalibur: only the holder learns the flipped card', async () => {
    await v3(phones[0], 'startGame');
    let g = (await room(phones[0], code)).game;
    assert.ok(g.loyalty.every((c: boolean | null) => c === null));
    assert.equal(g.ladyHolder, (g.leader + 4) % 5);
    assert.equal('reveals' in g, false);
    assert.equal('loyaltyDeck' in g, false);
    for (const p of phones) await v3(p, 'move', { move: 'confirmIdentity' });
    const leader = g.leader;
    const holder = (leader + 1) % 5;
    const team = [leader, holder].sort((a, b) => a - b);
    await refused(v3(phones[leader], 'move', { move: 'proposeTeam', team }), /王者之劍/);
    await refused(v3(phones[leader], 'move', { move: 'proposeTeam', team, excalibur: leader }), /王者之劍/);
    await v3(phones[leader], 'move', { move: 'proposeTeam', team, excalibur: holder });
    for (const p of phones) await v3(p, 'move', { move: 'vote', approve: true });
    await v3(phones[leader], 'move', { move: 'continueVote' });
    g = (await room(phones[0], code)).game;
    for (const seat of team) {
      const role: string = (await mine(phones[seat])).role;
      const lancelot = role === 'lancelotGood' || role === 'lancelotEvil';
      const evilNow = ['assassin', 'minion', 'lancelotEvil'].includes(role) !== (lancelot && g.lancelotSwitched);
      await v3(phones[seat], 'move', { move: 'playQuest', success: !(lancelot && evilNow) });
    }
    assert.equal((await room(phones[0], code)).game.phase, 'excalibur');
    await denied(v3(phones[leader], 'move', { move: 'useExcalibur', target: holder }));
    await v3(phones[holder], 'move', { move: 'useExcalibur', target: leader });
    const seen = (await mine(phones[holder])).reveals;
    assert.equal(seen.length, 1);
    assert.equal(seen[0].kind, 'excalibur');
    assert.equal(seen[0].target, leader);
    assert.equal(typeof seen[0].card, 'boolean');
    assert.deepEqual((await mine(phones[leader])).reveals, []);
    await denied(v3(phones[leader], 'move', { move: 'continueExcalibur' }));
    await v3(phones[holder], 'move', { move: 'continueExcalibur' });
    g = (await room(phones[0], code)).game;
    assert.equal(g.phase, 'questResult');
    assert.deepEqual(g.history[0].excalibur, { holder, target: leader });
  });
});
