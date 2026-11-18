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
  getDocFromServer,
  getFirestore,
  collection, deleteDoc, getDocs, query, serverTimestamp, setDoc, Timestamp, updateDoc, where,
} from 'firebase/firestore';
import {
  Functions,
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} from 'firebase/functions';

const CLOUD = process.env.AVALON_TARGET === 'cloud';
// emulators:exec exports its project ID; keep local/CI data isolated from cloud.
const PROJECT = CLOUD ? 'avalon-shadow-council'
  : process.env.GCLOUD_PROJECT ?? 'demo-avalon-ci';

interface Phone {
  app: FirebaseApp;
  uid: string;
  db: Firestore;
  fns: Functions;
  call: (name: string, data: Record<string, unknown>) => Promise<any>;
}

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
      await refused(move(0, 'vote', { approve: true, generation: r.gen - 1 }), /這局已更新/);
      await refused(move(0, 'vote', { approve: true, historyLength: q + 1 }), /這輪已更新/);
      await refused(move(0, 'vote', { approve: true, rejections: r.game.rejections + 1 }), /這輪已更新/);
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
    await refused(phones[0].call('move', { code, move: 'confirmIdentity', generation: r.gen - 1 }), /這局已更新/);
    assert.deepEqual((await room(phones[0], code)).game.confirmed, []);
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
    await denied(getDocFromServer(doc(phones[4].db, 'rooms', code, 'private', phones[4].uid)));
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

  test('Lady: a good holder may only tell the truth; the table hears it', async () => {
    // finish the first quest (it stopped at its result) and play the second
    let g = (await room(phones[0], code)).game;
    const evilRoles = ['assassin', 'minion', 'morgana', 'mordred', 'oberon'];
    const roles: string[] = [];
    for (const p of phones) roles.push((await mine(p)).role);
    await v3(phones[g.leader], 'move', { move: 'continueQuest' });
    g = (await room(phones[0], code)).game;
    const size = 3;
    const team = [g.leader, ...[0, 1, 2, 3, 4].filter((x) => x !== g.leader)].slice(0, size).sort((a, b) => a - b);
    const holder = team.find((x) => x !== g.leader)!;
    await v3(phones[g.leader], 'move', { move: 'proposeTeam', team, excalibur: holder });
    for (const p of phones) await v3(p, 'move', { move: 'vote', approve: true });
    await v3(phones[g.leader], 'move', { move: 'continueVote' });
    for (const seat of team) await v3(phones[seat], 'move', { move: 'playQuest', success: true });
    await v3(phones[holder], 'move', { move: 'useExcalibur', target: null });
    g = (await room(phones[0], code)).game;
    await v3(phones[g.leader], 'move', { move: 'continueQuest' });
    g = (await room(phones[0], code)).game;
    assert.equal(g.phase, 'lady');
    const lady: number = g.ladyHolder;
    const target = [0, 1, 2, 3, 4].find((x) => !g.ladyPast.includes(x))!;
    // not yet: nothing has been checked
    await refused(v3(phones[lady], 'announceLady', { evil: true }), /不能公布/);
    await v3(phones[lady], 'move', { move: 'useLady', target });
    const truth: boolean = (await mine(phones[lady])).reveals.at(-1).evil;
    const other = (lady + 1) % 5 === target ? (lady + 2) % 5 : (lady + 1) % 5;
    await denied(v3(phones[other], 'announceLady', { evil: truth }));
    if (evilRoles.includes(roles[lady])) {
      await v3(phones[lady], 'announceLady', { evil: !truth });  // evil may lie
    } else {
      await refused(v3(phones[lady], 'announceLady', { evil: !truth }), /好人不能謊報/);
      await v3(phones[lady], 'announceLady', { evil: truth });
    }
    const r = await room(phones[0], code);
    const said = r.talk.filter((l: any) => l.lady);
    assert.equal(said.length, 1);
    assert.equal(said[0].by, lady);
    assert.equal(said[0].lady.target, target);
    // once a check
    await v3(phones[lady], 'announceLady', { evil: truth });
    assert.equal((await room(phones[0], code)).talk.filter((l: any) => l.lady).length, 1);
  });
});

