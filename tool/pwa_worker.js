const scope = self.registration.scope;
const cachePrefix = `avalon:${scope}:`;
const coreName = `${cachePrefix}${release.version}:core`;
const mediaName = `${cachePrefix}${release.version}:media`;
const voiceName = `${cachePrefix}${release.voiceVersion}:voices`;
const recentVoiceName = `${cachePrefix}${release.voiceVersion}:recent-voices`;
const recentVoiceLimit = 2000;
const filesAtScope = paths => new Set(paths.map(path => new URL(path, scope).href));
const coreUrls = filesAtScope(release.core);
const mediaUrls = filesAtScope(release.media);
const packs = {
  media: {
    paths: [...release.core, ...release.media], name: mediaName,
    bytes: release.coreBytes + release.mediaBytes,
  },
  voice: { paths: release.voicePacks, name: voiceName, bytes: release.voiceBytes },
};
const downloads = new Map();

const marker = kind => new URL(`_avalon_${kind}_complete`, scope).href;
let recentVoices;
let recentUpdates = Promise.resolve();

async function broadcast(message) {
  for (const client of await self.clients.matchAll({ includeUncontrolled: true })) {
    if (client.url.startsWith(scope)) client.postMessage(message);
  }
}

async function download(paths, cache, kind, coreCache) {
  let next = 0;
  let done = 0;
  let failure;
  await broadcast({ kind, state: 'downloading', done, total: paths.length });
  async function run() {
    while (!failure && next < paths.length) {
      const path = paths[next++];
      const url = new URL(path, scope).href;
      try {
        const target = coreCache && coreUrls.has(url) ? coreCache : cache;
        if (!await target.match(url)) {
          // Pages serves index.html at the directory URL. An Access login
          // response must never be saved as a game asset.
          const source = path === 'index.html' ? scope : url;
          const response = await fetch(source, { cache: 'reload', redirect: 'error' });
          if (response.status !== 200 || (path !== 'index.html' &&
              response.headers.get('Content-Type')?.startsWith('text/html'))) {
            throw new Error(`Invalid offline download response: ${url}`);
          }
          await target.put(url, response);
        }
        done++;
        if (kind === 'voice' || done % 40 === 0 || done === paths.length) {
          await broadcast({ kind, state: 'downloading', done, total: paths.length });
        }
      } catch (error) {
        failure = new Error(`${path}: ${error?.message ?? error}`);
      }
    }
  }
  await Promise.all(Array.from({ length: kind === 'voice' ? 2 : 8 }, run));
  if (failure) throw failure;
}

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    // Users who already downloaded the game keep offline access during upgrades.
    // A first visit installs the worker without downloading the offline game.
    if (await caches.match(marker('media'))) await storeOfflinePack('media');
    // Take over at once: an app on the iPhone's home screen is rarely
    // closed, so waiting for it would keep the old version for days. The
    // page reloads when the player is off the table (web/pwa.js); the old
    // version's files are gone from the server anyway.
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter(name =>
      name.startsWith(cachePrefix) && ![coreName, mediaName, voiceName, recentVoiceName].includes(name)
    ).map(name => caches.delete(name)));
    await self.clients.claim();
  })());
});

async function storeOfflinePack(kind) {
  const { paths, name } = packs[kind];
  const cache = await caches.open(name);
  const coreCache = kind === 'media' ? await caches.open(coreName) : null;
  await download(paths, cache, kind, coreCache);
  await cache.put(marker(kind), new Response('ready'));
}

async function downloadPack(kind) {
  try {
    await storeOfflinePack(kind);
    await broadcast({ kind, state: 'ready' });
  } catch (error) {
    await broadcast({ kind, state: 'error', reason: String(error?.message ?? error) });
  }
}

self.addEventListener('message', event => {
  if (event.data === 'avalon-status') {
    event.waitUntil((async () => {
      for (const [pack, { name, bytes }] of Object.entries(packs)) {
        event.source?.postMessage({
          kind: 'status', pack, bytes, busy: downloads.has(pack),
          ready: Boolean(await caches.match(marker(pack), { cacheName: name })),
        });
      }
    })());
  }
  const kind = event.data === 'avalon-download-media' ? 'media'
    : event.data === 'avalon-download-voices' ? 'voice' : null;
  if (kind) {
    if (!downloads.has(kind)) {
      downloads.set(kind, downloadPack(kind).finally(() => downloads.delete(kind)));
    }
    event.waitUntil(downloads.get(kind));
  }
});

