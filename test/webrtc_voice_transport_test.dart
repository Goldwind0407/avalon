import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/online/voice/voice_controller.dart';
import 'package:avalon_shadow_council/features/online/voice/voice_mesh.dart';
import 'package:avalon_shadow_council/features/online/voice/webrtc_voice_transport.dart';
import 'voice_mesh_test.dart' show Bus, MemorySignaling, FakePeer, flush;

class AudioDevice implements VoiceAudio {
  bool microphone = false, closed = false, deny = false;
  int captures = 0, initializations = 0;
  Completer<void>? pendingInitialize;
  final peers = <FakePeer>[];
  @override
  Future<void> initialize() async {
    initializations++;
    await pendingInitialize?.future;
  }

  @override
  Future<VoicePeer> createPeer() async {
    final peer = FakePeer();
    peers.add(peer);
    return peer;
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (deny) throw StateError('permission denied');
    if (enabled) captures++;
    microphone = enabled;
  }

  @override
  Future<double> localLevel() async => microphone ? .5 : 0;
  @override
  Future<void> close() async {
    closed = true;
    microphone = false;
  }
}

void main() {
  late Bus bus;
  late List<WebRtcVoiceTransport> transports;
  setUp(() {
    bus = Bus();
    transports = [];
  });
  tearDown(() async {
    await Future.wait([for (final transport in transports) transport.close()]);
    await bus.changes.close();
  });
  WebRtcVoiceTransport transport(String uid, AudioDevice audio) {
    final voice = WebRtcVoiceTransport(
        uid: uid,
        audio: audio,
        signaling: MemorySignaling(bus),
        sampleInterval: const Duration(milliseconds: 3));
    transports.add(voice);
    return voice;
  }

  test(
      'joining listens without capture, reports actual peers and speaking UIDs',
      () async {
    final ad = AudioDevice(), bd = AudioDevice();
    final a = transport('a', ad), b = transport('b', bd);
    final updates = <VoiceUpdate>[];
    final sub = a.updates.listen(updates.add);
    await a.connect();
    await flush();
    expect(ad.captures, 0);
    expect(updates.last.participants, 0);
    await b.connect();
    await flush();
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(updates.last.connections, 1);
    expect(updates.last.participants, 1);
    expect(updates.last.speakers, {'b'});
    await a.setMicrophoneEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(updates.last.speakers, {'a', 'b'});
    await a.setMicrophoneEnabled(false);
    await flush();
    expect(ad.microphone, isFalse);
    expect(updates.last.speakers.contains('a'), isFalse);
    await b.close();
    await flush();
    expect(updates.last.connections, 0);
    await a.close();
    expect(ad.closed, isTrue);
    await sub.cancel();
  });

  test('microphone refusal keeps capture off and can be retried', () async {
    final audio = AudioDevice()..deny = true;
    final voice = transport('a', audio);
    await voice.connect();
    await expectLater(voice.setMicrophoneEnabled(true), throwsStateError);
    expect(audio.microphone, isFalse);
    audio.deny = false;
    await voice.setMicrophoneEnabled(true);
    expect(audio.microphone, isTrue);
    await voice.close();
    expect(audio.microphone, isFalse);
    await expectLater(
        voice.setMicrophoneEnabled(true), throwsA(isA<VoiceException>()));
  });

  test('late initialization after close never announces voice presence',
      () async {
    final audio = AudioDevice()..pendingInitialize = Completer<void>();
    final voice = transport('a', audio);
    final pending = voice.connect();
    await voice.close();
    audio.pendingInitialize!.complete();
    await pending;
    expect(bus.people, isEmpty);
    expect(audio.captures, 0);
  });
}
