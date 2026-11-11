import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme.dart';
import 'features/home/home_screen.dart';
import 'features/intro/intro_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The game is played in landscape only, full screen like a real table.
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const AvalonApp());
}

class AvalonApp extends StatelessWidget {
  const AvalonApp({super.key, this.intro = true});

  /// Play the opening animation before the home screen.
  final bool intro;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Avalon · 阿瓦隆',
        debugShowCheckedModeBanner: false,
        theme: AvalonTheme.dark,
        home: intro
            ? IntroScreen(next: (_) => const HomeScreen())
            : const HomeScreen(),
      );
}
