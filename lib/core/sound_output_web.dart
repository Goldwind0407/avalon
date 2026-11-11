import 'dart:js_interop';
import 'package:web/web.dart' as web;

class SoundOutput {
  final _playing = <web.HTMLAudioElement>[];
  Future<void> play(String name, double volume, bool important) async {
    if (important) await stop();
    while (_playing.length >= 3) {
      _playing.removeAt(0).pause();
    }
    final player = web.HTMLAudioElement()
      ..src = Uri.base.resolve('assets/assets/audio/$name.wav').toString()
      ..volume = volume;
    _playing.add(player);
    player.onended = ((web.Event _) {
      _playing.remove(player);
    }).toJS;
    try {
      await player.play().toDart;
    } catch (_) {
      _playing.remove(player); /* Browser awaits a user gesture. */
    }
  }

  Future<void> stop() async {
    for (final player in _playing) {
      player.pause();
    }
    _playing.clear();
  }
}
