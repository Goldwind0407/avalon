import 'package:flutter/material.dart';
import 'theme.dart';

class FantasyBackground extends StatelessWidget {
  const FantasyBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF192444), Color(0xFF11102A), AvalonTheme.bg]),
        ),
        child: Stack(children: [
          Positioned(
              top: -120,
              right: -130,
              child: _Glow(
                  size: 330, color: AvalonTheme.violet.withValues(alpha: .19))),
          Positioned(
              bottom: -180,
              left: -140,
              child: _Glow(
                  size: 360, color: AvalonTheme.gold.withValues(alpha: .07))),
          child,
        ]),
      );
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
          color: AvalonTheme.surface.withValues(alpha: .93),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AvalonTheme.gold.withValues(alpha: .35)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x44000000), blurRadius: 20, offset: Offset(0, 9))
          ],
        ),
        child: child,
      );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 13,
          letterSpacing: 2.3,
          color: AvalonTheme.gold,
          fontWeight: FontWeight.bold));
}
