import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/solo/voice_lines.dart';

/// Plays a computer player's line in their own voice, joined from the
/// recorded pieces in `assets/voice/<persona>/` (see voice_lines.dart). A
/// line with any piece not recorded yet is not spoken at all: it is read
/// on screen as before.
class BotVoices extends ChangeNotifier with WidgetsBindingObserver {
  BotVoices({AssetBundle? bundle, this.persist = true})
      : _bundle = bundle ?? rootBundle;
  static final instance = BotVoices();
  final AssetBundle _bundle;
  final bool persist;

  bool enabled = true;
  double volume = .9;
  bool _foreground = true, _disposed = false;
  Future<Set<String>>? _recorded;
  AudioPlayer? _player;
  int _line = 0;

  /// The pieces of each voice that have a recording.
  Future<Set<String>> get recorded => _recorded ??= _list();

  Future<Set<String>> _list() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
      return {
        for (final asset in manifest.listAssets())
          if (asset.startsWith('assets/voice/') && asset.endsWith('.mp3')) asset
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> initialize() async {
    if (_disposed) return;
    WidgetsBinding.instance.addObserver(this);
    if (!persist) return;
    try {
      final preferences = SharedPreferencesAsync();
      enabled = await preferences.getBool('avalon.voice.enabled') ?? true;
      volume = (await preferences.getDouble('avalon.voice.volume') ?? .9)
          .clamp(0, 1);
    } catch (_) {/* Voices still work without saved settings. */}
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    if (!value) await stop();
    notifyListeners();
    if (persist) {
      try {
        await SharedPreferencesAsync().setBool('avalon.voice.enabled', value);
      } catch (_) {}
    }
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0, 1);
    unawaited(_player?.setVolume(volume));
    notifyListeners();
    if (persist) {
      try {
        await SharedPreferencesAsync().setDouble('avalon.voice.volume', volume);
      } catch (_) {}
    }
  }

  /// The recordings [line] is said with in [persona]'s voice; null when one
  /// of them is missing (or the line has no words to say).
  Future<List<(String, int)>?> recordingsFor(
      String persona, String line) async {
    final pieces = voicePieces(line);
    if (pieces.isEmpty) return null;
    final have = await recorded;
    final assets = [
      for (final piece in pieces) (voiceAsset(persona, piece), piece.pause)
    ];
    return assets.every((a) => have.contains(a.$1)) ? assets : null;
  }

  /// Lines the computers often say, for trying the voices out.
  static const samples = [
    '現在講什麼都是猜，先出任務。',
    '我沒特別想法，這隊可以。',
    '第一隊大家都是白的，讓它走吧。',
    '過吧，回來再聊。',
    '3號第1次出失敗時在隊上，這次我反對。',
  ];

  /// Plays one of [samples] in the first voice that has it all recorded,
  /// starting after [after] (the persona tried last); returns who spoke,
  /// or null when no voice has a whole sample yet.
  Future<String?> trySample({String? after}) async {
    const order = [
      'chen',
      'yu',
      'pei',
      'zhe',
      'mia',
      'kai',
      'rong',
      'wei',
      'hu'
    ];
    final start = after == null ? 0 : order.indexOf(after) + 1;
    for (var i = 0; i < order.length; i++) {
      final persona = order[(start + i) % order.length];
      for (final line in samples) {
        if (await recordingsFor(persona, line) != null) {
          unawaited(speak(persona, line));
          return persona;
        }
      }
    }
    return null;
  }

  /// The silence recorded for a pause of [ms] milliseconds (voice_lines.dart
  /// uses 180 and 350).
  static String _silence(int ms) =>
      'assets/voice/pause${ms >= 300 ? 350 : 180}.mp3';

  /// Says [line] in [persona]'s voice, cutting off whatever was being said.
  Future<void> speak(String? persona, String line) async {
    final turn = ++_line;
    if (persona == null || !enabled || volume == 0 || !_foreground) return;
    final assets = await recordingsFor(persona, line);
    if (assets == null || turn != _line || _disposed) return;
    try {
      // Never take the audio session: online, people are talking over WebRTC.
      final player =
          _player ??= AudioPlayer(handleAudioSessionActivation: false);
      await player.setVolume(volume);
      // the whole line at once, played back to back; the pauses at the
      // punctuation are short silent recordings of their own
      await player.setAudioSources([
        for (final (asset, pause) in assets) ...[
          AudioSource.asset(asset),
          if (pause > 0) AudioSource.asset(_silence(pause)),
        ]
      ]);
      if (turn != _line || _disposed) return;
      await player.play();
      await player.processingStateStream
          .firstWhere((s) => s == ProcessingState.completed);
      await player.stop();
    } catch (_) {/* A voice that cannot play must never hold up the game. */}
  }

  Future<void> stop() async {
    ++_line;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(stop());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_player?.dispose());
    super.dispose();
  }
}
