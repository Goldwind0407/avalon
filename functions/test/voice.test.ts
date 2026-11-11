import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { TokenVerifier } from 'livekit-server-sdk';
import { issueVoiceAccess, VoiceAccessError, VoiceRoom } from '../src/voice';

const config = { url: 'wss://test.livekit.cloud', apiKey: 'test-key', apiSecret: 'test-secret-at-least-32-characters-long' };
const room: VoiceRoom = { voiceRoomId: 'avalon-test-unique-room',
  players: [{ uid: 'member', name: '亞瑟' }], expiresAt: Date.now() + 3600000 };

test('member token is bound to identity, unique room and microphone-only publishing', async () => {
  const access = await issueVoiceAccess(config, room, 'member');
  const claims = await new TokenVerifier(config.apiKey, config.apiSecret).verify(access.token);
  assert.equal(access.url, config.url);
  assert.equal(claims.sub, 'member');
  assert.equal(claims.name, '亞瑟');
  assert.equal(claims.video?.room, room.voiceRoomId);
  assert.equal(claims.video?.roomJoin, true);
  assert.equal(claims.video?.canSubscribe, true);
  assert.deepEqual(claims.video?.canPublishSources, ['microphone']);
  assert.equal(claims.video?.canPublishData, false);
  assert.equal(claims.video?.roomAdmin, false);
  assert.equal(claims.video?.roomRecord, false);
  assert.equal(claims.video?.canUpdateOwnMetadata, false);
  assert.equal(claims.exp! - claims.nbf!, 300);
  assert.equal(claims.metadata, undefined);
});

test('nonmembers and expired rooms cannot get voice access', async () => {
  await assert.rejects(issueVoiceAccess(config, room, 'outsider'),
    (e: unknown) => e instanceof VoiceAccessError && e.code === 'permission-denied');
  await assert.rejects(issueVoiceAccess(config, { ...room, expiresAt: 0 }, 'member'),
    (e: unknown) => e instanceof VoiceAccessError && e.code === 'failed-precondition');
});

test('missing credentials and insecure URLs fail without returning secrets', async () => {
  for (const invalid of [{ ...config, url: '' }, { ...config, apiSecret: '' }, { ...config, url: 'ws://test.local' }]) {
    await assert.rejects(issueVoiceAccess(invalid, room, 'member'), (e: unknown) =>
      e instanceof VoiceAccessError && e.message === '語音服務尚未啟用，仍可繼續遊戲');
  }
});

test('a reused game code can never authorize a different voice namespace', async () => {
  const access = await issueVoiceAccess(config, { ...room, voiceRoomId: 'avalon-another-room' }, 'member');
  const claims = await new TokenVerifier(config.apiKey, config.apiSecret).verify(access.token);
  assert.notEqual(claims.video?.room, room.voiceRoomId);
});
