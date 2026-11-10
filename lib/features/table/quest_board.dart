import 'package:flutter/material.dart';
import '../../core/assets.dart';
import '../../core/theme.dart';
import '../game/game_model.dart';
import 'board_layout.dart';
import 'components.dart';
import 'effects.dart';

/// The printed scoreboard lying on the mat, with the physical markers on it.
class QuestBoard extends StatelessWidget {
  const QuestBoard({super.key, required this.game, this.onImpact});
  final AvalonGame game;

  /// A score marker has just been dropped onto the board.
  final VoidCallback? onImpact;

  @override
  Widget build(BuildContext context) {
    final layout = BoardLayout.forPlayers(game.players.length);
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: LayoutBuilder(builder: (context, c) {
        final k = c.maxWidth / BoardLayout.basis.width;
        // The result of the quest being revealed is not on the board yet:
        // its marker is only placed once the cards have been turned over.
        final scored =
            game.history.length - (game.phase == GamePhase.questResult ? 1 : 0);
        final playing = game.phase != GamePhase.finished &&
            game.phase != GamePhase.assassination &&
            scored < 5;
        final current = scored.clamp(0, 4);
        final ring = BoardLayout.questRadius * 2.08 * k;
        final slot = BoardLayout.slotRadius * 2.15 * k;
        final voteSize = BoardLayout.voteRadius * 2 * k * .78;
        final lastChance = game.rejections >= 4 && playing;
        return Transform(
          // lying on the table: tilt away from the viewer a little
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .0007)
            ..rotateX(.16),
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(c.maxWidth * .018),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: .65),
                        blurRadius: 18,
                        offset: const Offset(0, 10)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(c.maxWidth * .018),
                  child: artImage(context, Assets.board(game.players.length),
                      width: c.maxWidth,
                      height: c.maxWidth * .75,
                      fit: BoxFit.cover),
                ),
              ),
            ),
            // glow around the quest being played; glides to the next one
            AnimatedPositioned(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInOutCubic,
              left: layout.quests[current].dx * k - ring / 2,
              top: layout.quests[current].dy * k - ring / 2,
              width: ring,
              height: ring,
              child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: playing ? 1 : 0,
                  child: PulseRing(diameter: ring)),
            ),
            if (lastChance)
              Positioned(
                left: layout.votes[4].dx * k - voteSize * .64,
                top: layout.votes[4].dy * k - voteSize * .64,
                width: voteSize * 1.28,
                height: voteSize * 1.28,
                child: PulseRing(
                    diameter: voteSize * 1.28, color: const Color(0xFFFF4A3A)),
              ),
            for (var i = 0; i < scored; i++)
              HopTo(
                key: ValueKey('score$i'),
                center: layout.slot(i) * k,
                size: slot,
                dropIn: true,
                rippleColor: game.history[i].succeeded
                    ? const Color(0xFF8FD3FF)
                    : const Color(0xFFFF7A66),
                onLand: onImpact,
                child: Token(
                    game.history[i].succeeded
                        ? Assets.scoreGood
                        : Assets.scoreEvil,
                    size: slot,
                    elevation: 4 * k + 1),
              ),
            // round marker: sits at the top-left of the current bubble,
            // clear of the previous quest's score marker
            if (playing)
              HopTo(
                key: const ValueKey('round'),
                center: (layout.quests[current] + const Offset(-98, -90)) * k,
                size: 80 * k,
                lift: 46 * k,
                delay: const Duration(milliseconds: 450),
                rippleColor: AvalonTheme.gold,
                child: Token(Assets.roundMarker,
                    size: 80 * k, elevation: 4 * k + 1),
              ),
            HopTo(
              key: const ValueKey('voteTrack'),
              center: layout.votes[game.rejections.clamp(0, 4)] * k,
              size: voteSize,
              lift: 40 * k,
              rippleColor: Colors.white,
              child: Token(Assets.voteTrackMarker,
                  size: voteSize, elevation: 5 * k + 1),
            ),
          ]),
        );
      }),
    );
  }
}
