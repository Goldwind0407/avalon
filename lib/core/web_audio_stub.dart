/// Audio elements the web build plays through (see web_audio_web.dart).
/// Elsewhere there is nothing to unlock and nothing is played here.
class WebAudio {
  WebAudio._();
  static final instance = WebAudio._();

  /// Readies the elements to be unlocked by the player's first touch.
  void arm() {}

  /// Plays the files at [urls] back to back as one sound; false when it
  /// could not be played (nothing to play, or not allowed).
  Future<bool> playVoice(List<String> urls, double volume) async => false;

  void stopVoice() {}

  void setVoiceVolume(double volume) {}

  /// Decodes the table's sounds ahead, so they can sound at once.
  Future<void> preloadEffects(List<String> names) async {}

  /// Plays a decoded table sound; false when it is not ready to.
  bool playEffect(String name, double volume) => false;

  void stopEffects() {}
}
