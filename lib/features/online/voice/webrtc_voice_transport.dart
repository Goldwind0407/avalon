import 'dart:async';
import 'voice_controller.dart';
import 'voice_mesh.dart';
import 'voice_signaling.dart';
import 'webrtc_voice_audio.dart';

abstract class VoiceAudio {
  Future<void> initialize();
  Future<VoicePeer> createPeer();
  Future<void> setMicrophoneEnabled(bool enabled);
  Future<double> localLevel();
  Future<void> close();
}

class WebRtcVoiceTransport implements VoiceTransport, VoiceFloorTransport {
  WebRtcVoiceTransport(
      {required this.uid,
      required this.signaling,
      Future<List<Map<String, dynamic>>> Function()? iceServers,
      VoiceAudio? audio,
      this.sampleInterval = const Duration(milliseconds: 750)})
      : _audio = audio ?? WebRtcVoiceAudio(iceServers: iceServers);
  final String uid;
  final VoiceSignaling signaling;
  final VoiceAudio _audio;
  final Duration sampleInterval;
  final _updates = StreamController<VoiceUpdate>.broadcast();
  VoiceMesh? _mesh;
  StreamSubscription<void>? _subscription;
  Timer? _levels;
  Future<void>? _closing;
  bool _microphone = false, _sampling = false, _ready = false;
  Set<String> _speakers = {};
  String? _lastUpdate;
  Set<String>? _allowedSpeakers;
  @override
  void setAllowedSpeakers(Set<String>? allowed) {
    _allowedSpeakers = allowed;
    _applyFloor();
  }

  void _applyFloor() {
    for (final entry in (_mesh?.allPeers ?? <String, VoicePeer>{}).entries) {
      entry.value.setPlaybackEnabled(
          _allowedSpeakers == null || _allowedSpeakers!.contains(entry.key));
    }
  }

  @override
  Stream<VoiceUpdate> get updates => _updates.stream;

  @override
  Future<void> connect() async {
    await _audio.initialize().timeout(const Duration(seconds: 15));
    if (_closing != null) return;
    final mesh = _mesh = VoiceMesh(
        uid: uid, signaling: signaling, createPeer: _audio.createPeer);
    _subscription =
        mesh.changes.listen((_) => _emit(), onError: (Object error) {
      if (_closing != null) return;
      _updates.add(const VoiceUpdate(VoiceStatus.failed));
      unawaited(close());
    });
    await mesh.start().timeout(const Duration(seconds: 15));
    if (_closing != null) return;
    _ready = true;
    _emit();
    _levels = Timer.periodic(sampleInterval, (_) => unawaited(_sample()));
  }

  void _emit() {
    _applyFloor();
    if (_closing != null || !_ready) return;
    final connected = _mesh!.connected;
    _speakers = _speakers.intersection({...connected, if (_microphone) uid});
    if (_allowedSpeakers != null) {
      _speakers = _speakers.intersection(_allowedSpeakers!);
    }
    final update = VoiceUpdate(VoiceStatus.connected,
        microphone: _microphone,
        speakers: Set.unmodifiable(_speakers),
        connections: connected.length,
        participants: _mesh!.participants.length);
    final sorted = _speakers.toList()..sort();
    final key =
        '$_microphone/${update.connections}/${update.participants}/$sorted';
    if (_lastUpdate == key) return;
    _lastUpdate = key;
    _updates.add(update);
  }

  Future<void> _sample() async {
    if (_closing != null || _sampling || !_ready) return;
    _sampling = true;
    try {
      final speakers = <String>{};
      final peers = _mesh!.peers;
      await Future.wait([
        for (final entry in peers.entries)
          () async {
            try {
              if (await entry.value.remoteLevel() > .02) {
                speakers.add(entry.key);
              }
            } catch (_) {/* A peer may close during sampling. */}
          }(),
        if (_microphone)
          () async {
            try {
              if (await _audio.localLevel() > .02) speakers.add(uid);
            } catch (_) {/* Microphone may close during sampling. */}
          }(),
      ]);
      if (_closing != null) return;
      _speakers = speakers;
      _emit();
    } finally {
      _sampling = false;
    }
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (_closing != null || !_ready) throw const VoiceException('語音已斷線');
    await _audio.setMicrophoneEnabled(enabled);
    if (_closing != null) return;
    _microphone = enabled;
    _emit();
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _ready = false;
    _levels?.cancel();
    final cancelled = _subscription?.cancel();
    try {
      // Stop the physical mic before any Firestore cleanup can wait on network.
      await _audio.close();
    } finally {
      try {
        await _mesh?.stop();
      } catch (_) {/* Offline cleanup expires. */}
      await cancelled;
      await _updates.close();
    }
  }
}
