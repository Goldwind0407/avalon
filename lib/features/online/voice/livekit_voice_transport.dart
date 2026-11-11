import 'dart:async';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'voice_controller.dart';

class LiveKitVoiceTransport implements VoiceTransport {
  final _updates = StreamController<VoiceUpdate>.broadcast();
  final _room = lk.Room(
      roomOptions: const lk.RoomOptions(
    defaultAudioCaptureOptions: lk.AudioCaptureOptions(
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
      stopAudioCaptureOnMute: true,
    ),
  ));
  lk.EventsListener<lk.RoomEvent>? _events;
  Future<void>? _closing;

  @override
  Stream<VoiceUpdate> get updates => _updates.stream;

  void _emit(VoiceStatus status) {
    if (_updates.isClosed || _closing != null) return;
    _updates.add(VoiceUpdate(
      status,
      microphone: _room.localParticipant?.isMicrophoneEnabled() ?? false,
      speakers: status == VoiceStatus.connected
          ? _room.activeSpeakers.map((p) => p.identity).toSet()
          : {},
    ));
  }

  @override
  Future<void> connect(VoiceCredentials credentials) async {
    _events = _room.createListener()
      ..on<lk.RoomReconnectingEvent>((_) => _emit(VoiceStatus.reconnecting))
      ..on<lk.RoomResumingEvent>((_) => _emit(VoiceStatus.reconnecting))
      ..on<lk.RoomReconnectedEvent>((_) => _emit(VoiceStatus.connected))
      ..on<lk.RoomDisconnectedEvent>((_) => _emit(VoiceStatus.failed))
      ..on<lk.ActiveSpeakersChangedEvent>((_) => _emit(VoiceStatus.connected));
    await _room.connect(credentials.url, credentials.token);
    // Connecting subscribes to others but does not publish or open the mic.
    _emit(VoiceStatus.connected);
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    final participant = _room.localParticipant;
    if (participant == null || _closing != null) {
      throw const VoiceException('語音已斷線');
    }
    await participant.setMicrophoneEnabled(enabled);
    _emit(VoiceStatus.connected);
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    await _events?.dispose();
    try {
      await _room.disconnect();
    } finally {
      await _room.dispose();
      await _updates.close();
    }
  }
}
