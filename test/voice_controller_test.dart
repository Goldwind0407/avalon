import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/online/voice/voice_controller.dart';

class FakeVoiceTransport implements VoiceTransport {
  final events = StreamController<VoiceUpdate>.broadcast();
  final microphoneRequests = <bool>[];
  int connections = 0;
  int closes = 0;
  bool denied = false;
  bool failConnect = false;
  Completer<void>? pendingConnect;
  Completer<void>? pendingMicrophone;
  @override
  Stream<VoiceUpdate> get updates => events.stream;
  @override
  Future<void> connect() async {
    connections++;
    if (failConnect) throw const VoiceException('無法連上語音');
    await pendingConnect?.future;
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    await pendingMicrophone?.future;
    if (denied) throw Exception('permission denied');
    microphoneRequests.add(enabled);
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  late FakeVoiceTransport transport;
  late VoiceController voice;
  setUp(() {
    transport = FakeVoiceTransport();
    voice = VoiceController(createTransport: () => transport);
  });
  tearDown(() async {
    voice.dispose();
    await Future<void>.delayed(Duration.zero);
    await transport.events.close();
  });

  test('join listens without opening mic and duplicate join does not reconnect',
      () async {
    await Future.wait([voice.join(), voice.join()]);
    expect(voice.connected, isTrue);
    expect(voice.microphone, isFalse);
    expect(transport.microphoneRequests, isEmpty);
    expect(transport.connections, 1);
    await voice.toggleMicrophone();
    expect(voice.microphone, isTrue);
    await voice.toggleMicrophone();
    expect(voice.microphone, isFalse);
    expect(transport.microphoneRequests, [true, false]);
  });

  test('leaving the app closes the microphone, also one still opening',
      () async {
    await voice.join();
    await voice.toggleMicrophone();
    voice.releaseMicrophone();
    await Future<void>.delayed(Duration.zero);
    expect(voice.microphone, isFalse);
    expect(voice.connected, isTrue); // still listening
    expect(transport.microphoneRequests, [true, false]);

    transport.pendingMicrophone = Completer<void>();
    final opening = voice.toggleMicrophone();
    voice.releaseMicrophone();
    transport.pendingMicrophone!.complete();
    await opening;
    await Future<void>.delayed(Duration.zero);
    expect(voice.microphone, isFalse);
    expect(transport.microphoneRequests.last, isFalse);
  });

  test('permission refusal preserves muted state and allows another attempt',
      () async {
    await voice.join();
    transport.denied = true;
    await voice.toggleMicrophone();
    expect(voice.microphone, isFalse);
    expect(voice.error, contains('權限'));
    expect(voice.microphoneBusy, isFalse);
    transport.denied = false;
    await voice.toggleMicrophone();
    expect(voice.microphone, isTrue);
  });

  test('a floor change while joining never mutes a not-yet-ready transport',
      () async {
    transport.pendingConnect = Completer<void>();
    final joining = voice.join();
    await Future<void>.delayed(Duration.zero);
    voice.setFloor({'other'}, 'me');
    await Future<void>.delayed(Duration.zero);
    expect(voice.status, VoiceStatus.connecting);
    expect(transport.microphoneRequests, isEmpty);
    expect(transport.closes, 0);
    transport.pendingConnect!.complete();
    await joining;
    expect(voice.connected, isTrue);
    expect(voice.microphoneAllowed, isFalse);
    await voice.toggleMicrophone();
    expect(transport.microphoneRequests, isEmpty);
  });

  test('floor loss cancels pending mic and restoring floor never opens it',
      () async {
    await voice.join();
    transport.pendingMicrophone = Completer<void>();
    final opening = voice.toggleMicrophone();
    voice.setFloor({'other'}, 'me');
    expect(voice.microphoneAllowed, isFalse);
    transport.pendingMicrophone!.complete();
    await opening;
    await Future<void>.delayed(Duration.zero);
    expect(voice.microphone, isFalse);
    expect(transport.microphoneRequests.last, isFalse);
    final count = transport.microphoneRequests.length;
    await voice.toggleMicrophone();
    expect(transport.microphoneRequests.length, count);
    voice.setFloor({'me'}, 'me');
    expect(voice.microphoneAllowed, isTrue);
    expect(voice.microphone, isFalse);
    transport.pendingMicrophone = null;
    await voice.toggleMicrophone();
    expect(voice.microphone, isTrue);
    voice.setFloor({}, 'me');
    await Future<void>.delayed(Duration.zero);
    expect(voice.microphone, isFalse);
    expect(transport.microphoneRequests.last, isFalse);
  });

  test('speaker identity and reconnect events update the UI state', () async {
    await voice.join();
    transport.events
        .add(const VoiceUpdate(VoiceStatus.connected, speakers: {'u1'}));
    await Future<void>.delayed(Duration.zero);
    expect(voice.isSpeaking('u1'), isTrue);
    transport.events.add(const VoiceUpdate(VoiceStatus.reconnecting));
    await Future<void>.delayed(Duration.zero);
    expect(voice.status, VoiceStatus.reconnecting);
    expect(voice.speakers, isEmpty);
    transport.events.add(const VoiceUpdate(VoiceStatus.connected));
    await Future<void>.delayed(Duration.zero);
    expect(voice.connected, isTrue);
  });

  test('late microphone permission cannot unmute a failed connection',
      () async {
    await voice.join();
    transport.pendingMicrophone = Completer<void>();
    final pending = voice.toggleMicrophone();
    transport.events.add(const VoiceUpdate(VoiceStatus.failed));
    await Future<void>.delayed(Duration.zero);
    transport.pendingMicrophone!.complete();
    await pending;
    expect(voice.status, VoiceStatus.failed);
    expect(voice.microphone, isFalse);
  });

  test('leaving closes audio and ignores subsequent speaker events', () async {
    await voice.join();
    await voice.toggleMicrophone();
    await voice.leave();
    transport.events.add(const VoiceUpdate(VoiceStatus.connected,
        microphone: true, speakers: {'u1'}));
    await Future<void>.delayed(Duration.zero);
    expect(transport.closes, 1);
    expect(voice.status, VoiceStatus.offline);
    expect(voice.microphone, isFalse);
    expect(voice.speakers, isEmpty);
  });

  test('late connection after leave cannot reactivate voice', () async {
    transport.pendingConnect = Completer<void>();
    final pending = voice.join();
    await Future<void>.delayed(Duration.zero);
    await voice.leave();
    transport.pendingConnect!.complete();
    await pending;
    expect(transport.closes, greaterThanOrEqualTo(1));
    expect(voice.status, VoiceStatus.offline);
  });

  test('pending connection cannot become active after disposal', () async {
    transport.pendingConnect = Completer<void>();
    final pending = voice.join();
    await Future<void>.delayed(Duration.zero);
    voice.dispose();
    transport.pendingConnect!.complete();
    await pending;
    expect(transport.closes, greaterThanOrEqualTo(1));
    // Avoid disposing the same ChangeNotifier in tearDown.
    voice = VoiceController(createTransport: () => transport);
  });

  test('connection failure is recoverable and never opens the mic', () async {
    transport.failConnect = true;
    await voice.join();
    expect(voice.status, VoiceStatus.failed);
    expect(voice.error, '無法連上語音');
    expect(transport.connections, 1);
    expect(transport.microphoneRequests, isEmpty);
    transport.failConnect = false;
    await voice.join();
    expect(voice.connected, isTrue);
  });
}
