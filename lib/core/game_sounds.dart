import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sound_output.dart';

enum GameSound {
  tap,
  deal,
  flip,
  shuffle,
  token,
  seal,
  approve,
  reject,
  questStart,
  success,
  failure,
  turn,
  tick,
  freeDiscussion,
  assassin,
  goodWin,
  evilWin,
  magic,
  page;

  bool get important =>
      [approve, reject, success, failure, goodWin, evilWin].contains(this);
}

/// Short, local, non-looping effects. Secret choices always share neutral cues.
class GameSounds extends ChangeNotifier with WidgetsBindingObserver {
  GameSounds({SoundOutput? output}) : _output = output ?? SoundOutput();
  static final instance = GameSounds();
  final SoundOutput _output;
  bool enabled = true;
  double volume = .6;
  bool _ready = false, _foreground = true, _disposed = false;
  final _last = <GameSound, DateTime>{};
  Future<void> _writes = Future.value();
  SharedPreferencesAsync? _preferences;

  Future<void> initialize({bool persist = true}) async {
    if (_ready || _disposed) return;
    if (persist) {
      try {
        _preferences = SharedPreferencesAsync();
        enabled = await _preferences!.getBool('avalon.sound.enabled') ?? true;
        volume = (await _preferences!.getDouble('avalon.sound.volume') ?? .6)
            .clamp(0, 1);
      } catch (_) {/* Audio still works if preferences are unavailable. */}
    }
    if (_disposed) return;
    WidgetsBinding.instance.addObserver(this);
    _ready = true;
    notifyListeners();
  }

  void play(GameSound cue) {
    if (!_ready || _disposed || !enabled || volume == 0 || !_foreground) return;
    final now = DateTime.now();
    if (_last[cue] != null && now.difference(_last[cue]!).inMilliseconds < 85) {
      return;
    }
    _last[cue] = now;
    unawaited(_play(cue));
  }

  Future<void> _play(GameSound cue) async {
    try {
      await _output.play(
          cue.name, volume * (cue == GameSound.tick ? .45 : 1), cue.important);
    } catch (_) {/* Missing/unsupported output must never block a game move. */}
  }

  Future<void> stop() async {
    try {
      await _output.stop();
    } catch (_) {/* Already stopped. */}
  }

  void setEnabled(bool value) {
    enabled = value;
    if (!value) unawaited(stop());
    notifyListeners();
    _save();
  }

  void setVolume(double value) {
    volume = value.clamp(0, 1);
    if (volume == 0) unawaited(stop());
    notifyListeners();
    _save();
  }

  void _save() {
    final state = enabled, level = volume;
    _writes = _writes.then((_) async {
      try {
        await _preferences?.setBool('avalon.sound.enabled', state);
        await _preferences?.setDouble('avalon.sound.volume', level);
      } catch (_) {/* Keep settings for this session. */}
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(stop());
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ready) WidgetsBinding.instance.removeObserver(this);
    unawaited(stop());
    super.dispose();
  }
}