// Keep on-demand NPC audio separate from the complete, user-downloaded pack.
// Cache insertion order seeds the order when the browser restarts the worker.
function rememberVoice(cache, url, response) {
  const update = recentUpdates.then(async () => {
    recentVoices ??= new Set((await cache.keys()).map(entry => entry.url));
    if (response) await cache.put(url, response);
    if (!response && !recentVoices.has(url)) return;
    recentVoices.delete(url);
    recentVoices.add(url);
    while (recentVoices.size > recentVoiceLimit) {
      const oldest = recentVoices.values().next().value;
      await cache.delete(oldest);
      recentVoices.delete(oldest);
    }
  });
  recentUpdates = update.catch(() => {}); // A full cache must never stall playback.
  return recentUpdates;
}

async function fetchMedia(event, request, url) {
  const saved = await caches.match(url, { cacheName: mediaName });
  if (saved) return mediaResponse(request, saved);

  // Safari can ask for a byte range on the first play. Store a complete
  // response so later ranges can be served while offline.
  const response = await fetch(new Request(url, { credentials: 'same-origin' }));
  if (response.status === 200 && !response.redirected &&
      !response.headers.get('Content-Type')?.startsWith('text/html')) {
    const copy = response.clone();
    event.waitUntil(caches.open(mediaName).then(cache => cache.put(url, copy))
      .catch(() => {}));
  }
  return response.status === 200 ? mediaResponse(request, response) : response;
}

// A cached response (or a host ignoring Range) may contain the entire
// persona pack. Retain only this clip and stop reading once it is complete.
async function readClip(response, offset, length, headers) {
  const reader = response.body?.getReader();
  if (!reader) return null;
  const clip = new Uint8Array(length);
  let position = 0;
  try {
    while (position < offset + length) {
      const { value, done } = await reader.read();
      if (done) return null;
      const start = Math.max(0, offset - position);
      const end = Math.min(value.length, offset + length - position);
      if (end > start) clip.set(value.subarray(start, end), position + start - offset);
      position += value.length;
    }
    return new Response(clip, { headers });
  } finally {
    reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

async function fetchVoice(request, url, [pack, offset, length]) {
  const packUrl = new URL(release.voicePacks[pack], scope).href;
  const headers = { 'Content-Type': 'audio/mpeg', 'Content-Length': length, 'Accept-Ranges': 'bytes' };
  const downloaded = await caches.match(packUrl, { cacheName: voiceName });
  if (downloaded) {
    const clip = await readClip(downloaded, offset, length, headers);
    if (clip) return mediaResponse(request, clip);
  }

  const recentCache = await caches.open(recentVoiceName).catch(() => null);
  const recent = await recentCache?.match(url);
  if (recent) {
    await rememberVoice(recentCache, url);
    return mediaResponse(request, recent);
  }

  const range = `${offset}-${offset + length - 1}`;
  const partial = await fetch(packUrl, { headers: { Range: `bytes=${range}` } });
  let clip;
  if (partial.status === 206 && partial.headers.get('Content-Range')?.startsWith(`bytes ${range}/`)) {
    clip = new Response(partial.body, { headers });
  } else if (partial.status === 200 && !partial.redirected &&
             !partial.headers.get('Content-Type')?.startsWith('text/html')) {
    // Some static hosts return the whole file for a range request.
    clip = await readClip(partial, offset, length, headers);
  }
  if (!clip) return new Response(null, { status: 502 });
  if (recentCache) await rememberVoice(recentCache, url, clip.clone());
  return mediaResponse(request, clip);
}

async function mediaResponse(request, response) {
  const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.get('Range') || '');
  if (!range || (!range[1] && !range[2])) return response;
  const file = await response.blob();
  const start = range[1] ? Number(range[1]) : Math.max(0, file.size - Number(range[2]));
  const end = range[1] && range[2]
    ? Math.min(Number(range[2]), file.size - 1)
    : file.size - 1;
  if (start > end) {
    return new Response(null, {
      status: 416, headers: { 'Content-Range': `bytes */${file.size}` },
    });
  }
  return new Response(file.slice(start, end + 1, file.type), {
    status: 206,
    headers: {
      'Accept-Ranges': 'bytes',
      'Content-Type': file.type || 'application/octet-stream',
      'Content-Length': end - start + 1,
      'Content-Range': `bytes ${start}-${end}/${file.size}`,
    },
  });
}

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET' || !request.url.startsWith(scope)) return;
  const url = new URL(request.url);
  url.search = '';
  if (request.mode === 'navigate' &&
      (url.href === scope || url.href === new URL('index.html', scope).href)) {
    event.respondWith(caches.match(new URL('index.html', scope).href, { cacheName: coreName })
      .then(response => response || fetch(request)));
  } else if (coreUrls.has(url.href)) {
    event.respondWith(caches.match(url.href, { cacheName: coreName })
      .then(response => response || fetch(request)));
  } else if (mediaUrls.has(url.href)) {
    event.respondWith(fetchMedia(event, request, url.href));
  } else {
    const clip = release.voiceIndex[url.href.slice(scope.length)];
    if (Array.isArray(clip)) event.respondWith(fetchVoice(request, url.href, clip));
  }
});
