import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'support/bot_dialogue_fixtures.dart';

DiscussionStatement pos(int by, int q, int a, int to, bool suspect) =>
    DiscussionStatement(
        speaker: by,
        quest: q,
        generation: 4,
        attempt: a,
        text: '',
        target: to,
        position:
            suspect ? DiscussionPosition.suspect : DiscussionPosition.defend);

ProposalRecord prop(int q, int a, int leader, List<int> team, String v) =>
    ProposalRecord(
        quest: q,
        attempt: a,
        leader: leader,
        team: team,
        votes: [for (final c in v.split('')) c == 'o']);

void main() {
  // A reported 7-player game with Lady and Lancelot (variant one), no switch
  // yet: quest 2 (seats 3, 4, 5) failed with one Fail. Every good player
  // sees that one of the others on it is evil, and never sends the same
  // team again.
  for (final (role, seat, visible) in [
    (Role.percival, 5, [1, 4]),
    (Role.lancelotGood, 2, <int>[]),
    (Role.loyal, 0, <int>[]),
  ]) {
    test('$role does not resend the team that just failed', () {
      final o = observe(
          role: role,
          count: 7,
          seat: seat,
          leader: 5,
          rejections: 1,
          phase: GamePhase.team,
          team: [3, 4, 5],
          visible: visible,
          expansions: const ExpansionSettings(lady: true, lancelot: 1),
          loyalty: const [null, null, false, null, null],
          history: [
            QuestResult([0, 5], 0, true),
            QuestResult([3, 4, 5], 1, false),
          ],
          proposals: [
            prop(1, 1, 5, [0, 5], 'ooooooo'),
            prop(2, 1, 6, [0, 2, 6], 'oxoxxxo'),
            prop(2, 2, 0, [0, 4, 5], 'ooxxxxx'),
            prop(2, 3, 1, [1, 4, 5], 'xoxxxxx'),
            prop(2, 4, 2, [2, 3, 5], 'oxoxxxo'),
            prop(2, 5, 3, [3, 4, 5], 'ooooooo'),
            prop(3, 1, 4, [0, 2, 4], 'ooxxoxx'),
          ],
          ladyChecks: const [LadyCheck(4, 5, 2)],
          statements: [
            pos(4, 2, 3, 1, true),
            pos(5, 2, 3, 1, true),
            pos(5, 2, 4, 1, true),
            pos(6, 2, 4, 1, true),
            pos(6, 2, 5, 0, true),
            pos(0, 2, 5, 4, true),
            pos(1, 2, 5, 0, true),
            pos(2, 2, 5, 0, true),
            DiscussionStatement(
                speaker: 4,
                quest: 3,
                generation: 4,
                attempt: 1,
                text: '',
                target: 5,
                claimedEvil: false,
                intent: 'interpretLady'),
            pos(2, 3, 1, 1, true),
            pos(3, 3, 1, 0, true),
            pos(4, 3, 1, 0, false),
            pos(0, 3, 2, 4, true),
          ]);
      final p = BotBrain(Random(1)).suspicion(o);
      final others = [3, 4, 5].where((s) => s != seat).toList();
      // the one Fail sits among the others of that team
      expect(others.fold(0.0, (sum, s) => sum + p[s]),
          greaterThan(others.length == 3 ? .95 : .85),
          reason: '$role');
      for (var s = 0; s < 50; s++) {
        expect(BotBrain(Random(s)).chooseTeam(o, 3), isNot([3, 4, 5]),
            reason: '$role seed $s');
      }
    });
  }
}
