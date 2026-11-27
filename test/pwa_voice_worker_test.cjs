const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const env = {
  self: {registration: {scope: 'https://localhost/'}, addEventListener() {}},
  release: {core: [], media: [], voicePacks: []},
  Response, URL, Uint8Array,
};
vm.createContext(env);
vm.runInContext(fs.readFileSync('tool/pwa_worker.js', 'utf8'), env);

test('offline voice reads only through the end of a clip that spans chunks', async () => {
  let next = 0, cancelled = false;
  const body = new ReadableStream({
    pull(controller) {
      controller.enqueue(Uint8Array.of(next++, next++));
    },
    cancel() { cancelled = true; },
  }, { highWaterMark: 0 });
  const clip = await env.readClip(new Response(body), 3, 4, {});
  assert.deepEqual([...new Uint8Array(await clip.arrayBuffer())], [3, 4, 5, 6]);
  assert.equal(next, 8);
  assert.ok(cancelled);
});

test('an incomplete voice pack is never returned as a playable clip', async () => {
  assert.equal(await env.readClip(new Response(Uint8Array.of(1, 2)), 1, 2, {}), null);
});

test('first image can render while its offline copy is being written', async () => {
  let finishWrite, background;
  const written = new Promise(resolve => { finishWrite = resolve; });
  env.caches = {match: async () => undefined, open: async () => ({put: () => written})};
  env.fetch = async () => new Response('picture', {headers: {'Content-Type': 'image/webp'}});
  env.Request = Request;
  const url = 'https://localhost/role.webp';
  const response = await env.fetchMedia({waitUntil(p) { background = p; }}, new Request(url), url);
  assert.equal(await response.text(), 'picture');
  assert.ok(background);
  finishWrite();
  await background;
});
