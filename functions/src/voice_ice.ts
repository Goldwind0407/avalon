import { createHmac } from 'node:crypto';

export interface IceServer {
  urls: string | string[];
  username?: string;
  credential?: string;
}

/** Exchange a server-only Cloudflare TURN token for four-hour ICE credentials. */
export async function cloudflareIceServers(
  keyId: string, token: string, request: typeof fetch = fetch,
): Promise<IceServer[]> {
  const url = `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(keyId)}/credentials/generate-ice-servers`;
  const response = await request(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ ttl: 4 * 60 * 60 }),
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error('Cloudflare TURN request failed');

  const payload = await response.json() as { iceServers?: unknown[] };
  if (!Array.isArray(payload.iceServers)) throw new Error('Invalid ICE response');
  const servers: IceServer[] = [];
  for (const entry of payload.iceServers) {
    if (!entry || typeof entry !== 'object') continue;
    const { urls, username, credential } = entry as Partial<IceServer>;
    const usable = (Array.isArray(urls) ? urls : [urls]).filter(
      (url): url is string => typeof url === 'string' && !/:53(?:\?|$)/.test(url));
    const stun = usable.filter(url => /^stun:[^\s]+$/.test(url));
    const turn = usable.filter(url => /^turns?:[^\s]+$/.test(url));
    if (stun.length) servers.push({ urls: stun });
    if (turn.length && typeof username === 'string' && username &&
        typeof credential === 'string' && credential) {
      servers.push({ urls: turn, username, credential });
    }
  }
  if (!servers.some(server => server.credential)) throw new Error('No usable TURN credentials');
  return servers;
}

/** coturn's REST authentication: the long-lived shared secret stays server-side. */
export function voiceIceServers(
  uid: string, config: { urls?: string; secret?: string },
  now = Date.now(),
): IceServer[] {
  const servers: IceServer[] = [{ urls: 'stun:stun.l.google.com:19302' }];
  const urls = (config.urls ?? '').split(',').map(s => s.trim()).filter(Boolean);
  if (!urls.length) return servers;
  if (!config.secret || urls.some(url => !/^turns?:[^\s]+$/.test(url))) {
    throw new Error('TURN server configuration is incomplete');
  }
  const username = `${Math.floor(now / 1000) + 4 * 60 * 60}:${uid}`;
  servers.push({ urls, username,
    credential: createHmac('sha1', config.secret).update(username).digest('base64') });
  return servers;
}