describe('a player whose phone has gone quiet', () => {
  const phones: Phone[] = [];
  let outsider: Phone;
  let code = '';
  const presence = (p: Phone, of: Phone = p) => doc(p.db, 'rooms', code, 'presence', of.uid);
  const here = (p: Phone) => setDoc(presence(p), {
    at: serverTimestamp(), expireAt: Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000),
  });

  before(async () => {
    for (let i = 0; i < 5; i++) phones.push(await phone());
    outsider = await phone();
    ({ code } = await phones[0].call('createRoom', { name: '亞瑟', protocolVersion: 4 }));
    // seat 3 runs an older app, which never reports its presence
    for (let i = 1; i < 5; i++) {
      await phones[i].call('joinRoom', { code, name: `騎士${i}`, protocolVersion: i === 3 ? 3 : 4 });
    }
    await phones[0].call('setDiscussion', { code, discussion: {
      enabled: false, speechSeconds: 45, freeSeconds: 0, selectionFree: true,
    } });
  });

  after(async () => {
    for (const p of phones) await p.call('leaveRoom', { code }).catch(() => {});
    await Promise.all([...phones, outsider].map((p) => deleteApp(p.app)));
  });

  test('a phone reports only for itself, with the server clock, and nobody reads it', async () => {
    await here(phones[1]);
    await denied(setDoc(presence(phones[1], phones[2]), {
      at: serverTimestamp(), expireAt: Timestamp.fromMillis(Date.now() + 60000),
    }));
    // a made-up time is refused: being here cannot be dated ahead
    await denied(setDoc(presence(phones[1]), {
      at: Timestamp.fromMillis(Date.now() + 3600000),
      expireAt: Timestamp.fromMillis(Date.now() + 7200000),
    }));
    await denied(setDoc(presence(phones[1]), {
      at: serverTimestamp(), expireAt: Timestamp.fromMillis(Date.now() + 60000), extra: 1,
    }));
    await denied(setDoc(presence(outsider), {
      at: serverTimestamp(), expireAt: Timestamp.fromMillis(Date.now() + 60000),
    }));
    await denied(getDocFromServer(presence(phones[1])));
    await denied(getDocFromServer(presence(phones[2], phones[1])));
  });

  test('the server plays for whoever is gone, and only for them', async () => {
    await phones[0].call('startGame', { code });
    // seats 0-2 are here; seat 3 (older app) and seat 4 say nothing
    for (const p of phones.slice(0, 3)) await here(p);
    for (const p of phones.slice(0, 4)) await p.call('move', { code, move: 'confirmIdentity' });
    assert.equal((await room(phones[0], code)).game.phase, 'identity');
    await denied(outsider.call('nudge', { code }));
    await phones[1].call('nudge', { code });
    let r = await room(phones[0], code);
    assert.deepEqual(r.away, [4]);
    assert.match(r.notice, /5 號.*電腦代理/);
    // asked again until nothing more comes of it (the plain stand-in does
    // all it can at once; the computers' server takes a step at a time)
    for (let i = 0; i < 6; i++) {
      if ((await phones[1].call('nudge', { code })).moves === 0) break;
    }
    r = await room(phones[0], code);
    // the game went on as far as it could without a player who is here
    const leader: number = r.game.leader;
    if (leader === 4) {
      assert.equal(r.game.phase, 'vote');
      assert.deepEqual(r.game.voted, [4]);
    } else {
      assert.equal(r.game.phase, 'team');
      assert.equal((await phones[1].call('nudge', { code })).moves, 0);
      const team = [leader, (leader + 1) % 4].sort((a, b) => a - b);
      await phones[leader].call('move', { code, move: 'proposeTeam', team });
    }
    // everyone who is here votes; the stand-in's vote is already in or follows
    for (const p of phones.slice(0, 4)) await p.call('move', { code, move: 'vote', approve: true });
    await phones[0].call('nudge', { code });
    r = await room(phones[0], code);
    assert.equal(r.game.phase, 'voteResult');
    assert.equal(r.game.votes.length, 5);
    // the older app in seat 3 was never played for
    assert.ok(!r.away.includes(3));
  });

  test('the player takes the seat back on returning', async () => {
    await here(phones[4]);
    await phones[4].call('nudge', { code });
    const r = await room(phones[0], code);
    assert.deepEqual(r.away, []);
    assert.match(r.notice, /5 號.*回來了/);
    // nobody is away: asking again changes nothing
    const step = r.step;
    assert.equal((await phones[0].call('nudge', { code })).moves, 0);
    assert.equal((await room(phones[0], code)).step, step);
  });
});

