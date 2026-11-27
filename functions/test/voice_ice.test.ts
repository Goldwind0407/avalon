import { strict as assert } from 'node:assert';
import { createHmac } from 'node:crypto';
import { test } from 'node:test';
import { cloudflareIceServers, voiceIceServers } from '../src/voice_ice';

test('Cloudflare issues short-lived credentials and blocked port 53 is omitted', async () => {
  const servers = await cloudflareIceServers('test-key', 'test-api-token', async (url, init) => {
    assert.equal(url, 'https://rtc.live.cloudflare.com/v1/turn/keys/test-key/credentials/generate-ice-servers');
    assert.equal(init?.method, 'POST');
    assert.equal(new Headers(init?.headers).get('Authorization'), 'Bearer test-api-token');
    assert.deepEqual(JSON.parse(String(init?.body)), { ttl: 14400 });
    return Response.json({ iceServers: [
      { urls: ['stun:stun.cloudflare.com:3478'] },
      { urls: ['turn:turn.cloudflare.com:53?transport=udp', 'turns:turn.cloudflare.com:443?transport=tcp'],
        username: 'temporary-user', credential: 'temporary-password' },
    ] }, { status: 201 });
  });
  assert.deepEqual(servers, [
    { urls: ['stun:stun.cloudflare.com:3478'] },
    { urls: ['turns:turn.cloudflare.com:443?transport=tcp'],
      username: 'temporary-user', credential: 'temporary-password' },
  ]);
});

test('Cloudflare HTTP errors and responses without a usable relay are rejected', async () => {
  await assert.rejects(
    cloudflareIceServers('key', 'token', async () => new Response(null, { status: 401 })),
    /request failed/,
  );
  await assert.rejects(
    cloudflareIceServers('key', 'token', async () => Response.json({ iceServers: [
      { urls: 'stun:stun.cloudflare.com:3478' },
      { urls: 'turns:turn.cloudflare.com:443' },
    ] })),
    /No usable TURN credentials/,
  );
});

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
