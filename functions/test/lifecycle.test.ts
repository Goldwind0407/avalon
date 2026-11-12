// Admin fixtures are permitted ONLY against the local Firestore emulator.
import { strict as assert } from 'node:assert';
import { after, afterEach, before, describe, test } from 'node:test';
import { initializeApp as initializeAdminApp, deleteApp as deleteAdminApp } from 'firebase-admin/app';
import { FieldValue, getFirestore as getAdminFirestore, Timestamp } from 'firebase-admin/firestore';
import { deleteApp, initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, signInAnonymously } from 'firebase/auth';
import { connectFirestoreEmulator, doc, getDocFromServer, getFirestore } from 'firebase/firestore';
import { connectFunctionsEmulator, getFunctions, httpsCallable } from 'firebase/functions';

const PROJECT = 'avalon-shadow-council';
async function phone(index: number) {
  const app = initializeApp({ apiKey: 'fake', projectId: PROJECT, appId: 'test' }, `lifecycle-${index}`);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  const fns = getFunctions(app, 'asia-east1');
  connectFunctionsEmulator(fns, '127.0.0.1', 5001);
  const uid = (await signInAnonymously(auth)).user.uid;
  return { app, db, uid, call: async (name: string, data: Record<string, unknown>) =>
    (await httpsCallable(fns, name)({ protocolVersion: 3, ...data })).data as any };
}

