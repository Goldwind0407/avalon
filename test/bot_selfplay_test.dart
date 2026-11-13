import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_difficulty.dart';
import 'support/bot_selfplay.dart';

/// Fixed seeds, so these numbers only move when the strategy changes. The
/// bands are deliberately wide: they catch a strategy that breaks the game
/// (one side always winning, endless rejections, give-away habits).
void main() {
  test('expert self-play includes discussion, responses and final vote review',
      () {
    var responses = 0, revised = 0;
    for (final n in [5, 7]) {
      final stats = selfPlay(n, 40,
          good: BotDifficulty.expert,
          evil: BotDifficulty.expert,
          withDiscussion: true);
      expect(stats.utterances, stats.proposals * n);
      expect(stats.goodWinRate, inInclusiveRange(.05, .85));
      expect(stats.proposalsPerQuest, lessThan(5));
      expect(stats.certainMissed, 0);
      responses += stats.directResponses;
      revised += stats.revisedVotes;
      // ignore: avoid_print
      print(
          'With discussion: $stats\nresponses=${stats.directResponses}, revised=${stats.revisedVotes}');
    }
    expect(responses, greaterThan(0));
    expect(revised, greaterThan(0));
  });
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

  test('difficulty balance stays within the seeded sample tolerance', () {
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
    // 600 games cannot establish superiority from a one-game difference.
    // Treat this as a regression band, not a proof of a difficulty ranking.
    // A 4-point change is about 1.5 standard errors for rates near 0.3.
    expect(good(normal, novice), greaterThanOrEqualTo(base - .04));
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
