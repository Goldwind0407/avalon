import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:ui' show FramePhase, FrameTiming, PlatformDispatcher;
import 'package:flutter/foundation.dart' show FlutterError, kIsWasm;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:web/web.dart' as web;
import 'effects.dart';
import 'perf_stage.dart';
import 'web_page.dart';

/// Where the frame-rate summaries go (functions/src/index.ts: perfReport),
/// so how the game runs on friends' phones can be read without asking them.
const _reportUrl =
    'https://asia-east1-avalon-shadow-council.cloudfunctions.net/perfReport';

/// Every effect is given up when, after the start-up, this many seconds in
/// a row averaged fewer frames than [_slowFps] (60 is smooth; below 40 the
/// cards and seats are seen to stutter).
const _slowSeconds = 6, _slowFps = 40.0;
const _warmUp = Duration(seconds: 15);

/// Watches how smoothly the browser draws, the whole time the game is open:
/// switches to the light table when every effect is too much for this
/// device (and starts with it next time; a Safari that ran the WebAssembly
/// build tries the lighter JavaScript one), and sends a summary now and
/// then. Nothing about the player is in it.
void watchFrameRate() => _Watcher()..start();

class _Watcher {
  final _started = DateTime.now();
  double _last = 0, _secondFrom = 0;
  int _secondFrames = 0;
  final _recentFps = <double>[];

  // since the last report
  int _frames = 0, _late = 0, _slowSecondsSeen = 0;
  double _drawn = 0, _worst = 0;
  final _gaps = <double>[];
  // the same, step by step (perf_stage.dart): [frames, ms drawn, late, stalls]
  final _stages = <String, List<double>>{};
  // the longest stops, with where they happened and what came just before
  final _stalls = <({String stage, double ms, List<String> before})>[];
  // stops by length: at least 50, 100, 250, 500 and 1000 ms
  static const _overs = [50, 100, 250, 500, 1000];
  final _over = List.filled(_overs.length, 0);
  // what happened lately (perf_stage.dart: perfNote; files fetched)
  final _notes = <({double at, String what})>[];
  bool _gaveUp = false, _reportedGivingUp = false;

  // Frames the game built, and when the last of them reached the screen.
  // The drawing is done on its own thread (or after the build, at least):
  // frames still built while none is drawn for seconds is a screen stuck
  // on its last picture, though the game goes on behind it.
  int _built = 0, _builtWhenDrawn = 0;
  double _drawnAt = 0, _builtAt = 0, _errorAt = 0;
  bool _frozen = false, _stillTold = false;
  // errors since the last report, as `err:what@s` (seconds since the start)
  final _errors = <String>[];

  void _note(String what, [double? at]) {
    _notes.add((at: at ?? web.window.performance.now(), what: what));
    if (_notes.length > 40) _notes.removeAt(0);
  }

