import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/online/voice/voice_mesh.dart';
import 'package:avalon_shadow_council/features/online/voice/voice_signaling.dart';

class Bus {
  final changes = StreamController<void>.broadcast();
  final people = <String, VoicePresence>{};
  final messages = <String, VoiceSignal>{};
  final sent = <VoiceSignal>[];
  int next = 0;
  void emit() => changes.add(null);
}

class MemorySignaling implements VoiceSignaling {
  MemorySignaling(this.bus);
  final Bus bus;
  @override
  Stream<List<VoicePresence>> presence() => Stream.multi((sink) {
        void emit() => sink.add(bus.people.values.toList());
        final sub = bus.changes.stream.listen((_) => emit());
        emit();
        sink.onCancel = sub.cancel;
      });
  @override
  Stream<List<VoiceSignal>> inbox(String uid) => Stream.multi((sink) {
        void emit() =>
            sink.add(bus.messages.values.where((s) => s.to == uid).toList());
        final sub = bus.changes.stream.listen((_) => emit());
        emit();
        sink.onCancel = sub.cancel;
      });
  @override
  Future<void> announce(VoicePresence me) async {
    bus.people[me.uid] = me;
    bus.emit();
  }

  @override
  Future<void> withdraw(VoicePresence me) async {
    if (bus.people[me.uid]?.session == me.session) bus.people.remove(me.uid);
    bus.emit();
  }

  @override
  Future<void> send(VoiceSignal s) async {
    final id = '${bus.next++}';
    final message = VoiceSignal(
        id: id,
        from: s.from,
        fromSession: s.fromSession,
        to: s.to,
        toSession: s.toSession,
        attempt: s.attempt,
        kind: s.kind,
        data: s.data,
        order: bus.next);
    bus.messages[id] = message;
    bus.sent.add(message);
    bus.emit();
  }

  @override
  Future<void> consume(String id) async {
    bus.messages.remove(id);
    bus.emit();
  }
}

class FakePeer extends VoicePeer {
  int offers = 0, answers = 0, acceptedAnswers = 0, closes = 0;
  final candidates = <Map<String, dynamic>>[];
  bool failOffer = false;
  @override
  Future<Map<String, dynamic>> createOffer() async {
    offers++;
    if (failOffer) throw StateError('handshake failed');
    onCandidate?.call({'candidate': 'local-ice'});
    return {'sdp': 'offer', 'type': 'offer'};
  }

  @override
  Future<Map<String, dynamic>> acceptOffer(Map<String, dynamic> offer) async {
    answers++;
    onCandidate?.call({'candidate': 'answer-ice'});
    onState?.call(PeerState.connected);
    return {'sdp': 'answer', 'type': 'answer'};
  }

  @override
  Future<void> acceptAnswer(Map<String, dynamic> answer) async {
    acceptedAnswers++;
    onState?.call(PeerState.connected);
  }

  @override
  Future<void> addCandidate(Map<String, dynamic> candidate) async =>
      candidates.add(candidate);
  @override
  Future<double> remoteLevel() async => .5;
  @override
  Future<void> close() async {
    closes++;
  }
}

