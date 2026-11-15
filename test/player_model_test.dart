import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/game_review.dart';
import 'package:avalon_shadow_council/features/solo/memory/match_archive.dart';
import 'package:avalon_shadow_council/features/solo/memory/match_repository.dart';
import 'package:avalon_shadow_council/features/solo/memory/player_model.dart';

/// Seven players; seat 0 is the player. Seats 3 and 5 are evil.
GameReview review(
        {required Role me,
        List<ProposalRecord> proposals = const [],
        List<QuestResult> history = const [],
        List<DiscussionStatement> statements = const [],
        List<LadyCheck> lady = const []}) =>
    GameReview.build(
        players: [for (var i = 0; i < 7; i++) 'p$i'],
        roles: [
          me,
          me == Role.merlin ? Role.loyal : Role.merlin,
          Role.loyal,
          Role.minion,
          me == Role.percival ? Role.loyal : Role.percival,
          me == Role.assassin ? Role.morgana : Role.assassin,
          Role.loyal,
        ],
        styles: List.filled(7, null),
        mySeat: 0,
        winner: '正義',
        result: '',
        proposals: proposals,
        history: history,
        statements: statements,
        sources: const {},
        decisions: const {},
        cardsBySeat: const {},
        ladyChecks: lady,
        assassinTarget: null,
        expansions: const ExpansionSettings(lady: true));

ProposalRecord proposal(int quest, int attempt, int leader, List<int> team,
        {required bool myVote}) =>
    ProposalRecord(
        quest: quest,
        attempt: attempt,
        leader: leader,
        team: team,
        votes: [myVote, true, true, true, true, true, true]);

DiscussionStatement said(int quest, int attempt, String text,
        {int? target,
        DiscussionPosition? position,
        bool? claimedEvil,
        String? intent}) =>
    DiscussionStatement(
        speaker: 0,
        quest: quest,
        attempt: attempt,
        text: text,
        target: target,
        position: position,
        claimedEvil: claimedEvil,
        intent: intent);

MatchSummary summary(String id, Map<String, int>? traits,
        {List<String> personas = const ['kai']}) =>
    MatchSummary(
        id: id,
        endedAt: DateTime(2026, 11, 15),
        players: 7,
        myRole: Role.loyal,
        won: true,
        winner: '正義',
        difficulty: '高手',
        episodes: {for (final p in personas) p: const []},
        traits: traits);

