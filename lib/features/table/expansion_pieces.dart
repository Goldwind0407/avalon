import 'package:flutter/material.dart';
import '../../core/assets.dart';
import '../../core/theme.dart';
import 'components.dart';
import 'effects.dart';

/// A landscape card (the Lancelot loyalty cards are 3:2).
class WideCard extends StatelessWidget {
  const WideCard(this.asset,
      {super.key, required this.width, this.elevation = 4});
  final String asset;
  final double width;
  final double elevation;
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: width * cardAspect,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * cardAspect * .06),
          boxShadow: elevation <= 0
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .55),
                      blurRadius: elevation * 1.8,
                      offset: Offset(0, elevation * .7)),
                ],
        ),
        child: artImage(context, asset,
            width: width, height: width * cardAspect, fit: BoxFit.cover),
      );
}

/// Loyalty card art for a quest: switch, no change, or still face down.
String loyaltyArt(bool? card) => switch (card) {
      true => Assets.loyaltySwitch,
      false => Assets.loyaltyNoSwitch,
      null => Assets.loyaltyBack,
    };

/// The Lancelot loyalty cards lying by the quest board, one per quest.
class LoyaltyStrip extends StatelessWidget {
  const LoyaltyStrip(
      {super.key,
      required this.cards,
      required this.variant,
      required this.current,
      required this.switched,
      required this.scale});

  /// Card on each quest (null: none turned over yet).
  final List<bool?> cards;
  final int variant;

  /// Index of the quest being played (-1 when the game is over).
  final int current;
  final bool switched;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale, w = 34 * s;
    return Container(
      key: const ValueKey('loyaltyStrip'),
      padding: EdgeInsets.fromLTRB(6 * s, 4 * s, 6 * s, 5 * s),
      decoration: plaqueDecoration(radius: 8 * s),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(switched ? '蘭斯洛特・已轉換' : '蘭斯洛特',
            style: TextStyle(
                fontSize: 9.5 * s,
                color: switched ? const Color(0xFFFF9B8A) : AvalonTheme.gold)),
        SizedBox(height: 3 * s),
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 1.5 * s),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // variant 1 never turns a card over for quests 1 and 2
                Opacity(
                  opacity: variant == 1 && i < 2 ? .25 : 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: EdgeInsets.all(1.2 * s),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3 * s),
                      border: Border.all(
                          color: i == current
                              ? AvalonTheme.gold
                              : Colors.transparent,
                          width: 1.2 * s),
                    ),
                    child: FlipCard(
                      key: ValueKey('loyalty$i'),
                      faceUp: cards[i] != null,
                      flipOnMount: cards[i] != null,
                      delay: const Duration(milliseconds: 600),
                      back: WideCard(Assets.loyaltyBack, width: w, elevation: 2),
                      front:
                          WideCard(loyaltyArt(cards[i]), width: w, elevation: 2),
                    ),
                  ),
                ),
                Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 8.5 * s,
                        height: 1.3,
                        color: i == current
                            ? AvalonTheme.gold
                            : AvalonTheme.muted)),
              ]),
            ),
        ]),
      ]),
    );
  }
}

/// The Lady of the Lake lying by its holder's seat.
class LadyBadge extends StatelessWidget {
  const LadyBadge({super.key, required this.scale});
  final double scale;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: '湖中女神',
        child: Appear(
          key: const ValueKey('ladyBadge'),
          scaleFrom: .4,
          offset: Offset.zero,
          child: GameCard(Assets.ladyOfTheLake, width: 26 * scale, elevation: 3),
        ),
      );
}

/// Excalibur lying by its holder's seat.
class ExcaliburBadge extends StatelessWidget {
  const ExcaliburBadge({super.key, required this.scale});
  final double scale;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: '王者之劍',
        child: Appear(
          key: const ValueKey('excaliburBadge'),
          scaleFrom: .4,
          offset: Offset.zero,
          child: Token(Assets.excalibur, size: 30 * scale, elevation: 3),
        ),
      );
}
