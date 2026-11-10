import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme.dart';
import 'features/home/home_screen.dart';
import 'features/lobby/room_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The game is played in landscape only, full screen like a real table.
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const AvalonApp());
}

class AvalonApp extends StatefulWidget {
  const AvalonApp({super.key});
  @override
  State<AvalonApp> createState() => _AvalonAppState();
}

class _AvalonAppState extends State<AvalonApp> {
  final LocalRoomRepository _repository = LocalRoomRepository();
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Avalon · 暗影議會',
        debugShowCheckedModeBanner: false,
        theme: AvalonTheme.dark,
        home: HomeScreen(repository: _repository),
      );
}
