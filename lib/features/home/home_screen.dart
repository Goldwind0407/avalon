import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/sound_controls.dart';
import '../../core/game_sounds.dart';
import '../online/online_play_screen.dart';
import 'local_play_screen.dart';
import '../rules/rules_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openLocalPlay(BuildContext context) {
    GameSounds.instance.play(GameSound.tap);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LocalPlayScreen()),
    );
  }

  void _showMultiplayer(BuildContext context) {
    GameSounds.instance.play(GameSound.tap);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OnlinePlayScreen()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: const SoundSettingsButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
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
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const ValueKey('openSolo'),
                          onPressed: () {
                            GameSounds.instance.play(GameSound.tap);
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const LocalPlayScreen(solo: true)));
                          },
                          icon: const Icon(Icons.smart_toy_outlined),
                          label: const Text('跟電腦遊玩（測試中）'),
                        ),
                        const SizedBox(height: 4),
                        TextButton.icon(
                          key: const ValueKey('openRules'),
                          onPressed: () {
                            GameSounds.instance.play(GameSound.tap);
                            RulesScreen.open(context);
                          },
                          icon: const Icon(Icons.menu_book_outlined, size: 18),
                          label: const Text('遊戲規則・新手教學'),
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
