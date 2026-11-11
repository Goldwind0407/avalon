import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../online/online_play_screen.dart';
import 'local_play_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openLocalPlay(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LocalPlayScreen()),
      );

  void _showMultiplayer(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OnlinePlayScreen()),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: FantasyBackground(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 320,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('AVALON',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 44,
                                letterSpacing: 9,
                                color: AvalonTheme.gold,
                                fontWeight: FontWeight.w700)),
                        const Text('阿 瓦 隆',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 22,
                                color: Colors.white,
                                letterSpacing: 6)),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: () => _openLocalPlay(context),
                          icon: const Icon(Icons.phone_iphone),
                          label: const Text('一機遊玩'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _showMultiplayer(context),
                          icon: const Icon(Icons.devices),
                          label: const Text('多機遊玩'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
