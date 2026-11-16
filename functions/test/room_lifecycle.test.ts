import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { Timestamp } from 'firebase-admin/firestore';
import { GAME_DOCS_LEAD_MS, gameDocsRenewalDue, roomHasExpired }
  from '../src/room_lifecycle';

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

test('private game documents never expire while the room is still there', () => {
  const HOUR = 60 * 60 * 1000;
  const DAY = 24 * HOUR;
  // the reported timeline: start, a move at hour 11, the next at hour 30
  let room = DAY;
  let priv = DAY + GAME_DOCS_LEAD_MS;
  for (const at of [11 * HOUR, 30 * HOUR, 30.5 * HOUR, 55 * HOUR]) {
    assert.ok(priv > at, `private documents alive at ${at / HOUR}h`);
    room = at + DAY;
    if (gameDocsRenewalDue(Timestamp.fromMillis(priv), room)) {
      priv = room + GAME_DOCS_LEAD_MS;
    }
    assert.ok(priv > room, `private documents outlive the room after ${at / HOUR}h`);
  }
  // half an hour later the room has barely moved: no rewrite yet
  assert.equal(gameDocsRenewalDue(Timestamp.fromMillis(priv), room + HOUR / 2), false);
  // a deadline missing (a game started before the field) is renewed
  assert.equal(gameDocsRenewalDue(undefined, room), true);
});
