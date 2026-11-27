import 'package:material_ui/material_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/sound_controls.dart';
import '../../core/game_sounds.dart';
import '../../core/pwa_controls.dart';
import '../online/online_play_screen.dart';
import 'local_play_screen.dart';
import '../rules/rules_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const emblem = 'assets/images/brand/emblem.webp';

  void _open(BuildContext context, Widget screen) {
    GameSounds.instance.play(GameSound.tap);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: const SoundSettingsButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
        body: FantasyBackground(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 720,
                    height: 340,
                    child: Row(children: [
                      const Expanded(flex: 5, child: _Crest()),
                      const SizedBox(width: 28),
                      Expanded(
                        flex: 6,
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ModeCard(
                                key: const ValueKey('openLocal'),
                                icon: Icons.phone_iphone,
                                title: '一機遊玩',
                                subtitle: '一支手機輪流傳，面對面開局',
                                primary: true,
                                onTap: () =>
                                    _open(context, const LocalPlayScreen()),
                              ),
                              const SizedBox(height: 10),
                              ModeCard(
                                key: const ValueKey('openOnline'),
                                icon: Icons.devices,
                                title: '多機遊玩',
                                subtitle: '每人一支手機，加入同一個房間（需要網路）',
                                onTap: () =>
                                    _open(context, const OnlinePlayScreen()),
                              ),
                              const SizedBox(height: 10),
                              ModeCard(
                                key: const ValueKey('openSolo'),
                                icon: Icons.smart_toy_outlined,
                                title: '跟電腦遊玩',
                                subtitle: '和九位固定的電腦玩家對戰',
                                badge: '測試中',
                                onTap: () => _open(
                                    context, const LocalPlayScreen(solo: true)),
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: Wrap(
                                    alignment: WrapAlignment.center,
                                    children: [
                                      TextButton.icon(
                                        key: const ValueKey('openRules'),
                                        onPressed: () {
                                          GameSounds.instance
                                              .play(GameSound.tap);
                                          RulesScreen.open(context);
                                        },
                                        icon: const Icon(
                                            Icons.menu_book_outlined,
                                            size: 18),
                                        label: const Text('遊戲規則・新手教學'),
                                      ),
                                      if (hasOfflineControls)
                                        TextButton.icon(
                                          onPressed: openOfflineControls,
                                          icon: const Icon(
                                              Icons.download_outlined,
                                              size: 18),
                                          label: const Text('離線遊玩'),
                                        )
                                    ]),
                              ),
                            ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// The emblem with the name under it.
class _Crest extends StatelessWidget {
  const _Crest();
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 210,
          height: 210,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(38),
            border: Border.all(color: AvalonTheme.gold.withValues(alpha: .45)),
            boxShadow: [
              BoxShadow(
                  color: AvalonTheme.gold.withValues(alpha: .16),
                  blurRadius: 40,
                  spreadRadius: 2),
              const BoxShadow(
                  color: Color(0x88000000),
                  blurRadius: 24,
                  offset: Offset(0, 12)),
            ],
          ),
          child: ClipRRect(
              borderRadius: BorderRadius.circular(37),
              child: Image.asset(HomeScreen.emblem,
                  key: const ValueKey('homeEmblem'),
                  scale: 1,
                  cacheWidth:
                      (210 * MediaQuery.devicePixelRatioOf(context)).ceil(),
                  fit: BoxFit.cover,
                  semanticLabel: 'AVALON 阿瓦隆')),
        ),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _rule(true),
          const SizedBox(width: 12),
          const GoldDiamond(),
          const SizedBox(width: 12),
          const Text('阿 瓦 隆',
              style: TextStyle(
                  fontSize: 22,
                  letterSpacing: 6,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          const GoldDiamond(),
          const SizedBox(width: 12),
          _rule(false),
        ]),
        const SizedBox(height: 6),
        const Text('正義與邪惡，在圓桌上一決勝負',
            style: TextStyle(
                fontSize: 12, letterSpacing: 1.5, color: AvalonTheme.muted)),
      ]);

  /// A thin gold line fading out away from the name.
  Widget _rule(bool left) => Container(
      width: 38,
      height: 1,
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
        AvalonTheme.gold.withValues(alpha: left ? 0 : .7),
        AvalonTheme.gold.withValues(alpha: left ? .7 : 0),
      ])));
}
