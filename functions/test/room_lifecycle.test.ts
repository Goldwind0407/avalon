import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { Timestamp } from 'firebase-admin/firestore';
import { GAME_DOCS_RENEW_MARGIN_MS, gameDocsRenewalDue, roomHasExpired }
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

test('private game documents are renewed before they could expire', () => {
  const now = 10 * GAME_DOCS_RENEW_MARGIN_MS;
  // far from expiring: left alone, so a busy room does not rewrite them
  assert.equal(gameDocsRenewalDue(Timestamp.fromMillis(now + 2 * GAME_DOCS_RENEW_MARGIN_MS), now),
    false);
  // within the margin, already past, or a game started before the field
  assert.equal(gameDocsRenewalDue(Timestamp.fromMillis(now + GAME_DOCS_RENEW_MARGIN_MS - 1), now),
    true);
  assert.equal(gameDocsRenewalDue(Timestamp.fromMillis(now - 1), now), true);
  assert.equal(gameDocsRenewalDue(undefined, now), true);
});