// Needs the computer players' server running (bot_server/) and the
// functions told where it is: BOT_SERVER_URL and BOT_SERVER_SECRET.
describe('computers at the table', { skip: !process.env.BOT_SERVER_URL }, () => {
  const phones: Phone[] = [];
  let outsider: Phone;
  let code = '';
  const v5 = (p: Phone, name: string, data: Record<string, unknown>) =>
    p.call(name, { protocolVersion: 5, ...data });
  const mine = async (p: Phone) =>
    (await getDoc(doc(p.db, 'rooms', code, 'private', p.uid))).data() as any;

  before(async () => {
    for (let i = 0; i < 2; i++) phones.push(await phone());
    outsider = await phone();
    ({ code } = await v5(phones[0], 'createRoom', { name: '亞瑟' }));
    await v5(phones[1], 'joinRoom', { code, name: '高文' });
  });

  after(async () => {
    for (const p of phones) await p.call('leaveRoom', { code }).catch(() => {});
    await Promise.all([...phones, outsider].map((p) => deleteApp(p.app)));
  });

  test('only the host seats computers; old apps cannot join them', async () => {
    await refused(v5(phones[1], 'setBot', { code, persona: 'chen', name: '老陳', seated: true }), /房主/);
    await refused(v5(phones[0], 'setBot', { code, persona: 'Chen!', name: '老陳', seated: true }));
    for (const [persona, name] of [['chen', '老陳'], ['yu', '小魚'], ['zhe', '阿哲'], ['mia', '米亞']]) {
      await v5(phones[0], 'setBot', { code, persona, name, seated: true });
    }
    await v5(phones[0], 'setBot', { code, persona: 'mia', name: '米亞', seated: false });
    await refused(v5(phones[1], 'setBotLevel', { code, level: 'expert' }), /房主/);
    await refused(v5(phones[0], 'setBotLevel', { code, level: 'godlike' }));
    await v5(phones[0], 'setBotLevel', { code, level: 'expert' });
    const r = await room(phones[0], code);
    assert.deepEqual(r.players.map((p: any) => p.name), ['亞瑟', '高文', '老陳', '小魚', '阿哲']);
    assert.deepEqual(r.players.map((p: any) => p.bot === true), [false, false, true, true, true]);
    assert.equal(r.botLevel, 'expert');
    await refused(outsider.call('joinRoom', { code, name: '舊版', protocolVersion: 4 }), /更新/);
  });

  test('two people and three computers play a whole game', async () => {
    await v5(phones[0], 'setDiscussion', { code, discussion: {
      enabled: true, speechSeconds: 30, freeSeconds: 0, selectionFree: true,
    } });
    await v5(phones[0], 'startGame', { code });
    const cards = [await mine(phones[0]), await mine(phones[1])];
    const evil = (role: string) => ['assassin', 'minion', 'morgana', 'mordred', 'oberon'].includes(role);
    let said = 0;
    for (let turn = 0; turn < 600; turn++) {
      const r = await room(phones[0], code);
      const g = r.game;
      if (g.phase === 'finished') break;
      const move = (seat: number, data: Record<string, unknown>) =>
        v5(phones[seat], 'move', { code, generation: r.gen, ...data });
      let acted = false;
      for (const seat of [0, 1]) {
        switch (g.phase) {
          case 'identity':
            if (!g.confirmed.includes(seat)) { await move(seat, { move: 'confirmIdentity' }); acted = true; }
            break;
          case 'team':
            if (g.leader === seat) {
              const size = [2, 3, 2, 3, 3][g.history.length];
              const team = [seat, ...[0, 1, 2, 3, 4].filter((x) => x !== seat)].slice(0, size);
              await move(seat, { move: 'proposeTeam', team });
              acted = true;
            }
            break;
          case 'discussion':
            if ((g.leader + 1 + g.speechIndex) % 5 === seat) {
              await v5(phones[seat], 'say', { code, generation: r.gen, text: said % 2 ? '這隊我可以接受，支持。' : '我覺得3號有點可疑' });
              said++;
              await refused(v5(phones[1 - seat], 'say', { code, text: '插話' }), /輪到你/);
              // a line from an earlier turn that arrives late is not hung on this one
              await refused(v5(phones[seat], 'say', {
                code, generation: r.gen, expectedVersion: g.speechVersion - 1, text: '遲到的話',
              }), /結束/);
              await move(seat, { move: 'endSpeech', expectedVersion: g.speechVersion });
              acted = true;
            }
            break;
          case 'vote':
            if (!g.voted.includes(seat)) { await move(seat, { move: 'vote', approve: true }); acted = true; }
            break;
          case 'quest':
            if (g.team.includes(seat) && !g.played.includes(seat)) {
              await move(seat, { move: 'playQuest', success: !evil(cards[seat].role) });
              acted = true;
            }
            break;
          case 'voteResult':
            // the host may move on for a computer leader
            if (seat === 0) { await move(0, { move: 'continueVote' }); acted = true; }
            break;
          case 'questResult':
            if (seat === 0) { await move(0, { move: 'continueQuest' }); acted = true; }
            break;
          case 'assassination':
            if (cards[seat].role === 'assassin') {
              await move(seat, { move: 'assassinate', target: (seat + 2) % 5 });
              acted = true;
            }
            break;
        }
        if (acted) break;
      }
      // nothing for a person to do: the computers are asked
      if (!acted) await v5(phones[1], 'nudge', { code });
    }
    const r = await room(phones[0], code);
    assert.equal(r.game.phase, 'finished');
    assert.ok(['正義', '邪惡'].includes(r.game.winner));
    const talk: any[] = r.talk;
    const byBot = talk.filter((l) => l.bot === true);
    const byPeople = talk.filter((l) => l.bot !== true);
    assert.ok(byBot.length >= 3, `computers said ${byBot.length} lines`);
    assert.ok(byBot.every((l) => [2, 3, 4].includes(l.by) && l.text.length > 0));
    assert.ok(byPeople.length >= 1 && byPeople.every((l) => [0, 1].includes(l.by)));
    // a computer has no card anyone could read
    await denied(getDocFromServer(doc(phones[0].db, 'rooms', code, 'private', 'bot:chen')));
    // the game is kept for the computers to remember, out of everyone's reach
    await denied(getDocFromServer(doc(phones[0].db, 'rooms', code, 'pastGames', String(r.gen))));
    // the review: the whole game for those who played it, nobody else
    const review = (await getDocFromServer(doc(phones[1].db, 'rooms', code, 'reviews', String(r.gen)))).data() as any;
    assert.equal(review.state.phase, 'finished');
    assert.equal(review.state.roles.length, 5);
    assert.ok(Object.keys(review.state.cardLog).length > 0, 'every card');
    assert.ok(Object.keys(review.state.botReasons).length > 0, "the computers' reasons");
    assert.ok(Object.keys(review.state.botReasons).every((k: string) => ['2', '3', '4'].includes(k.split('/')[1])));
    await denied(getDocFromServer(doc(outsider.db, 'rooms', code, 'reviews', String(r.gen))));
    // the next deal: the computers are asked with that game in mind
    await v5(phones[0], 'startGame', { code });
    for (const p of phones) await v5(p, 'move', { code, move: 'confirmIdentity' });
    let moved = 0;
    for (let i = 0; i < 4; i++) moved += (await v5(phones[1], 'nudge', { code })).moves;
    assert.ok(moved > 0, 'the computers play the next game too');
  });

  test('when the people have gone, a room of computers is closed', async () => {
    await phones[1].call('leaveRoom', { code });
    let r = await room(phones[0], code);
    assert.equal(r.players.length, 4);
    assert.equal(r.status, 'lobby');
    await phones[0].call('leaveRoom', { code });
    await denied(getDocFromServer(doc(phones[0].db, 'rooms', code)));
  });
});

