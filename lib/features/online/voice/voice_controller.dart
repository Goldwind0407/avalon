import 'dart:async';
import 'package:flutter/foundation.dart';

enum VoiceStatus { offline, connecting, connected, reconnecting, failed }

class VoiceUpdate {
  const VoiceUpdate(this.status,
      {this.microphone = false,
      this.speakers = const {},
      this.connections = 0,
      this.participants = 0});
  final VoiceStatus status;
  final bool microphone;
  final Set<String> speakers;
  final int connections, participants;
}

class VoiceException implements Exception {
  const VoiceException(this.message);
  final String message;
}

abstract class VoiceTransport {
  Stream<VoiceUpdate> get updates;
  Future<void> connect();
  Future<void> setMicrophoneEnabled(bool enabled);
  Future<void> close();
}

/// A receiver also filters audio from seats without the current floor.
abstract class VoiceFloorTransport {
  void setAllowedSpeakers(Set<String>? allowed);
}

/// Owned by the online room, not the game route. Joining is explicit and muted;
/// the local game never constructs this controller or requests microphone access.
class VoiceController extends ChangeNotifier {
  VoiceController({required this.createTransport});
  final VoiceTransport Function() createTransport;
  VoiceStatus status = VoiceStatus.offline;
  bool microphone = false;
  bool microphoneBusy = false;
  Set<String> speakers = {};
  int connections = 0, participants = 0;
  String? error;
  VoiceTransport? _transport;
  StreamSubscription<VoiceUpdate>? _subscription;
  int _generation = 0;
  bool _disposed = false;
  bool microphoneAllowed = true;
  Set<String>? _allowedSpeakers;
  int _floorVersion = 0;

  void setFloor(Set<String>? allowed, String uid) {
    if (setEquals(allowed, _allowedSpeakers)) return;
    _allowedSpeakers = allowed == null ? null : Set.unmodifiable(allowed);
    ++_floorVersion;
    microphoneAllowed = allowed == null || allowed.contains(uid);
    final transport = _transport;
    if (transport is VoiceFloorTransport) {
      (transport as VoiceFloorTransport).setAllowedSpeakers(_allowedSpeakers);
    }
    if (!microphoneAllowed) {
      microphone = false;
      if (transport != null) unawaited(_forceMute(transport));
    }
    _notify();
  }

  Future<void> _forceMute(VoiceTransport transport) async {
    try {
      await transport.setMicrophoneEnabled(false);
    } catch (_) {
      if (!_disposed && _transport == transport) {
        await leave();
        error = '關閉麥克風失敗，已離開語音，請重新加入';
      }
    }
    _notify();
  }

  bool get busy => status == VoiceStatus.connecting || microphoneBusy;
  bool get connected => status == VoiceStatus.connected;
  bool isSpeaking(String uid) => speakers.contains(uid);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> join() async {
    if (_disposed || busy || connected || status == VoiceStatus.reconnecting) {
      return;
    }
    final generation = ++_generation;
    status = VoiceStatus.connecting;
    microphone = false;
    speakers = {};
    connections = participants = 0;
    error = null;
    _notify();
    await _detach();
    if (_disposed || generation != _generation) return;
    VoiceTransport? transport;
    try {
      transport = createTransport();
      _transport = transport;
      if (transport is VoiceFloorTransport) {
        (transport as VoiceFloorTransport).setAllowedSpeakers(_allowedSpeakers);
      }
      _subscription = transport.updates.listen((update) {
        if (_disposed || generation != _generation) return;
        status = update.status;
        microphone = microphoneAllowed && update.microphone;
        speakers = Set.unmodifiable(update.speakers);
        connections = update.connections;
        participants = update.participants;
        if (status == VoiceStatus.failed) error = '語音已斷線，請重新加入';
        _notify();
      });
      await transport.connect();
      if (_disposed || generation != _generation) {
        await transport.close();
        return;
      }
      if (status == VoiceStatus.connecting) status = VoiceStatus.connected;
      _notify();
    } catch (e) {
      if (_disposed || generation != _generation) return;
      await _detach();
      if (_disposed || generation != _generation) return;
      status = VoiceStatus.failed;
      error = e is VoiceException ? e.message : '無法加入語音，請檢查網路後重試';
      _notify();
    }
  }

  Future<void> toggleMicrophone() async {
    if (_disposed || !connected || microphoneBusy || _transport == null) return;
    if (!microphone && !microphoneAllowed) return;
    final generation = _generation;
    final floorVersion = _floorVersion;
    final enabled = !microphone;
    microphoneBusy = true;
    error = null;
    _notify();
    try {
      final transport = _transport!;
      await transport.setMicrophoneEnabled(enabled);
      if (enabled && (floorVersion != _floorVersion || !microphoneAllowed)) {
        await transport.setMicrophoneEnabled(false);
        return;
      }
      if (!_disposed &&
          generation == _generation &&
          connected &&
          _transport == transport) {
        microphone = enabled;
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error = '無法操作麥克風，請確認系統麥克風權限後再試';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        microphoneBusy = false;
        _notify();
      }
    }
  }

  Future<void> leave() async {
    if (_disposed) return;
    ++_generation;
    status = VoiceStatus.offline;
    microphone = microphoneBusy = false;
    speakers = {};
    connections = participants = 0;
    error = null;
    _notify();
    await _detach();
  }

  Future<void> _detach() async {
    final subscription = _subscription;
    final transport = _transport;
    _subscription = null;
    _transport = null;
    final cancelled = subscription?.cancel();
    try {
      await transport?.close();
    } catch (_) {/* Already disconnected. */}
    await cancelled;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_detach());
    super.dispose();
  }
}
