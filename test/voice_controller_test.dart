import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/online/voice/voice_controller.dart';

class FakeVoiceTransport implements VoiceTransport {
  final events = StreamController<VoiceUpdate>.broadcast();
  final microphoneRequests = <bool>[];
  int connections = 0;
  int closes = 0;
  bool denied = false;
  Completer<void>? pendingConnect;
  @override
  Stream<VoiceUpdate> get updates => events.stream;
  @override
  Future<void> connect(VoiceCredentials _) async {
    connections++;
    await pendingConnect?.future;
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
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
    voice = VoiceController(
        credentials: () async =>
            const VoiceCredentials('wss://voice.test', 'test-token'),
        createTransport: () => transport);
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

  test('late token after leave cannot open a connection', () async {
    final access = Completer<VoiceCredentials>();
    voice.dispose();
    voice = VoiceController(
        credentials: () => access.future, createTransport: () => transport);
    final pending = voice.join();
    await Future<void>.delayed(Duration.zero);
    await voice.leave();
    access.complete(const VoiceCredentials('wss://voice.test', 'late-token'));
    await pending;
    expect(transport.connections, 0);
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
    voice = VoiceController(
        credentials: () async => const VoiceCredentials('', ''),
        createTransport: () => transport);
  });

  test('service not configured is recoverable and never opens the mic',
      () async {
    voice.dispose();
    voice = VoiceController(
        credentials: () async => throw const VoiceException('語音服務尚未啟用'),
        createTransport: () => transport);
    await voice.join();
    expect(voice.status, VoiceStatus.failed);
    expect(voice.error, '語音服務尚未啟用');
    expect(transport.connections, 0);
    expect(transport.microphoneRequests, isEmpty);
  });
}
