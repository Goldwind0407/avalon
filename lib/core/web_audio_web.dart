import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'perf_stage.dart';

/// The audio elements the web build plays through.
///
/// Safari on the iPhone lets a page start a sound only from the player's
/// own tap; an element that has once been played that way may play again
/// later on its own. So these few elements are made at start-up, played
/// silent on the first touch (unlocking them), and used for every sound
/// after that: the computers' lines, which start when they speak, not when
/// anyone taps, and the table's sounds.
class WebAudio {
  WebAudio._();
  static final instance = WebAudio._();

  /// For the computers' lines.
  final voice = web.HTMLAudioElement()..preload = 'auto';

  /// For the table's sounds, taken in turn (a few may sound at once).
  final effects =
      List.generate(4, (_) => web.HTMLAudioElement()..preload = 'auto');
  var _nextEffect = 0;

  bool _armed = false, unlocked = false, _waking = false;
  JSFunction? _listener;
  static const _events = ['pointerdown', 'touchend', 'keydown', 'click'];

  /// A recording of silence, played to unlock each element.
  static String get _silence =>
      Uri.base.resolve('assets/assets/voice/pause180.mp3').toString();

  /// Readies the elements to be unlocked by the player's first touch.
  void arm() {
    if (_armed) return;
    _armed = true;
    _listener = ((web.Event _) => _unlock()).toJS;
    for (final type in _events) {
      web.document.addEventListener(type, _listener, true.toJS);
    }
  }

  /// Runs inside the touch itself (that is what makes it count).
  void _unlock() {
    if (unlocked) return;
    unlocked = true;
    _startContext();
    for (final type in _events) {
      web.document.removeEventListener(type, _listener, true.toJS);
    }
    // An iPhone stops the audio engine now and then (the app put away, a
    // call, another app's sound) and it may only start again from a
    // touch: every touch from now on wakes it if it has stopped.
    if (!_waking) {
      _waking = true;
      final wake = ((web.Event _) => _wake()).toJS;
      for (final type in const ['pointerdown', 'touchend']) {
        web.document.addEventListener(type, wake, true.toJS);
      }
    }
    for (final element in [voice, ...effects]) {
      element.src = _silence;
      element.play().toDart.then((_) {
        element.pause();
        element.currentTime = 0;
      }, onError: (_) {
        // not this time: try again on the next touch
        unlocked = false;
        arm();
      });
    }
  }

  /// The next element for a table sound.
  web.HTMLAudioElement nextEffect() {
    final element = effects[_nextEffect];
    _nextEffect = (_nextEffect + 1) % effects.length;
    return element;
  }

  // ── the table's sounds: decoded once, played at once ──
  //
  // A sound played through an element is fetched and decoded every time
  // (a tenth of a second and more on a phone: the card has landed before
  // it is heard), and only as many play together as there are elements.
  // Decoded ahead into the browser's audio engine they start at once, and
  // seven votes turning over are seven sounds.
  web.AudioContext? _context;
  final _buffers = <String, web.AudioBuffer>{};
  final _playing = <web.AudioBufferSourceNode>[];

  static String _effectUrl(String name) =>
      Uri.base.resolve('assets/assets/audio/$name.wav').toString();

  Future<void> preloadEffects(List<String> names) async {
    final web.AudioContext context;
    try {
      context = _context ??= web.AudioContext();
    } catch (_) {
      return; // no audio engine: the elements play instead
    }
    final pending = names.iterator;
    Future<void> load() async {
      while (pending.moveNext()) {
        final name = pending.current;
        try {
          final response = await web.window.fetch(_effectUrl(name).toJS).toDart;
          if (!response.ok) continue;
          final data = await response.arrayBuffer().toDart;
          _buffers[name] = await context.decodeAudioData(data).toDart;
        } catch (_) {/* that one plays through an element */}
      }
    }

    await Future.wait([load(), load()]);
  }

  /// Inside the first touch: the engine may only start from one.
  void _startContext() {
    // Sounds go on with the phone's ring switch off, like the voices
    // (Safari 16.4+; elsewhere this does nothing).
    try {
      final navigator = web.window.navigator as JSObject;
      if (navigator.has('audioSession')) {
        (navigator['audioSession'] as JSObject)['type'] = 'playback'.toJS;
      }
    } catch (_) {}
    final context = _context;
    if (context == null) return;
    try {
      context.resume();
      // one silent sample, played inside the touch
      final source = context.createBufferSource()
        ..buffer = context.createBuffer(1, 1, 22050);
      source.connect(context.destination);
      source.start();
    } catch (_) {}
  }

  void _wake() {
    final context = _context;
    if (context == null || context.state == 'running') return;
    _startContext();
  }

