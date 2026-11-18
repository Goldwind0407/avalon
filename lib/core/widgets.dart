import 'dart:math';
import 'package:material_ui/material_ui.dart';
import 'theme.dart';

/// The night sky every menu screen sits on: a deep gradient, two soft
/// glows, a scatter of faint stars and a vignette at the edges.
class FantasyBackground extends StatelessWidget {
  const FantasyBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A2548), Color(0xFF11102A), AvalonTheme.bg]),
        ),
        child: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: _Stars())),
          Positioned(
              top: -120,
              right: -130,
              child: _Glow(
                  size: 340, color: AvalonTheme.violet.withValues(alpha: .2))),
          Positioned(
              bottom: -180,
              left: -140,
              child: _Glow(
                  size: 380, color: AvalonTheme.gold.withValues(alpha: .08))),
          // darker toward the edges, so the middle reads first
          const Positioned.fill(
              child: IgnorePointer(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: RadialGradient(
                              radius: 1.1,
                              colors: [Colors.transparent, Color(0x66050814)],
                              stops: [.55, 1]))))),
          child,
        ]),
      );
}

/// Faint stars, the same on every screen (a fixed seed).
class _Stars extends CustomPainter {
  const _Stars();
  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(7);
    final paint = Paint();
    for (var i = 0; i < 70; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = .5 + rng.nextDouble() * 1.1;
      paint.color =
          Colors.white.withValues(alpha: .08 + rng.nextDouble() * .22);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_Stars oldDelegate) => false;
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, Colors.transparent])),
      );
}

/// A framed panel: lighter at the top like lit stone, with a thin gold rim.
class GoldPanel extends StatelessWidget {
  const GoldPanel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF1D2443).withValues(alpha: .95),
                AvalonTheme.surface.withValues(alpha: .93),
              ]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AvalonTheme.gold.withValues(alpha: .3)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x55000000), blurRadius: 22, offset: Offset(0, 10))
          ],
        ),
        child: child,
      );
}

/// A small gold diamond, the ornament used before headings.
class GoldDiamond extends StatelessWidget {
  const GoldDiamond({super.key, this.size = 7});
  final double size;
  @override
  Widget build(BuildContext context) => Transform.rotate(
      angle: pi / 4,
      child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: AvalonTheme.gold, boxShadow: [
            BoxShadow(
                color: AvalonTheme.gold.withValues(alpha: .5), blurRadius: 6)
          ])));
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        const GoldDiamond(size: 6),
        const SizedBox(width: 9),
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  letterSpacing: 2.3,
                  color: AvalonTheme.gold,
                  fontWeight: FontWeight.bold)),
        ),
      ]);
}

/// A round, gold-rimmed icon button: back, history, settings.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton(
      {super.key,
      required this.icon,
      required this.tooltip,
      required this.onPressed,
      this.size = 38});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: AvalonTheme.raised.withValues(alpha: .75),
          shape: CircleBorder(
              side: BorderSide(color: AvalonTheme.gold.withValues(alpha: .35))),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon,
                    size: size * .5,
                    color: onPressed == null
                        ? AvalonTheme.muted
                        : AvalonTheme.gold)),
          ),
        ),
      );
}

/// The top of a menu screen: a round back button, the title, and an
/// optional line under it.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.title,
      {super.key,
      this.subtitle,
      this.onBack,
      this.backTooltip = '返回',
      this.backKey});
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final String backTooltip;
  final Key? backKey;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        RoundIconButton(
            key: backKey,
            icon: Icons.arrow_back,
            tooltip: backTooltip,
            onPressed: onBack ?? () => Navigator.pop(context)),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: AvalonTheme.gold)),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, color: AvalonTheme.muted)),
              ]),
        ),
      ]);
}

/// A small rounded setting chip: an icon and a short label.
class SettingChip extends StatelessWidget {
  const SettingChip(
      {super.key,
      required this.icon,
      required this.label,
      this.onTap,
      this.highlight = false,
      this.trailing,
      this.tooltip});
  final IconData icon;

  /// Empty: the icon alone (then [tooltip] says what it is).
  final String label;
  final VoidCallback? onTap;
  final bool highlight;
  final Widget? trailing;
  final String? tooltip;
  @override
  Widget build(BuildContext context) =>
      tooltip == null ? _chip() : Tooltip(message: tooltip!, child: _chip());

  Widget _chip() => Material(
        color: highlight
            ? AvalonTheme.violet.withValues(alpha: .32)
            : AvalonTheme.raised.withValues(alpha: .8),
        shape: StadiumBorder(
            side: BorderSide(
                color:
                    AvalonTheme.gold.withValues(alpha: highlight ? .45 : .18))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: AvalonTheme.gold),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(label,
                    style:
                        const TextStyle(fontSize: 12.5, color: Colors.white)),
              ],
              if (trailing != null) ...[const SizedBox(width: 2), trailing!],
            ]),
          ),
        ),
      );
}

/// One choice out of a few, as a row of joined pills (e.g. 5 to 10).
class PillSelector<T> extends StatelessWidget {
  const PillSelector(
      {super.key,
      required this.values,
      required this.selected,
      required this.onSelected,
      required this.label,
      this.keyOf});
  final List<T> values;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T) label;
  final Key Function(T)? keyOf;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: ShapeDecoration(
            color: AvalonTheme.raised.withValues(alpha: .8),
            shape: StadiumBorder(
                side: BorderSide(
                    color: AvalonTheme.gold.withValues(alpha: .18)))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final value in values)
            _Pill(
                key: keyOf?.call(value),
                label: label(value),
                active: value == selected,
                onTap: () => onSelected(value)),
        ]),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(
      {super.key,
      required this.label,
      required this.active,
      required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 34,
          height: 30,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              gradient: active
                  ? const LinearGradient(
                      colors: [Color(0xFFF1D594), AvalonTheme.gold])
                  : null,
              shadows: active
                  ? [
                      BoxShadow(
                          color: AvalonTheme.gold.withValues(alpha: .35),
                          blurRadius: 8)
                    ]
                  : null),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active ? AvalonTheme.bg : AvalonTheme.muted)),
        ),
      );
}

/// A large tappable choice: an icon in a circle, a title and a line under
/// it ([primary] stands out in gold). The home screen's modes, online
/// play's "create a room" and "back to your room".
class ModeCard extends StatelessWidget {
  const ModeCard(
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
