import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_difficulty.dart';
import 'package:avalon_shadow_council/features/solo/memory/match_archive.dart';
import 'package:avalon_shadow_council/features/solo/memory/player_model.dart';
import 'support/bot_dialogue_fixtures.dart';

/// A model of the player built from [games] past games, each showing
/// [traits], all played with the computer player 'kai'.
PlayerModel model(Map<String, int> traits, {int games = 12}) =>
    PlayerModel.of('kai', [
      for (var i = 0; i < games; i++)
        MatchSummary(
            id: 'g$i',
            endedAt: DateTime(2026, 11, 1),
            players: 7,
            myRole: Role.loyal,
            won: true,
            winner: '正義',
            difficulty: '高手',
            episodes: const {'kai': []},
            traits: traits)
    ])!;

BotBrain brain(
        {PlayerModel? knows, BotDifficulty level = BotDifficulty.normal}) =>
    BotBrain(Random(1), difficulty: level)
      ..playerModel = knows
      ..playerSeat = 6;

/// Seat 6, the player, calls seat 3 suspicious on the second quest.
final accusation = DiscussionStatement(
    speaker: 6,
    quest: 2,
    generation: 4,
    attempt: 1,
    text: '3號很可疑',
    target: 3,
    position: DiscussionPosition.suspect);

void main() {
  final sharp = model({Trait.goodCalls: 5, Trait.goodCallsRight: 5});
  final wild = model({Trait.goodCalls: 5, Trait.goodCallsRight: 1});

  group("the player's calls", () {
    final o = observe(history: [
      QuestResult([1, 2], 0, true)
    ], statements: [
      accusation
    ]);
    double doubt(BotBrain b) => b.suspicion(o)[3];

    test('count for more from a player whose calls hit the mark', () {
      final plain = doubt(brain());
      expect(doubt(brain(knows: sharp)), greaterThan(plain));
      expect(doubt(brain(knows: wild)), lessThan(plain));
    });

    test('only the player is judged by the record', () {
      final someoneElse = observe(history: [
        QuestResult([1, 2], 0, true)
      ], statements: [
        DiscussionStatement(
            speaker: 5,
            quest: 2,
            generation: 4,
            attempt: 1,
            text: '3號很可疑',
            target: 3,
            position: DiscussionPosition.suspect)
      ]);
      expect(brain(knows: wild).suspicion(someoneElse)[3],
          brain().suspicion(someoneElse)[3]);
    });

    test('a beginner keeps no such record', () {
      expect(doubt(brain(knows: wild, level: BotDifficulty.novice)),
          doubt(brain(level: BotDifficulty.novice)));
    });

    test('a little record moves little', () {
      final once =
          model({Trait.goodCalls: 5, Trait.goodCallsRight: 1}, games: 1);
      final plain = doubt(brain());
      final little = plain - doubt(brain(knows: once));
      final lots = plain - doubt(brain(knows: wild));
      expect(little, greaterThan(0));
      expect(little, lessThan(lots / 2));
    });

    test('never overrides what a player knows for certain', () {
      // Merlin sees seat 3 as evil: no record of the player changes that
      final merlin = observe(role: Role.merlin, visible: [
        3,
        5
      ], history: [
        QuestResult([1, 2], 0, true)
      ], statements: [
        DiscussionStatement(
            speaker: 6,
            quest: 2,
            generation: 4,
            attempt: 1,
            text: '3號沒問題',
            target: 3,
            position: DiscussionPosition.defend)
      ]);
      expect(brain(knows: sharp).suspicion(merlin)[3], 1);
    });

    test('says nothing about the player\'s own side', () {
      // a player who as evil misled every time is not doubted for it
      final liar = model({
        Trait.gamesEvil: 1,
        Trait.evilCalls: 6,
        Trait.evilCallsMisleading: 6
      });
      final quiet = observe(history: [
        QuestResult([1, 2], 0, true)
      ]);
      expect(
          brain(knows: liar).suspicion(quiet)[6], brain().suspicion(quiet)[6]);
    });
  });

  test(
      'a vote for a failed team tells less from a player who votes alike '
      'on both sides', () {
    // seat 6 was off the team and backed it; the quest failed
    final o = observe(history: [
      QuestResult([1, 2], 0, true),
      QuestResult([3, 4, 5], 1, false)
    ], proposals: [
      ProposalRecord(
          quest: 2,
          attempt: 1,
          leader: 5,
          team: [3, 4, 5],
          votes: [false, false, false, true, true, true, true])
    ]);
    final alike = model({
      Trait.goodSawDirty: 10,
      Trait.goodBackedDirty: 5,
      Trait.evilSawDirty: 10,
      Trait.evilBackedDirty: 5,
    });
    final telling = model({
      Trait.goodSawDirty: 10,
      Trait.goodBackedDirty: 1,
      Trait.evilSawDirty: 10,
      Trait.evilBackedDirty: 9,
    });
    final plain = brain().suspicion(o)[6];
    expect(brain(knows: alike).suspicion(o)[6], lessThan(plain));
    expect(brain(knows: telling).suspicion(o)[6], greaterThan(plain));
  });

  test('the Assassin reads leads as the player has shown them to be', () {
    // the player (seat 6) led two clean teams; seat 2 led none
    final o = observe(
        role: Role.assassin,
        evil: true,
        visible: [3, 5],
        phase: GamePhase.assassination,
        history: [
          QuestResult([1, 2], 0, true),
          QuestResult([1, 2, 6], 0, true),
          QuestResult([0, 1, 6], 0, true)
        ],
        proposals: [
          ProposalRecord(
              quest: 1,
              attempt: 1,
              leader: 1,
              team: [1, 2],
              votes: List.filled(7, true)),
          ProposalRecord(
              quest: 2,
              attempt: 1,
              leader: 6,
              team: [1, 2, 6],
              votes: List.filled(7, true)),
          ProposalRecord(
              quest: 3,
              attempt: 1,
              leader: 6,
              team: [0, 1, 6],
              votes: List.filled(7, true)),
        ]);
    int stabs(PlayerModel? knows) => [
          for (var seed = 0; seed < 200; seed++)
            if ((BotBrain(Random(seed))
                      ..playerModel = knows
                      ..playerSeat = 6)
                    .assassinate(o) ==
                6)
              1
        ].length;
    // as Merlin this player leads like anyone else: leads give nothing away
    final hides = model({
      Trait.gamesMerlin: 1,
      Trait.merlinLeads: 4,
      Trait.merlinLeadsClean: 2,
      Trait.goodLeads: 4,
      Trait.goodLeadsClean: 2,
    });
    expect(stabs(hides), lessThan(stabs(null)));
  });
}