describe('room lifetime and private document revocation', {
  skip: !process.env.FIRESTORE_EMULATOR_HOST || process.env.AVALON_TARGET === 'cloud',
}, () => {
  let adminApp: ReturnType<typeof initializeAdminApp>;
  let admin: ReturnType<typeof getAdminFirestore>;
  const phones: Awaited<ReturnType<typeof phone>>[] = [];
  const codes = new Set<string>();
  before(async () => {
    adminApp = initializeAdminApp({ projectId: PROJECT }, 'lifecycle-fixtures');
    admin = getAdminFirestore(adminApp);
    for (let i = 0; i < 6; i++) phones.push(await phone(i));
  });
  afterEach(async () => {
    for (const code of codes) await admin.recursiveDelete(admin.doc(`rooms/${code}`));
    codes.clear();
  });
  after(async () => {
    await Promise.all(phones.map((p) => deleteApp(p.app)));
    if (adminApp) await deleteAdminApp(adminApp);
  });
  const read = (seat: number, path: string) => getDocFromServer(doc(phones[seat].db, path));
  const denied = (work: Promise<unknown>) => assert.rejects(work,
    (e: any) => String(e.code).includes('permission-denied'));
  const expired = (work: Promise<unknown>) => assert.rejects(work,
    (e: any) => e.code === 'functions/failed-precondition' && /到期/.test(e.message));

  async function dealtRoom() {
    const { code } = await phones[0].call('createRoom', { name: '房主' });
    codes.add(code);
    for (let i = 1; i < 5; i++) await phones[i].call('joinRoom', { code, name: `玩家${i}` });
    await phones[0].call('startGame', { code });
    return { code: code as string, ref: admin.doc(`rooms/${code}`) };
  }

  test('leaving deletes private data and rules reject even a surviving legacy document', async () => {
    const { code, ref } = await dealtRoom();
    const ownPath = `rooms/${code}/private/${phones[1].uid}`;
    const own = admin.doc(ownPath);
    const previous = (await own.get()).data()!;
    assert.equal((await read(1, ownPath)).exists(), true);
    await denied(read(5, ownPath));
    await denied(read(0, ownPath));
    await phones[1].call('leaveRoom', { code });
    assert.equal((await own.get()).exists, false, 'private deletion shares the leave transaction');
    await denied(read(1, ownPath));
    await denied(read(1, `rooms/${code}`));
    assert.equal((await read(0, `rooms/${code}/private/${phones[0].uid}`)).exists(), true);

    // Prove revocation comes from rules too, independently of deletion/TTL.
    await own.set(previous);
    await denied(read(1, ownPath));
    await phones[1].call('leaveRoom', { code });
    assert.equal((await own.get()).exists, false, 'repeated leave cleans legacy orphans');
    await phones[1].call('joinRoom', { code, name: '回來的玩家' });
    assert.equal((await read(1, ownPath)).exists(), false, 'lobby may subscribe to a missing own card');
    assert.equal((await ref.get()).data()!.status, 'lobby');
  });

  test('expired-but-existing rooms reject reads and every normal room action without renewal', async () => {
    const { code, ref } = await dealtRoom();
    const deadline = Timestamp.fromMillis(Date.now() - 60000);
    await ref.update({ expireAt: deadline });
    const before = (await ref.get()).data()!;
    await denied(read(0, `rooms/${code}`));
    await denied(read(0, `rooms/${code}/private/${phones[0].uid}`));
    const calls = [
      phones[0].call('joinRoom', { code, name: '房主' }),
      phones[5].call('joinRoom', { code, name: '新玩家' }),
      phones[0].call('setRoles', { code, roles: [] }),
      phones[0].call('startGame', { code }),
      phones[0].call('backToLobby', { code }),
      phones[0].call('move', { code, move: 'confirmIdentity' }),
      phones[0].call('voiceIce', { code }),
      phones[0].call('setDiscussion', { code, discussion: {
        enabled: false, speechSeconds: 45, freeSeconds: 0, selectionFree: true,
      } }),
      phones[0].call('setExpansions', { code, expansions: { lady: false, lancelot: 0, excalibur: false } }),
    ];
    await Promise.all(calls.map(expired));
    const after = (await ref.get()).data()!;
    assert.equal(after.expireAt.toMillis(), deadline.toMillis());
    assert.equal(after.step, before.step);
    assert.deepEqual(after.playerUids, before.playerUids);
    assert.equal(after.game.phase, 'identity');
  });

  test('expired rooms still allow departure and final cleanup without extending their deadline', async () => {
    const { code, ref } = await dealtRoom();
    const deadline = Timestamp.fromMillis(Date.now() - 60000);
    await ref.update({ expireAt: deadline });
    const voice = ref.collection('voice').doc(phones[0].uid);
    await voice.set({ uid: phones[0].uid, expireAt: Timestamp.fromMillis(Date.now() + 60000) });
    assert.deepEqual(await phones[0].call('leaveRoom', { code }), { left: true, ended: true });
    const after = (await ref.get()).data()!;
    assert.equal(after.expireAt.toMillis(), deadline.toMillis());
    assert.equal(after.status, 'lobby');
    assert.equal(after.hostUid, phones[1].uid);
    assert.equal(after.playerUids.includes(phones[0].uid), false);
    assert.equal((await ref.collection('private').doc(phones[0].uid).get()).exists, false);
    assert.equal((await voice.get()).exists, false);
    assert.equal((await ref.collection('secret').doc('state').get()).exists, false);
    for (let i = 1; i < 5; i++) await phones[i].call('leaveRoom', { code });
    assert.equal((await ref.get()).exists, false);
    for (const p of phones.slice(0, 5)) {
      assert.equal((await ref.collection('private').doc(p.uid).get()).exists, false);
    }
    assert.deepEqual(await phones[0].call('leaveRoom', { code }), { left: true, ended: false });
  });

  test('missing deadlines are denied and cleanup never creates a fresh lifetime', async () => {
    const { code, ref } = await dealtRoom();
    await ref.update({ expireAt: FieldValue.delete() });
    await denied(read(0, `rooms/${code}`));
    await denied(read(0, `rooms/${code}/private/${phones[0].uid}`));
    await expired(phones[0].call('joinRoom', { code, name: '房主' }));
    await phones[0].call('leaveRoom', { code });
    assert.equal((await ref.get()).data()!.expireAt.toMillis(), 0);
  });

  test('deleting the parent revokes orphan access, and leave removes only the caller\'s orphans', async () => {
    const { code, ref } = await dealtRoom();
    const own = ref.collection('private').doc(phones[0].uid);
    const other = ref.collection('private').doc(phones[1].uid);
    await ref.delete();
    assert.equal((await own.get()).exists, true, 'parent deletion is not recursive');
    await denied(read(0, own.path));
    await phones[5].call('leaveRoom', { code });
    assert.equal((await own.get()).exists, true, 'outsider cannot delete another UID');
    await phones[0].call('leaveRoom', { code });
    assert.equal((await own.get()).exists, false);
    assert.equal((await other.get()).exists, true);
  });
});
