import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { Timestamp } from 'firebase-admin/firestore';
import { roomHasExpired } from '../src/room_lifecycle';

test('room expires at its deadline, without waiting for TTL deletion', () => {
  assert.equal(roomHasExpired(Timestamp.fromMillis(1001), 1000), false);
  assert.equal(roomHasExpired(Timestamp.fromMillis(1000), 1000), true);
  assert.equal(roomHasExpired(Timestamp.fromMillis(999), 1000), true);
});

test('missing or malformed room deadlines fail closed', () => {
  for (const deadline of [undefined, null, 9999999999999, '2099-01-01', {},
    { toMillis: () => 9999999999999 }]) {
    assert.equal(roomHasExpired(deadline, 1000), true);
  }
});
