import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'core/theme.dart';
import 'core/game_sounds.dart';
import 'core/bot_voices.dart';
import 'core/pwa_controls.dart';
import 'dev/perf_demo.dart';
import 'features/home/home_screen.dart';
import 'features/online/online_play_screen.dart';
import 'features/intro/intro_screen.dart';
import 'core/web_audio.dart';
import 'core/web_page.dart';
import 'core/web_perf.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // A phone's browser gives the drawing far less memory than an app gets:
    // fewer decoded pictures and drawing resources are kept around (they
    // are decoded and drawn at display size; what is gone is made again).
    PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20;
    unawaited(SystemChannels.skia
        .invokeMethod<void>('Skia.setResourceCacheMaxBytes', 96 << 20));
  }
  // The game is played in landscape only, full screen like a real table.
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  // web: the first touch unlocks the sounds (Safari on the iPhone)
  WebAudio.instance.arm();
  unawaited(WebAudio.instance
      .preloadEffects([for (final sound in GameSound.values) sound.name]));
  await GameSounds.instance.initialize();
  await BotVoices.instance.initialize();
  runApp(AvalonApp(intro: !hasOfflineControls));
  // web: the frame-rate watcher (reports to perfReport, lightens the table
  // when too slow, offers a reload when the screen stops) is off since the
  // stalls were found (sounds through audio elements); turned on for one
  // device with ?perf in the address, or the flag avalon.perf
  if (kIsWeb &&
      (Uri.base.queryParameters.containsKey('perf') ||
          readFlag('avalon.perf'))) {
    watchFrameRate();
  }
}

class AvalonApp extends StatelessWidget {
  const AvalonApp({super.key, this.intro = true});

  /// Play the opening animation before the home screen.
  final bool intro;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Avalon · 阿瓦隆',
        debugShowCheckedModeBanner: false,
        builder: kIsWeb
            ? (context, child) => ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: SafeArea(child: child!),
                )
            : null,
        theme: hasOfflineControls
            ? AvalonTheme.dark.copyWith(
                textTheme: AvalonTheme.dark.textTheme
                    .apply(fontFamilyFallback: const ['Noto Sans TC']),
                primaryTextTheme: AvalonTheme.dark.primaryTextTheme
                    .apply(fontFamilyFallback: const ['Noto Sans TC']))
            : AvalonTheme.dark,
        // the sign-in page (web/login/) comes back to `#/online`
        routes: {'/online': (_) => const OnlinePlayScreen()},
        home: perfDemoRequested
            ? const PerfDemo()
            : intro
                ? IntroScreen(next: (_) => const HomeScreen())
                : const HomeScreen(),
      );
}
