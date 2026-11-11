import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme.dart';
import 'features/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The game is played in landscape only, full screen like a real table.
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const AvalonApp());
}

class AvalonApp extends StatelessWidget {
  const AvalonApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Avalon · 阿瓦隆',
        debugShowCheckedModeBanner: false,
        theme: AvalonTheme.dark,
        home: const HomeScreen(),
      );
}
