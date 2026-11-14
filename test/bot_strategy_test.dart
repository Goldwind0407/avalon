import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_observation.dart';
import 'support/bot_dialogue_fixtures.dart';

/// How many of 300 differently seeded bots do [act].
double share(bool Function(BotBrain) act) {
  var n = 0;
  for (var seed = 0; seed < 300; seed++) {
    if (act(BotBrain(Random(seed)))) n++;
  }
  return n / 300;
}

void main() {
  group('a lone evil player on the first quest', () {
    BotObservation first(int count, List<int> team) => observe(
        role: Role.minion,
        evil: true,
        count: count,
        visible: [count - 1],
        leader: 0,
        phase: GamePhase.quest,
        team: team);

    test('usually lies low at a small table', () {
      expect(share((b) => b.questCard(first(5, [0, 1]))), greaterThan(.65));
      expect(share((b) => b.questCard(first(7, [0, 1]))), greaterThan(.65));
    });

    test('holds back less at a large one', () {
      final small = share((b) => b.questCard(first(7, [0, 1, 2])));
      final large = share((b) => b.questCard(first(10, [0, 1, 2])));
      expect(large, lessThan(small - .15));
    });

    test('later he mostly plays Fail', () {
      final later = observe(
          role: Role.minion,
          evil: true,
          visible: [6],
          leader: 0,
          phase: GamePhase.quest,
          team: [0, 1, 2],
          history: [
            QuestResult([3, 4], 0, true)
          ]);
      expect(share((b) => b.questCard(later)), lessThan(.35));
    });
  });

  group('an evil player alone with Excalibur', () {
    // seat 2 sat on a quest that the ally in seat 6 failed; seat 1 has a
    // clean record
    final o = observe(
        role: Role.minion,
        evil: true,
        // seven players: both of his allies are known to him
        visible: [5, 6],
        leader: 3,
        phase: GamePhase.quest,
        team: [0, 1, 2],
        expansions: const ExpansionSettings(excalibur: true),
        excaliburHolder: 0,
        history: [
          QuestResult([1, 4], 0, true),
          QuestResult([2, 6], 1, false)
        ]);

    test('plays Success himself', () {
      expect(share((b) => b.questCard(o)), 1);
    });

    test('and turns over the card of the member the table doubts', () {
      final played = BotObservation(
          seat: o.seat,
          role: o.role,
          evil: true,
          count: o.count,
          leader: o.leader,
          quest: o.quest,
          rejections: 0,
          failsRequired: 1,
          expansions: o.expansions,
          switched: false,
          visible: o.visible,
          team: o.team,
          history: o.history,
          proposals: const [],
          ladyPast: const [],
          facts: const [],
          statements: const [],
          ownCards: {o.quest: true},
          excaliburHolder: 0,
          phase: GamePhase.excalibur);
      for (var seed = 0; seed < 30; seed++) {
        expect(BotBrain(Random(seed)).swordTarget(played), 2);
      }
    });

    test('with an ally on the team he leaves the cards alone', () {
      final withAlly = observe(
          role: Role.minion,
          evil: true,
          visible: [1],
          leader: 3,
          phase: GamePhase.quest,
          team: [0, 1, 2],
          expansions: const ExpansionSettings(excalibur: true),
          excaliburHolder: 0,
          history: [
            QuestResult([3, 4], 0, true)
          ]);
      // seat order decides who sabotages: the first ally plays the Fail
      expect(share((b) => b.questCard(withAlly)), 0);
    });
  });

  test('the evil Lancelot keeps a clean record before the switch cards', () {
    BotObservation lancelot(int variant) => observe(
        role: Role.lancelotEvil,
        evil: true,
        leader: 1,
        phase: GamePhase.quest,
        team: [0, 1, 2],
        expansions: ExpansionSettings(lancelot: variant),
        history: [
          QuestResult([3, 4], 0, true)
        ]);
    final early = share((b) => b.questCard(lancelot(1)));
    expect(early, greaterThan(.55));
    // from the third quest on he sabotages like anyone else
    final late = observe(
        role: Role.lancelotEvil,
        evil: true,
        leader: 1,
        phase: GamePhase.quest,
        team: [0, 1, 2],
        expansions: const ExpansionSettings(lancelot: 1),
        loyalty: const [null, null, false, null, null],
        history: [
          QuestResult([3, 4], 0, true),
          QuestResult([3, 4, 5], 0, true)
        ]);
    expect(share((b) => b.questCard(late)), lessThan(early - .3));
  });
}
