import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_difficulty.dart';
import 'support/bot_dialogue_fixtures.dart';

ProposalRecord proposal(
        int quest, int attempt, int leader, List<int> team, List<bool> votes) =>
    ProposalRecord(
        quest: quest,
        attempt: attempt,
        leader: leader,
        team: team,
        votes: votes);

const yes = true, no = false;

void main() {
  group('what the public votes say', () {
    // leader 1 proposed 1 and 2; only they and seat 3 said yes: voted down
    final rejected = proposal(1, 1, 1, [1, 2], [no, yes, yes, yes, no, no, no]);

    test('backing a rejected team from outside it is the plainest tell', () {
      final p = BotBrain(Random(1)).suspicion(observe(proposals: [rejected]));
      expect(p[3], greaterThan(p[4] + .2));
      // a member who backed his own team is doubted less than that
      expect(p[2], lessThan(p[3]));
      expect(p[2], greaterThan(p[4]));
    });

    test('it adds up over several proposals', () {
      final brain = BotBrain(Random(1));
      final once = brain.suspicion(observe(proposals: [rejected]));
      final twice = brain.suspicion(observe(proposals: [
        rejected,
        proposal(1, 2, 2, [2, 5], [no, no, yes, yes, no, yes, no])
      ]));
      expect(twice[3], greaterThan(once[3] + .1));
    });

    test('turning down a team that then failed speaks for a player', () {
      final p = BotBrain(Random(1)).suspicion(observe(history: [
        QuestResult([1, 2], 1, false)
      ], proposals: [
        proposal(1, 1, 1, [1, 2], [yes, yes, yes, yes, yes, no, no])
      ]));
      expect(p[5], lessThan(p[3] - .15));
      expect(p[5], lessThan(p[4] - .15));
    });

    test('the forced fifth proposal says nothing', () {
      final brain = BotBrain(Random(1));
      final fifth = brain.suspicion(observe(proposals: [
        proposal(1, 5, 1, [1, 2], [no, yes, yes, yes, no, no, no])
      ]));
      expect(fifth[3], closeTo(fifth[4], 1e-9));
    });

    test('a beginner does not read votes', () {
      final p = BotBrain(Random(1), difficulty: BotDifficulty.novice)
          .suspicion(observe(proposals: [rejected]));
      expect(p[3], closeTo(p[4], 1e-9));
    });

    test('what is certain is not moved by votes', () {
      // a failed pair: the loyal member knows his partner
      final p = BotBrain(Random(1)).suspicion(observe(history: [
        QuestResult([0, 1], 1, false)
      ], ownCards: {
        1: true
      }, proposals: [
        proposal(1, 1, 0, [0, 1], [yes, no, yes, yes, yes, no, no])
      ]));
      expect(p[1], 1);
    });
  });

  group('an evil player does not back every team his ally is on', () {
    // Ally 1 sat on the failed pair, so a player who knows nothing would
    // turn down a team with him on it.
    final history = [
      QuestResult([1, 3], 1, false)
    ];
    double approvals(List<QuestResult> history,
        {List<int> team = const [1, 2]}) {
      var approved = 0;
      for (var seed = 0; seed < 300; seed++) {
        final o = observe(
            role: Role.minion,
            evil: true,
            visible: [1],
            leader: 1,
            team: team,
            history: history);
        if (BotBrain(Random(seed)).vote(o)) approved++;
      }
      return approved / 300;
    }

    test('from outside the team, early in the quest, he mostly holds back', () {
      expect(approvals(history), lessThan(.4));
    });

    test('from inside the team he backs it more often', () {
      expect(approvals(history, team: [0, 1]),
          greaterThan(approvals(history) + .15));
    });

    test('when one more failed quest wins, he backs it', () {
      expect(
          approvals([
            ...history,
            QuestResult([1, 4, 5], 1, false)
          ]),
          greaterThan(.7));
    });
  });

  test('an evil leader takes players nobody doubts along with the saboteur',
      () {
    // seats 2 and 3 came back from a clean quest; 4 sat on a failed one
    var trusted = 0, oneEvil = 0;
    for (var seed = 0; seed < 100; seed++) {
      final o = observe(
          role: Role.minion,
          evil: true,
          visible: [1],
          leader: 0,
          phase: GamePhase.team,
          team: const [],
          history: [
            QuestResult([2, 3], 0, true),
            QuestResult([4, 5, 6], 1, false)
          ]);
      final team = BotBrain(Random(seed)).chooseTeam(o, 3);
      if (team.contains(2) && team.contains(3)) trusted++;
      if (team.where([0, 1].contains).length == 1) oneEvil++;
    }
    expect(oneEvil, greaterThan(80));
    expect(trusted, greaterThan(60));
  });
}