Future<void> flush() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Bus bus;
  late List<VoiceMesh> meshes;
  late Map<String, List<FakePeer>> peers;
  setUp(() {
    bus = Bus();
    meshes = [];
    peers = {};
  });
  tearDown(() async {
    await Future.wait([for (final mesh in meshes) mesh.stop()]);
    await bus.changes.close();
  });
  VoiceMesh mesh(String uid,
      {String? session,
      PeerFactory? factory,
      Duration timeout = const Duration(seconds: 20)}) {
    final voice = VoiceMesh(
        uid: uid,
        session: session,
        signaling: MemorySignaling(bus),
        retryDelay: const Duration(milliseconds: 1),
        handshakeTimeout: timeout,
        createPeer: factory ??
            () async {
              final peer = FakePeer();
              peers.putIfAbsent(uid, () => []).add(peer);
              return peer;
            });
    meshes.add(voice);
    return voice;
  }

  test(
      '10 players establish 45 pairs, with offers before ICE and no duplicate peers',
      () async {
    final voices = [for (var i = 0; i < 10; i++) mesh('u$i')];
    await Future.wait([for (final voice in voices) voice.start()]);
    await flush();
    for (final voice in voices) {
      expect(voice.connected.length, 9);
    }
    expect(bus.sent.where((s) => s.kind == 'offer').length, 45);
    expect(peers.values.expand((v) => v).length, 90);
    bus.emit();
    await flush();
    expect(peers.values.expand((v) => v).length, 90);
    for (final offer in bus.sent.where((s) => s.kind == 'offer')) {
      final first =
          bus.sent.firstWhere((s) => s.from == offer.from && s.to == offer.to);
      expect(first.kind, 'offer');
    }
  });

  test('leaving closes both ends; rejoining replaces the old session',
      () async {
    final a = mesh('a'), b = mesh('b');
    await a.start();
    await b.start();
    await flush();
    await b.stop();
    await flush();
    expect(a.connected, isEmpty);
    expect(peers.values.expand((v) => v).every((p) => p.closes == 1), isTrue);
    final replacement = mesh('b');
    await replacement.start();
    await flush();
    expect(a.connected, {'b'});
    expect(replacement.connected, {'a'});
    // A late disconnect from the old controller cannot remove its replacement.
    await MemorySignaling(bus).withdraw(VoicePresence('b', b.session));
    expect(bus.people['b']!.session, replacement.session);
  });

  test(
      'failed handshake retries with a new attempt and rejects stale answer/ICE',
      () async {
    final a = mesh('a'), b = mesh('b');
    await a.start();
    await b.start();
    await flush();
    final staleAnswer = bus.sent.firstWhere((s) => s.kind == 'answer');
    peers['a']!.first.onState!(PeerState.failed);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await flush();
    final current = peers['a']!.last;
    expect(peers['a']!.length, 2);
    expect(current.acceptedAnswers, 1);
    await MemorySignaling(bus).send(staleAnswer);
    await MemorySignaling(bus).send(VoiceSignal(
        from: 'b',
        fromSession: b.session,
        to: 'a',
        toSession: a.session,
        attempt: 1,
        kind: 'candidate',
        data: {'candidate': 'stale'}));
    await flush();
    expect(current.acceptedAnswers, 1);
    expect(current.candidates.any((c) => c['candidate'] == 'stale'), isFalse);
    expect(a.connected, {'b'});
  });

  test(
      'ICE arriving before offer is buffered until remote description is ready',
      () async {
    final b = mesh('b');
    bus.people['a'] = const VoicePresence('a', 'a-session');
    await b.start();
    await flush();
    final signaling = MemorySignaling(bus);
    await signaling.send(VoiceSignal(
        from: 'a',
        fromSession: 'a-session',
        to: 'b',
        toSession: b.session,
        attempt: 1,
        kind: 'candidate',
        data: {'candidate': 'early'}));
    await flush();
    await signaling.send(VoiceSignal(
        from: 'a',
        fromSession: 'a-session',
        to: 'b',
        toSession: b.session,
        attempt: 1,
        kind: 'offer',
        data: {'sdp': 'offer', 'type': 'offer'}));
    await flush();
    expect(peers['b']!.single.candidates, [
      {'candidate': 'early'}
    ]);
  });

  test('native connection created after stop is closed rather than leaked',
      () async {
    final pending = Completer<VoicePeer>();
    final a = mesh('a', factory: () => pending.future);
    bus.people['b'] = const VoicePresence('b', 'b-session');
    await a.start();
    await flush();
    await a.stop();
    final native = FakePeer();
    pending.complete(native);
    await flush();
    expect(native.closes, 1);
    expect(bus.sent, isEmpty);
  });

  test('handshake errors retry a bounded number of times', () async {
    var created = 0;
    final a = mesh('a', factory: () async {
      created++;
      return FakePeer()..failOffer = true;
    }, timeout: const Duration(milliseconds: 3));
    bus.people['b'] = const VoicePresence('b', 'b-session');
    await a.start();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(created, 4);
    expect(a.connected, isEmpty);
  });
}
