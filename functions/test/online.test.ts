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
    call: async (name, data) => (await httpsCallable(fns, name)(data)).data,
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
  });

  test('only players of the room can read it', async () => {
    await denied(getDoc(doc(outsider.db, 'rooms', code)));
    await refused(phones[1].call('setRoles', { code, roles: ['percival'] }), /房主/);
    await phones[0].call('setRoles', { code, roles: ['percival', 'morgana'] });
    assert.deepEqual((await room(phones[3], code)).optionalRoles, ['percival', 'morgana']);
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

    // three quests that all succeed
    for (let q = 0; q < 3; q++) {
      r = await room(phones[0], code);
      const size = [2, 3, 2][q];
      const team = Array.from({ length: size }, (_, i) => i);
      await move(r.game.leader, 'proposeTeam', { team });
      for (let i = 0; i < 4; i++) await move(i, 'vote', { approve: i !== 3 });
      r = await room(phones[0], code);
      assert.equal(r.game.votes, null, 'votes are not published yet');
      assert.deepEqual(r.game.voted, [0, 1, 2, 3]);
      await move(4, 'vote', { approve: true });
      r = await room(phones[0], code);
      assert.deepEqual(r.game.votes, [true, true, true, false, true]);
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
    const leaver = before.players[4].name;
    const result = await phones[4].call('leaveRoom', { code });
    assert.deepEqual(result, { left: true, ended: true });
    const r = await room(phones[0], code);
    assert.equal(r.status, 'lobby');
    assert.equal(r.game, null);
    assert.equal(r.players.length, 4);
    assert.equal(r.notice, `${leaver} 離開了房間，對局已中止`);
    assert.equal(r.noticeStep, r.step);
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
