import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_observation.dart';
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

/// Seat 1 ("2號", a loyal servant) at the end of a 5-player game a player
/// reported: his own Lady check showed seat 4 is evil, so seat 3 is clean
/// and one of seats 0 and 2 is the other evil player. Seat 2 spoke up for
/// seat 4 twice; seat 0 (the player, Merlin) told the truth about his own
/// Lady check and called seat 4 out.
BotObservation seat2() => observe(
        count: 5,
        seat: 1,
        leader: 1,
        rejections: 1,
        phase: GamePhase.team,
        expansions: const ExpansionSettings(lady: true),
        history: [
          QuestResult([1, 4], 0, true),
          QuestResult([0, 1, 2], 1, false),
          QuestResult([1, 3], 0, true),
          QuestResult([1, 3, 4], 1, false),
        ],
        proposals: [
          ProposalRecord(
              quest: 1,
              attempt: 1,
              leader: 1,
              team: [1, 4],
              votes: [true, true, true, true, true]),
          ProposalRecord(
              quest: 2,
              attempt: 1,
              leader: 2,
              team: [0, 1, 2],
              votes: [true, true, true, false, true]),
          ProposalRecord(
              quest: 3,
              attempt: 1,
              leader: 3,
              team: [1, 3],
              votes: [true, true, false, true, true]),
          ProposalRecord(
              quest: 4,
              attempt: 1,
              leader: 4,
              team: [1, 3, 4],
              votes: [true, false, true, false, true]),
          ProposalRecord(
              quest: 5,
              attempt: 1,
              leader: 0,
              team: [0, 1, 3],
              votes: [true, false, false, true, false]),
        ],
        ladyChecks: const [
          LadyCheck(0, 1, 2),
          LadyCheck(1, 4, 3),
          LadyCheck(4, 3, 4)
        ],
        facts: const [
          BotFact(
              quest: 3,
              target: 4,
              switched: false,
              owner: 1,
              generation: 4,
              evil: true)
        ],
        statements: [
          pos(4, 3, 1, 0, true),
          DiscussionStatement(
              speaker: 0,
              quest: 3,
              generation: 4,
              attempt: 1,
              text: '',
              target: 1,
              claimedEvil: false,
              intent: 'interpretLady'),
          pos(0, 3, 1, 2, true),
          pos(1, 3, 1, 2, true),
          pos(3, 3, 1, 2, true),
          pos(0, 4, 1, 4, true),
          pos(1, 4, 1, 4, true),
          pos(2, 4, 1, 4, false),
          pos(3, 4, 1, 4, true),
          pos(1, 5, 1, 4, true),
          pos(2, 5, 1, 4, false),
          pos(3, 5, 1, 4, true),
          pos(0, 5, 1, 4, true),
          pos(3, 5, 2, 2, true),
          pos(4, 5, 2, 2, false),
        ]);

void main() {
  test('one of two is evil: what damns one clears the other', () {
    final full = seat2();
    // the player's proposal: seats 0, 1 and 3
    final o = observe(
        count: 5,
        seat: 1,
        leader: 0,
        rejections: 0,
        phase: GamePhase.vote,
        team: [0, 1, 3],
        expansions: full.expansions,
        history: full.history,
        proposals: full.proposals.take(4).toList(),
        ladyChecks: full.ladyChecks,
        facts: full.facts,
        statements: full.statements.where((x) => x.attempt == 1).toList());
    final p = BotBrain(Random(1)).suspicion(o);
    // defending a player he knows is evil gives seat 2 away, and so clears
    // seat 0: their suspicion adds up to the one evil place between them
    expect(p[2], greaterThan(.7));
    expect(p[0], lessThan(.3));
    expect(p[0] + p[2], closeTo(1, .05));
    for (var seed = 0; seed < 100; seed++) {
      expect(BotBrain(Random(seed)).vote(o), isTrue, reason: 'seed $seed');
    }
  });

  test('a team turned down by the players he doubts can be sent again', () {
    // seat 2 and seat 4 turned the player's team down; as leader he sends
    // it again rather than one with seat 2 on it
    for (var seed = 0; seed < 100; seed++) {
      expect(BotBrain(Random(seed)).chooseTeam(seat2(), 3), [0, 1, 3]);
    }
  });
}