void main() {
  test('a game is counted from the player\'s side at the time', () {
    final t = playerTraits(review(me: Role.loyal, proposals: [
      // off the team: backs a team with evil 3, turns down a clean one
      proposal(1, 1, 1, [1, 3], myVote: true),
      proposal(1, 2, 2, [2, 4], myVote: false),
      // leads a clean team
      proposal(1, 3, 0, [0, 2], myVote: true),
      // the fifth proposal tells nothing
      proposal(2, 5, 1, [1, 5], myVote: true),
    ], history: [
      QuestResult([0, 2], 0, true),
      QuestResult([1, 5], 1, false),
    ], statements: [
      said(1, 1, '3號可疑', target: 3, position: DiscussionPosition.suspect),
      said(1, 2, '5號是好人', target: 5, position: DiscussionPosition.defend),
      said(2, 5, '湖中女神查到5號是壞人', target: 5, claimedEvil: true),
    ], lady: const [
      LadyCheck(0, 5, 1)
    ]));
    expect(t[Trait.gamesGood], 1);
    expect(t[Trait.goodSawDirty], 1);
    expect(t[Trait.goodBackedDirty], 1);
    expect(t[Trait.goodSawClean], 1);
    expect(t[Trait.goodBackedClean], isNull);
    expect(t[Trait.goodLeads], 1);
    expect(t[Trait.goodLeadsClean], 1);
    expect(t[Trait.goodCalls], 2);
    expect(t[Trait.goodCallsRight], 1);
    expect(t[Trait.ladyClaims], 1);
    expect(t[Trait.ladyClaimsTrue], 1);
    expect(t[Trait.evilCalls], isNull);
  });

  test('as evil: misleading calls, a false Percival claim, Merlin apart', () {
    final evil = playerTraits(review(me: Role.assassin, proposals: [
      proposal(1, 1, 1, [1, 2], myVote: false),
    ], statements: [
      said(1, 1, '2號可疑', target: 2, position: DiscussionPosition.suspect),
      said(1, 1, '3號沒問題', target: 3, position: DiscussionPosition.defend),
      said(1, 1, '我是派西維爾', intent: DiscussionStatement.percivalClaim),
    ]));
    expect(evil[Trait.gamesEvil], 1);
    expect(evil[Trait.evilCalls], 2);
    expect(evil[Trait.evilCallsMisleading], 2);
    expect(evil[Trait.evilSawClean], 1);
    expect(evil[Trait.evilBackedClean], isNull);
    expect(evil[Trait.percivalClaims], 1);
    expect(evil[Trait.percivalClaimsTrue], isNull);
    final merlin = playerTraits(review(me: Role.merlin, proposals: [
      proposal(1, 1, 0, [0, 2], myVote: true),
    ]));
    expect(merlin[Trait.gamesMerlin], 1);
    expect(merlin[Trait.merlinLeads], 1);
    expect(merlin[Trait.merlinLeadsClean], 1);
    expect(merlin[Trait.goodLeads], isNull);
  });

  test('older games count less, and only those the bot sat in', () {
    final past = [
      summary('new', {Trait.goodCalls: 4, Trait.goodCallsRight: 4}),
      for (var i = 0; i < 9; i++) summary('filler$i', const {}),
      summary('old', {Trait.goodCalls: 4, Trait.goodCallsRight: 0}),
      summary('elsewhere', {Trait.goodCalls: 10, Trait.goodCallsRight: 0},
          personas: const ['mia']),
      summary('unsaved', null),
    ];
    final kai = PlayerModel.of('kai', past)!;
    final calls = kai.rate(Trait.goodCallsRight);
    // the newest counts 1, the one ten games back a half
    expect(calls.events, closeTo(4 + 2, 1e-9));
    expect(calls.games, closeTo(1.5, 1e-9));
    const prior = 4 * .72;
    expect(calls.value, closeTo((4 + prior) / (6 + 4), 1e-9));
    expect(calls.confidence, closeTo(1.5 / 6.5, 1e-9));
    // nothing recorded: the population rate, and not shown
    final lady = kai.rate(Trait.ladyClaimsTrue);
    expect(lady.value, .8);
    expect(lady.known, isFalse);
    expect(playerModelLines(kai).single, startsWith('你當好人時，點名說中'));
    // a bot that never played with the player knows nothing
    expect(PlayerModel.of('dawei', past), isNull);
    expect(playerModelLines(null), isEmpty);
    // the weighted games together, forgetting included
    expect(
        kai.gamesTogether,
        closeTo(
            [for (var i = 0; i < 11; i++) pow(.5, i / 10)]
                .fold(0.0, (a, b) => a + b),
            1e-9));
  });

  test('a game saved before the habits were counted gets them counted once',
      () async {
    final storage = MemoryMatchStorage();
    final repository = MatchRepository(storage: storage);
    final match = MatchArchive(
        id: 'g1',
        endedAt: DateTime(2026, 11, 14),
        difficulty: '高手',
        personas: [null, 'kai', null, null, null, null, null],
        review: review(me: Role.loyal, statements: [
          said(1, 1, '3號可疑', target: 3, position: DiscussionPosition.suspect)
        ], proposals: [
          proposal(1, 1, 1, [1, 3], myVote: false)
        ]));
    await repository.save(match);
    // make the saved index look like it came from the version before
    const key = 'avalon.solo.matches.v1';
    final index = jsonDecode(storage.values[key]!) as List;
    (index.single as Map).remove('traits');
    // and one more game whose full record is gone
    index.add(summary('lost', null).toMap()..remove('traits'));
    storage.values[key] = jsonEncode(index);

    final list = await repository.summaries();
    expect(list.first.traits![Trait.goodCallsRight], 1);
    expect(list.last.traits, isEmpty);
    // written back: the next read does not count again
    final saved = jsonDecode(storage.values[key]!) as List;
    expect(saved.every((s) => (s as Map).containsKey('traits')), isTrue);
    expect(PlayerModel.of('kai', list)!.rate(Trait.goodCallsRight).games, 1);
  });
}
