import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_difficulty.dart';
import 'support/bot_selfplay.dart';

/// Fixed seeds, so these numbers only move when the strategy changes. The
/// bands are deliberately wide: they catch a strategy that breaks the game
/// (one side always winning, endless rejections, give-away habits).
void main() {
  const novice = BotDifficulty.novice,
      normal = BotDifficulty.normal,
      expert = BotDifficulty.expert;

  test('all-bot games stay plausible at every level', () {
    for (final level in BotDifficulty.values) {
      for (final (n, minGood) in [(5, .22), (7, .1), (10, .1)]) {
        final stats = selfPlay(n, 300, good: level, evil: level);
        // ignore: avoid_print
        print('${level.label} $stats');
        final where = '${level.name}, $n players';
        expect(stats.goodWinRate, inInclusiveRange(minGood, .6), reason: where);
        expect(stats.stabRate, lessThan(.7), reason: '$where: Merlin');
        expect(stats.proposalsPerQuest, lessThan(2.5), reason: where);
        expect(stats.hammerEvilRejects, 0, reason: where);
        expect(stats.uselessLoneFails, 0, reason: where);
        expect(stats.certainMissed, 0, reason: where);
        if (level != novice) {
          expect(stats.evilLeadsStacked / stats.evilLeads, lessThan(.4),
              reason: where);
        }
      }
    }
  });

  test('a higher level plays its side better', () {
    double good(BotDifficulty g, BotDifficulty e) =>
        [5, 7]
            .map((n) => selfPlay(n, 300, good: g, evil: e).goodWinRate)
            .reduce((a, b) => a + b) /
        2;
    final base = good(normal, normal);
    // ignore: avoid_print
    print('good wins: normal/normal ${base.toStringAsFixed(2)}, '
        'novice good ${good(novice, normal).toStringAsFixed(2)}, '
        'novice evil ${good(normal, novice).toStringAsFixed(2)}, '
        'expert evil ${good(normal, expert).toStringAsFixed(2)}, '
        'expert good ${good(expert, normal).toStringAsFixed(2)}');
    expect(good(novice, normal), lessThan(base - .05));
    expect(good(normal, novice), greaterThan(base));
    expect(good(normal, expert), lessThan(base));
    expect(good(expert, normal), greaterThanOrEqualTo(base - .02));
  });

  test('games with Oberon and Mordred finish and stay plausible', () {
    for (final roles in [
      {Role.percival, Role.oberon},
      {Role.percival, Role.morgana, Role.mordred},
      {Role.mordred, Role.oberon},
    ]) {
      final stats = selfPlay(8, 200, roles: roles);
      // ignore: avoid_print
      print('$roles $stats');
      expect(stats.goodWinRate, inInclusiveRange(.08, .7), reason: '$roles');
    }
  });
}