describe('limits on guessing and opening rooms', () => {
  test('a phone that keeps trying codes that lead nowhere is held off', async () => {
    const guesser = await phone();
    try {
      let refused = 0;
      for (let i = 0; i < 22; i++) {
        try {
          await guesser.call('joinRoom', { code: String(100000 + i), name: '猜猜看' });
        } catch (e: any) {
          if (/太多次/.test(String(e?.message))) refused++;
        }
      }
      assert.ok(refused >= 1, 'held off after twenty misses');
    } finally {
      await deleteApp(guesser.app);
    }
  });

  test('a phone that keeps opening rooms is held off', async () => {
    const host = await phone();
    const codes: string[] = [];
    try {
      let refused = 0;
      for (let i = 0; i < 11; i++) {
        try {
          codes.push((await host.call('createRoom', { name: '開房' })).code);
        } catch (e: any) {
          if (/太頻繁/.test(String(e?.message))) refused++;
        }
      }
      assert.equal(codes.length, 10);
      assert.equal(refused, 1);
    } finally {
      for (const code of codes) await host.call('leaveRoom', { code }).catch(() => {});
      await deleteApp(host.app);
    }
  });

  test('asking all at once does not get round the limits', async () => {
    const host = await phone();
    const codes: string[] = [];
    try {
      const tries = await Promise.allSettled(
        Array.from({ length: 16 }, () => host.call('createRoom', { name: '同時開房' })));
      for (const t of tries) if (t.status === 'fulfilled') codes.push(t.value.code);
      assert.ok(codes.length <= 10, `${codes.length} rooms opened at once`);
      await refused(host.call('createRoom', { name: '再開' }), /太頻繁/);
      const misses = await Promise.allSettled(Array.from({ length: 30 }, (_, i) =>
        host.call('joinRoom', { code: String(200000 + i), name: '同時猜' })));
      let notFound = misses.filter((m) => m.status === 'rejected' &&
        /找不到/.test(String((m as PromiseRejectedResult).reason?.message))).length;
      // some tries at once may fail on contention without being counted;
      // one at a time, the rest of the twenty run out and no more
      for (let i = 0; i < 25; i++) {
        try {
          await host.call('joinRoom', { code: String(300000 + i), name: '再猜' });
        } catch (e: any) {
          if (/太多次/.test(String(e?.message))) break;
          if (/找不到/.test(String(e?.message))) notFound++;
        }
      }
      assert.ok(notFound <= 20, `${notFound} misses let through`);
      await refused(host.call('joinRoom', { code: '399999', name: '再猜' }), /太多次/);
    } finally {
      for (const code of codes) await host.call('leaveRoom', { code }).catch(() => {});
      await deleteApp(host.app);
    }
  });
});