  /// Short enough, and plain enough, for a note in a report.
  static String _plain(String text, int max) {
    final plain = text
        .replaceAll(RegExp(r'[^\w:.\-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return plain.length > max ? plain.substring(0, max) : plain;
  }

  void _error(String text, [double? at]) {
    final what = 'err:${_plain(text, 32)}';
    final when = at ?? web.window.performance.now();
    _note(what, when);
    _errorAt = max(_errorAt, when);
    if (_errors.length < 6) _errors.add('$what@${(when / 1000).round()}');
  }

  /// The errors web/pwa.js kept (the browser's, the drawing thread's).
  void _takePageErrors() {
    try {
      final list = globalContext['avalonErrors'] as JSArray<JSArray>?;
      final errors = list?.toDart ?? const <JSArray>[];
      if (errors.isEmpty) return;
      for (final e in errors) {
        final pair = e.toDart;
        _error(
            (pair[1] as JSString).toDart, (pair[0] as JSNumber).toDartDouble);
      }
      list!.setProperty('length'.toJS, 0.toJS);
    } catch (_) {}
  }

  /// Each frame as drawn: how long the game took to build it, and the
  /// drawing; a slow one of either is noted (a stop shows which it was).
  void _timings(List<FrameTiming> timings) {
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds / 1000,
          raster = t.rasterDuration.inMicroseconds / 1000;
      if (build >= 50) {
        _note('build:${build.round()}',
            t.timestampInMicroseconds(FramePhase.buildStart) / 1000);
      }
      if (raster >= 50) {
        _note('raster:${raster.round()}',
            t.timestampInMicroseconds(FramePhase.rasterStart) / 1000);
      }
    }
    _drawnAt = web.window.performance.now();
    _builtWhenDrawn = _built;
  }

  /// The screen has stopped when, for three seconds, the game built frames
  /// none of which was drawn ('undrawn'); or wanted a frame and built none
  /// ('unbuilt'); or built none since an error while something was moving
  /// ('crashed'). The player is
  /// offered a reload (web/pwa.js), and a report goes at once.
  void _checkFrozen(double now) {
    // starting up, a first frame can take seconds: not a stop
    if (DateTime.now().difference(_started) < _warmUp) return;
    // the page's own table (web/table/) is drawn without the app
    if (perfPageTable && !_frozen) return;
    if (_frozen) {
      if (now - _builtAt < 1000 && now - _drawnAt < 1000) {
        _frozen = false;
        _note('thawed', now);
        _showFrozen(false);
      }
      return;
    }
    final binding = SchedulerBinding.instance;
    final since = now - _builtAt;
    final why =
        // still building (the last frames' timings wait for a later frame
        // to be sent with it: a screen come to rest is not one undrawn)
        _drawnAt > 0 &&
                _built - _builtWhenDrawn >= 3 &&
                now - _drawnAt >= 3000 &&
                since < 1000
            ? 'undrawn'
            : _builtAt > 0 &&
                    since >= 3000 &&
                    (binding.hasScheduledFrame ||
                        binding.schedulerPhase != SchedulerPhase.idle)
                ? 'unbuilt'
                // an error, then nothing built though something on screen
                // is moving (a screen at rest, like the menu, builds none)
                : _builtAt > 0 &&
                        since >= 3000 &&
                        _errorAt > _builtAt &&
                        binding.transientCallbackCount > 0
                    ? 'crashed'
                    : null;
    if (why == null) {
      _checkStill(now, since);
      return;
    }
    _frozen = true;
    final from = why == 'undrawn' ? _drawnAt : _builtAt;
    _note('frozen:$why', now);
    _stalls.add((stage: perfStage, ms: now - from, before: _before(from, now)));
    _keepLongestStalls();
    _report(always: true);
    _showFrozen(true);
  }

  /// At the table with every effect something always moves: nothing built
  /// for eight seconds is told (only told: the game may stand paused).
  void _checkStill(double now, double since) {
    if (since < 1000) _stillTold = false;
    if (_stillTold ||
        _builtAt == 0 ||
        since < 8000 ||
        perfStage == 'menu' ||
        perfPageTable ||
        lightEffects) {
      return;
    }
    _stillTold = true;
    _note('still', now);
    _stalls.add((stage: perfStage, ms: since, before: _before(_builtAt, now)));
    _keepLongestStalls();
    _report(always: true);
  }

  static void _showFrozen(bool frozen) {
    try {
      globalContext.callMethod('avalonFrozen'.toJS, frozen.toJS);
    } catch (_) {/* not the PWA page (web/pwa.js) */}
  }

  void start() {
    perfNoteSink = _note;
    SchedulerBinding.instance
      ..addTimingsCallback(_timings)
      ..addPersistentFrameCallback((_) {
        _built++;
        _builtAt = web.window.performance.now();
      });
    final flutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      _error('${details.exception}');
      flutterError?.call(details);
    };
    final platformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _error('$error');
      return platformError?.call(error, stack) ?? false;
    };
    try {
      web.PerformanceObserver(((web.PerformanceObserverEntryList list,
              web.PerformanceObserver _) {
        for (final entry in list.getEntries().toDart) {
          final name = entry.name
              .split('?')
              .first
              .split('/')
              .last
              .replaceAll(RegExp(r'[^\w.\-]'), '_');
          _note('net:${name.length > 32 ? name.substring(0, 32) : name}',
              (entry as web.PerformanceResourceTiming).responseEnd);
        }
      }).toJS)
          .observe(web.PerformanceObserverInit(type: 'resource'));
    } catch (_) {/* only notes */}
    web.window.requestAnimationFrame(_frame.toJS);
    Timer.periodic(const Duration(minutes: 2), (_) => _report());
    // closing the game, or putting it away, sends what was seen so far
    web.document.addEventListener(
        'visibilitychange',
        ((web.Event _) {
          _note(web.document.hidden ? 'hidden' : 'visible');
          if (web.document.hidden) _report();
        }).toJS);
  }

  void _frame(double now) {
    web.window.requestAnimationFrame(_frame.toJS);
    // a page in the background draws nothing: that is not slowness
    if (web.document.hidden) {
      _last = 0;
      return;
    }
    if (_last > 0) {
      final gap = now - _last;
      // a stop of the screen, up to a few seconds (longer: put away)
      if (gap >= 100 && gap < 5000) _stalled(gap, now);
      if (gap < 5000) {
        for (var i = 0; i < _overs.length; i++) {
          if (gap >= _overs[i]) _over[i]++;
        }
      }
      if (gap < 1000) {
        _frames++;
        _drawn += gap;
        _gaps.add(gap);
        if (gap > 25) _late++;
        _worst = max(_worst, gap);
        final step = _stages.putIfAbsent(perfStage, () => [0, 0, 0, 0]);
        step[0]++;
        step[1] += gap;
        if (gap > 25) step[2]++;
        // a tenth of a second and more: a stop, not just a slow frame
        if (gap >= 100) step[3]++;
      }
    } else {
      _secondFrom = now;
      // back on screen: the drawing is given its time again
      if (_drawnAt > 0) {
        _drawnAt = now;
        _builtWhenDrawn = _built;
      }
      if (_builtAt > 0) _builtAt = now;
    }
    _last = now;
    _secondFrames++;
    if (now - _secondFrom >= 1000) {
      _takePageErrors();
      _checkFrozen(now);
      _second(_secondFrames * 1000 / (now - _secondFrom));
      _secondFrom = now;
      _secondFrames = 0;
    }
  }

  void _stalled(double gap, double now) {
    final stage = perfStage, from = now - gap;
    // the stopped frame's own timings come a moment later
    Timer(const Duration(milliseconds: 400), () {
      _takePageErrors();
      _stalls.add((stage: stage, ms: gap, before: _before(from, now)));
      _keepLongestStalls();
    });
  }

  /// What happened from shortly before [from] to [now], as `what@ms` from
  /// [from]: the last six, keeping any timing or error among them.
  List<String> _before(double from, double now) {
    final near = [
      for (final n in _notes)
        if (n.at >= from - 600 && n.at <= now) n
    ]..sort((a, b) => a.at.compareTo(b.at));
    bool telling(String what) =>
        what.startsWith('build:') ||
        what.startsWith('raster:') ||
        what.startsWith('err:') ||
        what.startsWith('frozen') ||
        what == 'still';
    final kept = near.where((n) => telling(n.what)).take(4).toList();
    final rest = near.where((n) => !telling(n.what)).toList();
    kept.addAll(rest.sublist(max(0, rest.length - (6 - kept.length))));
    kept.sort((a, b) => a.at.compareTo(b.at));
    return [for (final n in kept) '${n.what}@${(n.at - from).round()}'];
  }

  void _keepLongestStalls() {
    _stalls.sort((a, b) => b.ms.compareTo(a.ms));
    if (_stalls.length > 8) _stalls.removeLast();
  }

  void _second(double fps) {
    if (DateTime.now().difference(_started) < _warmUp) return;
    if (fps < _slowFps) _slowSecondsSeen++;
    _recentFps.add(fps);
    if (_recentFps.length > _slowSeconds) _recentFps.removeAt(0);
    if (!_gaveUp &&
        !lightEffects &&
        _recentFps.length == _slowSeconds &&
        _recentFps.every((f) => f < _slowFps)) {
      _gaveUp = true;
      useLightEffects();
      // a Safari that cannot keep up with the WebAssembly build is given
      // the JavaScript one from its next start (flutter_bootstrap.js)
      if (kIsWasm) writeFlag('avalon.noWasm', true);
      _report();
    }
  }

  void _report({bool always = false}) {
    // too little seen to say anything (but giving up is always told: a
    // device that slow draws few frames; and a screen that stopped)
    final least = always
        ? 1
        : _gaveUp && !_reportedGivingUp
            ? 10
            : 120;
    if (_frames < least) return;
    _gaps.sort();
    final summary = {
      'renderer': kIsWasm ? 'wasm' : 'js',
      'isolated': pageIsolated,
      'light': lightEffects,
      'gaveUp': _gaveUp && !_reportedGivingUp,
      'fps': _round(1000 * _frames / _drawn),
      'latePct': _round(100 * _late / _frames),
      'p95': _round(_gaps[(_gaps.length * .95).floor()]),
      'worst': _worst.round(),
      'slowSeconds': _slowSecondsSeen,
      'seconds': (_drawn / 1000).round(),
      'dpr': web.window.devicePixelRatio,
      'width': web.window.innerWidth,
      'height': web.window.innerHeight,
      'standalone': web.window.matchMedia('(display-mode: standalone)').matches,
      'ua': web.window.navigator.userAgent,
      'page': web.window.location.hash,
      'release': (globalContext['avalonRelease'] as JSString?)?.toDart,
      'stages': {
        for (final MapEntry(key: stage, value: s) in _stages.entries)
          if (s[0] >= 30 || s[3] > 0)
            stage: {
              'fps': _round(1000 * s[0] / s[1]),
              'latePct': _round(100 * s[2] / s[0]),
              'seconds': _round(s[1] / 1000),
              'stalls': s[3].round(),
            },
      },
      'over': {
        for (var i = 0; i < _overs.length; i++) '${_overs[i]}': _over[i],
      },
      'stalls': [
        for (final s in _stalls.take(_errors.isEmpty ? 8 : 7))
          {'stage': s.stage, 'ms': s.ms.round(), 'before': s.before},
        // errors, wherever they came: `err:what@s`, s from the start
        if (_errors.isNotEmpty)
          {
            'stage': 'errors',
            'ms': 0,
            'before': [..._errors]
          },
      ],
    };
    _reportedGivingUp = _reportedGivingUp || _gaveUp;
    _frames = _late = _slowSecondsSeen = 0;
    _drawn = _worst = 0;
    _gaps.clear();
    _stages.clear();
    _stalls.clear();
    _errors.clear();
    _over.fillRange(0, _over.length, 0);
    try {
      web.window.fetch(
          _reportUrl.toJS,
          web.RequestInit(
              method: 'POST',
              headers: {'Content-Type': 'application/json'}.jsify()
                  as web.HeadersInit,
              body: jsonEncode({'data': summary}).toJS,
              keepalive: true));
    } catch (_) {/* offline, or blocked: it is only a report */}
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(1));
}