  /// Plays a decoded sound in the audio engine. Never through an element
  /// once the sound is decoded: on an iPhone an element given a new sound
  /// stops the whole page for about a second (the stamp, the shuffle, every
  /// turned card), so a stopped engine is woken and the sound waits for it
  /// (or is left out) instead.
  bool playEffect(String name, double volume) {
    final context = _context, buffer = _buffers[name];
    if (context == null || buffer == null) return false;
    if (context.state != 'running') {
      perfNote('sfxWait:${context.state}');
      final asked = DateTime.now();
      context.resume().toDart.then((_) {
        // a sound late by more than a moment would no longer fit the table
        if (context.state == 'running' &&
            DateTime.now().difference(asked).inMilliseconds < 400) {
          _start(context, buffer, volume);
        }
      }, onError: (_) {});
      return true;
    }
    return _start(context, buffer, volume);
  }

  bool _start(web.AudioContext context, web.AudioBuffer buffer, double volume) {
    try {
      final gain = context.createGain()..gain.value = volume.clamp(0, 1);
      final source = context.createBufferSource()..buffer = buffer;
      source.connect(gain);
      gain.connect(context.destination);
      _playing.add(source);
      source.onended = ((web.Event _) => _playing.remove(source)).toJS;
      source.start();
      return true;
    } catch (_) {
      return false;
    }
  }

  void stopEffects() {
    for (final source in _playing) {
      try {
        source.stop();
      } catch (_) {}
    }
    _playing.clear();
  }

  web.AbortController? _voiceFetch;
  String? _voiceUrl;
  Completer<bool>? _voiceDone;

  /// Plays the files at [urls] back to back as one sound (the pieces are
  /// MP3s of one format, so joined they play as one file, without gaps
  /// between pieces); completes when it has ended or been cut off, with
  /// false when it could not be played.
  Future<bool> playVoice(List<String> urls, double volume) async {
    stopVoice();
    final done = _voiceDone = Completer<bool>();
    final fetch = _voiceFetch = web.AbortController();
    try {
      final parts = await Future.wait([
        for (final url in urls)
          web.window
              .fetch(url.toJS, web.RequestInit(signal: fetch.signal))
              .toDart
              .then((response) {
            if (!response.ok) throw StateError('voice ${response.status}');
            return response.arrayBuffer().toDart;
          })
      ]);
      if (!identical(_voiceDone, done)) return false;
      final blob = web.Blob(parts.map((p) => p as JSAny).toList().toJS,
          web.BlobPropertyBag(type: 'audio/mpeg'));
      // Decoded into the audio engine, like the table's sounds: an element
      // given a new recording (or cut off) stops an iPhone's page for a
      // moment. The element only while the engine is not running.
      final context = _context;
      if (context != null && context.state == 'running') {
        final data = await blob.arrayBuffer().toDart;
        if (!identical(_voiceDone, done)) return false;
        final buffer = await context.decodeAudioData(data).toDart;
        if (!identical(_voiceDone, done)) return false;
        final gain = _voiceGain = context.createGain()
          ..gain.value = volume.clamp(0, 1);
        final source = _voiceSource = context.createBufferSource()
          ..buffer = buffer;
        source.connect(gain);
        gain.connect(context.destination);
        source.onended = ((web.Event _) {
          if (!done.isCompleted) done.complete(true);
        }).toJS;
        source.start();
        final played = await done.future;
        if (identical(_voiceDone, done)) stopVoice();
        return played;
      }
      final url = _voiceUrl = web.URL.createObjectURL(blob);
      voice
        ..src = url
        ..volume = volume.clamp(0, 1);
      voice.onended = ((web.Event _) {
        if (!done.isCompleted) done.complete(true);
      }).toJS;
      voice.onerror = ((web.Event _) {
        if (!done.isCompleted) done.complete(false);
      }).toJS;
      final before = web.window.performance.now();
      final playing = voice.play().toDart;
      _timed('voicePlay', before);
      await playing;
    } catch (_) {
      if (!done.isCompleted) done.complete(false);
    }
    final played = await done.future;
    if (identical(_voiceDone, done)) stopVoice();
    return played;
  }

  web.AudioBufferSourceNode? _voiceSource;
  web.GainNode? _voiceGain;

  void setVoiceVolume(double volume) {
    voice.volume = volume.clamp(0, 1);
    _voiceGain?.gain.value = volume.clamp(0, 1);
  }

  void stopVoice() {
    _voiceFetch?.abort();
    _voiceFetch = null;
    final source = _voiceSource;
    if (source != null) {
      _voiceSource = null;
      _voiceGain = null;
      source.onended = null;
      try {
        source.stop();
      } catch (_) {}
    }
    voice.pause();
    final done = _voiceDone;
    if (done != null && !done.isCompleted) done.complete(false);
    _voiceDone = null;
    final url = _voiceUrl;
    if (url != null) {
      _voiceUrl = null;
      voice.onended = null;
      voice.onerror = null;
      final before = web.window.performance.now();
      voice.removeAttribute('src');
      voice.load();
      _timed('voiceLoad', before);
      web.URL.revokeObjectURL(url);
    }
  }

  /// A call into an audio element that held the page up is noted (the
  /// frame-rate report shows what came right before a stop).
  static void _timed(String what, double before) {
    final ms = web.window.performance.now() - before;
    if (ms >= 30) perfNote('$what:${ms.round()}');
  }
}
