import { AccessToken, TrackSource } from 'livekit-server-sdk';

export class VoiceAccessError extends Error {
  constructor(public code: 'permission-denied' | 'failed-precondition', message: string) {
    super(message);
  }
}

export interface VoiceRoom {
  voiceRoomId: string;
  players: { uid: string; name: string }[];
  expiresAt: number;
}

/** Only public player identity goes into the token, never game roles. */
export async function issueVoiceAccess(
  config: { url: string; apiKey: string; apiSecret: string },
  room: VoiceRoom,
  uid: string,
  now = Date.now(),
): Promise<{ url: string; token: string }> {
  const player = room.players.find((p) => p.uid === uid);
  if (!player) throw new VoiceAccessError('permission-denied', '你不在這個房間裡');
  if (room.expiresAt <= now || !room.voiceRoomId.startsWith('avalon-')) {
    throw new VoiceAccessError('failed-precondition', '房間已失效，請重新加入');
  }
  let url: URL;
  try { url = new URL(config.url); } catch {
    throw new VoiceAccessError('failed-precondition', '語音服務尚未啟用，仍可繼續遊戲');
  }
  if (url.protocol !== 'wss:' || !config.apiKey || !config.apiSecret) {
    throw new VoiceAccessError('failed-precondition', '語音服務尚未啟用，仍可繼續遊戲');
  }
  const token = new AccessToken(config.apiKey, config.apiSecret, {
    identity: uid, name: player.name, ttl: 300,
  });
  token.addGrant({
    roomJoin: true, room: room.voiceRoomId,
    canSubscribe: true, canPublish: true,
    canPublishSources: [TrackSource.MICROPHONE],
    canPublishData: false, canUpdateOwnMetadata: false,
    roomAdmin: false, roomList: false, roomRecord: false,
  });
  return { url: config.url, token: await token.toJwt() };
}
