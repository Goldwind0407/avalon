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
      _subscription = transport.updates.listen((update) {
        if (_disposed || generation != _generation) return;
        status = update.status;
        microphone = update.microphone;
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
    final generation = _generation;
    final enabled = !microphone;
    microphoneBusy = true;
    error = null;
    _notify();
    try {
      final transport = _transport!;
      await transport.setMicrophoneEnabled(enabled);
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
