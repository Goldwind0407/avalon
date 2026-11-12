import { createHmac } from 'node:crypto';

export interface IceServer {
  urls: string | string[];
  username?: string;
  credential?: string;
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
