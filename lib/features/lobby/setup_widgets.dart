import 'package:flutter/material.dart';
import '../../core/assets.dart';
import '../../core/theme.dart';
import '../game/game_model.dart';

// The pieces of the setup screens, shared by pass-and-play, solo and the
// online lobby so the three look alike.

const setupGoodColor = Color(0xFF6FA8FF), setupEvilColor = Color(0xFFFF7A7A);

/// One seat at the table: its number in a gold ring, the name, and
/// whatever goes after it (a style, marks, small buttons).
class SetupSeat extends StatelessWidget {
  const SetupSeat(
      {super.key,
      required this.number,
      required this.name,
      this.leading,
      this.trailing = const [],
      this.highlight = false,
      this.dim = false,
      this.onTap,
      this.tapKey});
  final int number;

  /// Put on the tappable area (tests look for it there).
  final Key? tapKey;
  final String name;

  /// Shown before the number (who is speaking, who is away).
  final Widget? leading;
  final List<Widget> trailing;

  /// This player's own seat.
  final bool highlight;

  /// A seat nobody controls right now.
  final bool dim;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AvalonTheme.raised.withValues(alpha: .7),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
            side: BorderSide(
                color: highlight
                    ? AvalonTheme.gold.withValues(alpha: .55)
                    : Colors.white.withValues(alpha: .05))),
        child: InkWell(
          key: tapKey,
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(children: [
                if (leading != null) leading!,
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AvalonTheme.bg.withValues(alpha: .6),
                      border: Border.all(
                          color: AvalonTheme.gold.withValues(alpha: .6))),
                  child: Text('$number',
                      style: const TextStyle(
                          fontSize: 11.5,
                          color: AvalonTheme.gold,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 9),
                Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            color: dim ? AvalonTheme.muted : Colors.white))),
                ...trailing,
              ])),
        ),
      );
}

/// A seat nobody sits in yet; [onTap] (with [label]) offers to fill it.
class SetupEmptySeat extends StatelessWidget {
  const SetupEmptySeat({super.key, this.label = '空位', this.icon, this.onTap});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return Material(
      color: active
          ? AvalonTheme.violet.withValues(alpha: .14)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(
              color: active
                  ? AvalonTheme.gold.withValues(alpha: .35)
                  : Colors.white.withValues(alpha: .06))),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon,
                size: 16, color: active ? AvalonTheme.gold : AvalonTheme.muted),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  color: active
                      ? AvalonTheme.gold
                      : Colors.white.withValues(alpha: .22))),
        ])),
      ),
    );
  }
}

/// One role that can be in the deal: its portrait framed in its side's
/// colour, its name and side, and whether it is in.
class SetupRole extends StatelessWidget {
  const SetupRole(
      {super.key,
      required this.role,
      required this.side,
      required this.active,
      required this.locked,
      this.onTap,
      this.tapKey});
  final Role role;

  /// Put on the tappable area (tests look for it there).
  final Key? tapKey;
  final String side;
  final bool active, locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sideColor = role.isEvil ? setupEvilColor : setupGoodColor;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: active ? 1 : .55,
      child: Material(
        color: active
            ? AvalonTheme.violet.withValues(alpha: .26)
            : AvalonTheme.raised.withValues(alpha: .6),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
            side: BorderSide(
                color: active
                    ? AvalonTheme.gold.withValues(alpha: .5)
                    : Colors.white.withValues(alpha: .05))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: tapKey,
          onTap: locked ? null : onTap,
          child: Row(children: [
            Container(
              width: 34,
              margin: const EdgeInsets.fromLTRB(5, 5, 0, 5),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: sideColor.withValues(alpha: .8))),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(Assets.role(role, 0),
                      fit: BoxFit.cover, alignment: const Alignment(0, -.55))),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(role.label,
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: active
                                      ? AvalonTheme.gold
                                      : Colors.white)),
                          Text(side,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: sideColor.withValues(alpha: .85))),
                        ]))),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                  locked
                      ? Icons.lock_outline
                      : active
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                  size: 16,
                  color: active ? AvalonTheme.gold : AvalonTheme.muted),
            ),
          ]),
        ),
      ),
    );
  }
}

/// How many play on each side, with the sides' crests, and a note.
class SetupTally extends StatelessWidget {
  const SetupTally(
      {super.key,
      required this.good,
      required this.evil,
      this.note = '其餘名額自動補齊'});
  final int good, evil;
  final String note;
  @override
  Widget build(BuildContext context) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _side(Assets.logoGood, '正義', good, setupGoodColor),
        const SizedBox(width: 8),
        _side(Assets.logoEvil, '邪惡', evil, setupEvilColor),
        const SizedBox(width: 10),
        Text(note,
            style: const TextStyle(fontSize: 11.5, color: AvalonTheme.muted)),
      ]));

  Widget _side(String crest, String side, int count, Color color) => Container(
        padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
        decoration: ShapeDecoration(
            color: color.withValues(alpha: .12),
            shape: StadiumBorder(
                side: BorderSide(color: color.withValues(alpha: .4)))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Image.asset(crest, width: 22, height: 22),
          const SizedBox(width: 4),
          Text('$side $count 人', style: TextStyle(fontSize: 12, color: color)),
        ]),
      );
}

/// Lays [count] cells out in two columns of rows that share the height.
class SetupGrid extends StatelessWidget {
  const SetupGrid(
      {super.key, required this.count, required this.cell, this.rows});
  final int count;
  final Widget Function(int index) cell;

  /// At least this many rows (empty cells keep their place).
  final int? rows;
  @override
  Widget build(BuildContext context) {
    final rowCount = rows ?? (count + 1) ~/ 2;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var row = 0; row < rowCount; row++)
        Expanded(
            child: Padding(
          padding: EdgeInsets.only(top: row == 0 ? 0 : 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var column = 0; column < 2; column++) ...[
              if (column == 1) const SizedBox(width: 7),
              Expanded(
                  child: row * 2 + column >= count
                      ? const SizedBox.shrink()
                      : cell(row * 2 + column)),
            ]
          ]),
        )),
    ]);
  }
}
