import { strict as assert } from 'node:assert';
import { createHmac } from 'node:crypto';
import { test } from 'node:test';
import { voiceIceServers } from '../src/voice_ice';

test('STUN-only works without any paid account or TURN secret', () => {
  assert.deepEqual(voiceIceServers('u0', {}), [{ urls: 'stun:stun.l.google.com:19302' }]);
});

test('coturn credentials expire and never expose the shared secret', () => {
  const secret = 'test-secret-not-a-real-key';
  const servers = voiceIceServers('u0', { urls: 'turn:relay.test:3478, turns:relay.test:5349', secret }, 1000000);
  const turn = servers[1];
  assert.equal(turn.username, '15400:u0');
  assert.deepEqual(turn.urls, ['turn:relay.test:3478', 'turns:relay.test:5349']);
  assert.equal(turn.credential, createHmac('sha1', secret).update(turn.username!).digest('base64'));
  assert.equal(JSON.stringify(servers).includes(secret), false);
  assert.notEqual(voiceIceServers('u1', { urls: 'turn:relay.test', secret }, 1000000)[1].credential, turn.credential);
});

test('incomplete or invalid TURN config fails instead of pretending to connect', () => {
  assert.throws(() => voiceIceServers('u0', { urls: 'turn:relay.test' }));
  assert.throws(() => voiceIceServers('u0', { urls: 'https://relay.test', secret: 'test' }));
});
