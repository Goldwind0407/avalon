import 'package:flutter_test/flutter_test.dart';
import 'support/bot_selfplay.dart';

/// Fixed seeds, so these numbers only move when the strategy changes. The
/// bands are deliberately wide: they catch a strategy that breaks the game
/// (one side always winning, endless rejections, give-away habits).
void main() {
  test('all-bot games stay plausible', () {
    for (final (n, minGood) in [(5, .25), (7, .18), (10, .12)]) {
      final stats = selfPlay(n, 300);
      // ignore: avoid_print
      print(stats);
      expect(stats.goodWinRate, inInclusiveRange(minGood, .6), reason: '$n');
      expect(stats.stabRate, lessThan(.6), reason: '$n players: Merlin');
      expect(stats.proposalsPerQuest, lessThan(2.5), reason: '$n');
      expect(stats.hammerEvilRejects, 0);
      expect(stats.uselessLoneFails, 0);
      expect(stats.certainMissed, 0);
      expect(stats.evilLeadsStacked / stats.evilLeads, lessThan(.4));
    }
  });
}
