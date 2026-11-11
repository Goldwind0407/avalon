import 'package:flutter/services.dart';

/// Does not take audio focus or reconfigure the WebRTC audio session.
class SoundOutput {
  static const channel = MethodChannel('avalon/sound_effects');
  Future<void> play(String name, double volume, bool important) async {
    await channel.invokeMethod<void>('play', {
      'name': name,
      'volume': volume,
      'important': important,
    });
  }

  Future<void> stop() async {
    await channel.invokeMethod<void>('stop');
  }
}
