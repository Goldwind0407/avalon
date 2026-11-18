import 'package:material_ui/material_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/sound_controls.dart';
import '../../core/game_sounds.dart';
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
                              _ModeCard(
                                key: const ValueKey('openLocal'),
                                icon: Icons.phone_iphone,
                                title: '一機遊玩',
                                subtitle: '一支手機輪流傳，面對面開局',
                                primary: true,
                                onTap: () =>
                                    _open(context, const LocalPlayScreen()),
                              ),
                              const SizedBox(height: 10),
                              _ModeCard(
                                key: const ValueKey('openOnline'),
                                icon: Icons.devices,
                                title: '多機遊玩',
                                subtitle: '每人一支手機，加入同一個房間',
                                onTap: () =>
                                    _open(context, const OnlinePlayScreen()),
                              ),
                              const SizedBox(height: 10),
                              _ModeCard(
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
                                child: TextButton.icon(
                                  key: const ValueKey('openRules'),
                                  onPressed: () {
                                    GameSounds.instance.play(GameSound.tap);
                                    RulesScreen.open(context);
                                  },
                                  icon: const Icon(Icons.menu_book_outlined,
                                      size: 18),
                                  label: const Text('遊戲規則・新手教學'),
                                ),
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

/// One way to play: an icon in a ring, a name and what it means.
class _ModeCard extends StatelessWidget {
  const _ModeCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.primary = false,
      this.badge});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool primary;
  final String? badge;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: primary
                    ? [const Color(0xFF3A3156), const Color(0xFF232348)]
                    : [const Color(0xFF222746), const Color(0xFF181D38)]),
            border: Border.all(
                color: AvalonTheme.gold.withValues(alpha: primary ? .7 : .28),
                width: primary ? 1.3 : 1),
            boxShadow: [
              if (primary)
                BoxShadow(
                    color: AvalonTheme.gold.withValues(alpha: .14),
                    blurRadius: 18),
              const BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 12,
                  offset: Offset(0, 6)),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: primary
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFF1D594), Color(0xFFC9A257)])
                        : null,
                    color: primary ? null : AvalonTheme.raised,
                    border: Border.all(
                        color: AvalonTheme.gold.withValues(alpha: .5)),
                  ),
                  child: Icon(icon,
                      size: 21,
                      color: primary ? AvalonTheme.bg : AvalonTheme.gold),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(title,
                              style: TextStyle(
                                  fontSize: 16.5,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.bold,
                                  color: primary
                                      ? AvalonTheme.gold
                                      : Colors.white)),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AvalonTheme.violet
                                          .withValues(alpha: .8))),
                              child: Text(badge!,
                                  style: const TextStyle(
                                      fontSize: 10, color: Color(0xFFB9AEF0))),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: const TextStyle(
                                fontSize: 12, color: AvalonTheme.muted)),
                      ]),
                ),
                Icon(Icons.chevron_right,
                    color: AvalonTheme.gold.withValues(alpha: .7)),
              ]),
            ),
          ),
        ),
      );
}
