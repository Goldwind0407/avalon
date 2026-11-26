import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'perf_stage.dart';
import 'web_audio_web.dart';

class SoundOutput {
  final _playing = <web.HTMLAudioElement>[];
  Future<void> play(String name, double volume, bool important) async {
    if (important) await stop();
    // decoded ahead and played at once (see web_audio_web.dart); the
    // elements below only until the engine is ready
    if (WebAudio.instance.playEffect(name, volume)) return;
    while (_playing.length >= 3) {
      _playing.removeAt(0).pause();
    }
    // one of the elements the first touch unlocked (see web_audio_web.dart):
    // Safari on the iPhone does not let a new one sound on its own
    // (only until the sounds are decoded: see WebAudio.playEffect)
    perfNote('sfxElement');
    final player = WebAudio.instance.nextEffect()
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
    WebAudio.instance.stopEffects();
    for (final player in _playing) {
      player.pause();
    }
    _playing.clear();
  }
}
