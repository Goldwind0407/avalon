import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_difficulty.dart';
import 'package:avalon_shadow_council/features/solo/bot_observation.dart';
import 'support/bot_dialogue_fixtures.dart';

ProposalRecord prop(int q, int a, int leader, List<int> team, String votes) =>
    ProposalRecord(
        quest: q,
        attempt: a,
        leader: leader,
        team: team,
        votes: [for (final c in votes.split('')) c == 'o']);

void main() {
  // From a user's game (7 players, Lady, Lancelot variant one), seats 0-6
  // being 1號-7號: Merlin (seat 2) leads the fourth proposal of the last
  // quest, two failed quests behind. The Lancelots switched at quest 4: the
  // Assassin (1) now looks as if he could be the evil Lancelot gone good,
  // since he sat on the clean fourth quest; but that quest needed two Fails,
  // and the player Merlin checked good with the Lady (0) has announced that
  // his own Lady showed 1 as evil. Merlin led 0,1,2,5 and lost the game.
  test('Merlin with the switch to read does not send the Assassin at the end',
      () {
    final o = observe(
      role: Role.merlin,
      seat: 2,
      count: 7,
      visible: [1, 4, 6],
      leader: 2,
      rejections: 3,
      phase: GamePhase.team,
      switched: true,
      expansions: const ExpansionSettings(lady: true, lancelot: 1),
      loyalty: [false, false, false, true, false],
      history: [
        QuestResult([4, 6], 1, false),
        QuestResult([0, 1, 2], 1, false),
        QuestResult([2, 3, 5], 0, true),
        QuestResult([0, 1, 2, 5], 0, true),
      ],
      proposals: [
        prop(1, 1, 6, [4, 6], 'ooooooo'),
        prop(2, 1, 0, [0, 1, 2], 'oooo..o'),
        prop(3, 1, 1, [0, 1, 2], '.o..o..'),
        prop(3, 2, 2, [2, 3, 5], '...oooo'.replaceRange(0, 3, '.xo').replaceAll('x', '.')),
        prop(4, 1, 3, [0, 3, 4, 6], '...oo..'),
        prop(4, 2, 4, [1, 3, 4, 5], '...oo..'),
        prop(4, 3, 5, [0, 1, 2, 5], '.oo..oo'),
        prop(5, 1, 6, [0, 2, 5, 6], '...o..o'),
        prop(5, 2, 0, [0, 2, 3, 5], 'o..oo..'),
        prop(5, 3, 1, [1, 2, 5, 6], '.o.o...'),
      ],
      facts: const [
        BotFact(quest: 3, target: 0, switched: false, owner: 2, generation: 4, evil: false),
      ],
      statements: [
        DiscussionStatement(speaker: 5, quest: 3, text: '女神我拿去看了3號，結果是正義。', target: 2, claimedEvil: false, switched: false, generation: 4),
        DiscussionStatement(speaker: 2, quest: 4, text: '女神我拿去看了1號，結果是正義。', target: 0, claimedEvil: false, switched: true, generation: 4),
        DiscussionStatement(speaker: 0, quest: 5, text: '我用湖中女神查驗了2號，他是邪惡陣營。', target: 1, claimedEvil: true, switched: true, generation: 4),
      ],
    );
    final p = BotBrain(Random(1), difficulty: BotDifficulty.expert).suspicion(o);
    // a result from a seat all but surely good counts nearly as a fact
    expect(p[1], greaterThan(.9));
    // the good Lancelot, now evil, is worked out from the record
    expect(p[3], greaterThan(.9));
    for (var seed = 0; seed < 40; seed++) {
      final team = BotBrain(Random(seed), difficulty: BotDifficulty.expert)
          .chooseTeam(o, 4);
      // the one team of four good players left: 1, 3, 6, 7
      expect(team, [0, 2, 5, 6], reason: 'seed $seed');
    }
  });
}
