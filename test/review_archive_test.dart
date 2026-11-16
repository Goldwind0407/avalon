import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/game_review.dart';
import 'package:avalon_shadow_council/features/solo/review_export.dart';
import 'package:avalon_shadow_council/features/solo/memory/match_archive.dart';
import 'package:avalon_shadow_council/features/solo/memory/player_model.dart';
import 'package:avalon_shadow_council/features/solo/solo_session.dart';

/// Seven players. Seat 0 is the player; seat 3 is evil, seat 5 the Assassin.
GameReview review({
  List<Role>? roles,
  String? winner = '正義',
  required List<ProposalRecord> proposals,
  required List<QuestResult> history,
  List<DiscussionStatement> statements = const [],
  Map<int, Map<int, bool>> cards = const {},
  ExpansionSettings expansions = const ExpansionSettings(),
  List<bool> switchedDuring = const [],
  bool switchedAtEnd = false,
}) =>
    GameReview.build(
        players: [for (var i = 0; i < 7; i++) 'p$i'],
        roles: roles ??
            const [
              Role.loyal,
              Role.merlin,
              Role.loyal,
              Role.minion,
              Role.percival,
              Role.assassin,
              Role.loyal,
            ],
        styles: List.filled(7, null),
        mySeat: 0,
        winner: winner,
        result: '',
        proposals: proposals,
        history: history,
        statements: statements,
        sources: const {},
        decisions: const {},
        cardsBySeat: cards,
        ladyChecks: const [],
        assassinTarget: null,
        expansions: expansions,
        switchedDuring: switchedDuring,
        switchedAtEnd: switchedAtEnd);

ProposalRecord passed(int quest, int leader, List<int> team,
        {int attempt = 1}) =>
    ProposalRecord(
        quest: quest,
        attempt: attempt,
        leader: leader,
        team: team,
        votes: List.filled(7, true));

GameReview reread(GameReview r) => reviewFromMap(
    jsonDecode(jsonEncode(reviewToMap(r))) as Map<String, dynamic>);

void main() {
  test('a saved review reads back every field of every statement', () {
    final said = [
      DiscussionStatement(
          speaker: 0,
          quest: 1,
          generation: 3,
          attempt: 1,
          text: '湖中女神驗出2號是好人所以5號是壞人',
          target: 1,
          claimedEvil: false,
          switched: true,
          position: DiscussionPosition.defend,
          certainty: DiscussionCertainty.certain,
          supportsTeam: false,
          team: [0, 2],
          intent: 'interpretLady',
          topic: 'lady/1',
          questionTo: 4,
          replyTo: 7,
          quotedFrom: 2,
          claimedOriginalSuccess: true,
          originalCardQuest: 1,
          claimsOpeningKnowledge: true,
          evidenceIds: ['g3/ladyUse/q1/0/1']),
      DiscussionStatement(
          speaker: 0,
          quest: 1,
          attempt: 1,
          text: '湖中女神驗出2號是好人所以5號是壞人',
          target: 4,
          position: DiscussionPosition.suspect,
          intent: 'accuse',
          continues: true),
    ];
    final r = review(proposals: [
      passed(1, 0, [0, 2])
    ], history: [
      QuestResult([0, 2], 0, true)
    ], statements: said);
    final back = reread(r).quests.single.proposals.single.lines;
    expect(back, hasLength(2));
    for (final (i, line) in back.indexed) {
      final a = said[i], b = line.statement;
      expect([
        b.speaker,
        b.quest,
        b.generation,
        b.attempt,
        b.text,
        b.target,
        b.claimedEvil,
        b.switched,
        b.position,
        b.certainty,
        b.supportsTeam,
        b.team,
        b.intent,
        b.topic,
        b.questionTo,
        b.replyTo,
        b.quotedFrom,
        b.claimedOriginalSuccess,
        b.originalCardQuest,
        b.claimsOpeningKnowledge,
        b.continues,
        b.evidenceIds,
      ], [
        a.speaker,
        a.quest,
        a.generation,
        a.attempt,
        a.text,
        a.target,
        a.claimedEvil,
        a.switched,
        a.position,
        a.certainty,
        a.supportsTeam,
        a.team,
        a.intent,
        a.topic,
        a.questionTo,
        a.replyTo,
        a.quotedFrom,
        a.claimedOriginalSuccess,
        a.originalCardQuest,
        a.claimsOpeningKnowledge,
        a.continues,
        a.evidenceIds,
      ], reason: 'statement $i');
    }
    // the reopened review reads the player's line the same way
    final lines = reread(r).quests.single.proposals.single.lines;
    expect(lineReading(lines, 0),
        lineReading(r.quests.single.proposals.single.lines, 0));
    expect(lineReading(lines, 0), contains('湖中女神查到2號是好人'));
    expect(lineReading(lines, 0), contains('懷疑5號'));
  });

  test('a save from before these fields still reads', () {
    final r = review(proposals: [
      passed(1, 0, [0, 2])
    ], history: [
      QuestResult([0, 2], 0, true)
    ], statements: [
      DiscussionStatement(speaker: 0, quest: 1, attempt: 1, text: '我支持這隊')
    ]);
    final map = jsonDecode(jsonEncode(reviewToMap(r))) as Map<String, dynamic>;
    final line = ((((map['quests'] as List).single as Map)['proposals'] as List)
        .single as Map)['lines'] as List;
    line[0] = {'by': 0, 'q': 1, 'a': 1, 'text': '我支持這隊'};
    map.remove('switches');
    final back = reviewFromMap(map).quests.single.proposals.single.lines.single;
    expect(back.statement.continues, isFalse);
    expect(back.statement.evidenceIds, isEmpty);
    expect(back.statement.certainty, DiscussionCertainty.tentative);
  });

  group('a Lancelot who switched', () {
    // the player is the good Lancelot; the switch came before quest 3
    final roles = [
      Role.lancelotGood,
      Role.merlin,
      Role.loyal,
      Role.lancelotEvil,
      Role.percival,
      Role.assassin,
      Role.loyal,
    ];
    GameReview switched({String winner = '邪惡'}) => review(
        roles: roles,
        winner: winner,
        expansions: const ExpansionSettings(lancelot: 1),
        switchedDuring: [false, false, true],
        switchedAtEnd: true,
        proposals: [
          passed(1, 1, [1, 2]),
          passed(2, 2, [1, 2, 4]),
          passed(3, 4, [0, 1, 2, 4]),
        ],
        history: [
          QuestResult([1, 2], 0, true),
          QuestResult([1, 2, 4], 0, true),
          QuestResult([0, 1, 2, 4], 1, false),
        ]);

    test('wins and loses with the side he ended on', () {
      expect(switched().iWon, isTrue);
      expect(switched(winner: '正義').iWon, isFalse);
      expect(reread(switched()).iWon, isTrue);
    });

    test('is judged on each quest by the side he played for then', () {
      final r = switched();
      expect(r.evilIn(0, 1), isFalse);
      expect(r.evilIn(0, 3), isTrue);
      expect(r.evilIn(3, 1), isTrue);
      expect(r.evilIn(3, 3), isFalse);
      // the timeline survives a save
      final back = reread(r);
      expect([for (var q = 1; q <= 3; q++) back.evilIn(0, q)],
          [false, false, true]);
    });
  });

  group('who gets the blame for a quest', () {
    // the player is evil (minion) here, seat 2 a good bot who backs them
    final roles = [
      Role.minion,
      Role.merlin,
      Role.loyal,
      Role.loyal,
      Role.percival,
      Role.assassin,
      Role.loyal,
    ];
    List<EpisodeKind> episodes(QuestResult q, Map<int, bool> cards) =>
        episodesWith(
            review(roles: roles, winner: null, proposals: [
              passed(1, 2, q.team)
            ], history: [
              q
            ], cards: {
              for (final c in cards.entries) c.key: {1: c.value}
            }),
            2);

    test('the player failed it: "it went wrong in your hands"', () {
      expect(episodes(QuestResult([0, 2], 1, false), {0: false, 2: true}),
          contains(EpisodeKind.fooled));
    });

    test('the quest survived the Fail: only "I let you through"', () {
      // a quest that needs two Fails
      final kinds =
          episodes(QuestResult([0, 2, 3, 6], 1, true), {0: false, 2: true});
      expect(kinds, contains(EpisodeKind.letYouThrough));
      expect(kinds, isNot(contains(EpisodeKind.fooled)));
    });

    test('someone else failed it, or the sword did', () {
      // the player played Success; the Fail came from elsewhere
      final kinds = episodes(
          QuestResult([0, 2, 5], 1, false,
              excaliburHolder: 5, excaliburTarget: 0),
          {0: true, 2: true, 5: true});
      expect(kinds, contains(EpisodeKind.letYouThrough));
      expect(kinds, isNot(contains(EpisodeKind.fooled)));
    });

    test('a bot that did not fail the quest only slipped past the player', () {
      // the player is good and backs the evil bot in seat 5
      final kinds = episodesWith(
          review(winner: null, proposals: [
            passed(1, 0, [0, 5])
          ], history: [
            QuestResult([0, 5], 0, true)
          ], cards: {
            0: {1: true},
            5: {1: true}
          }),
          5);
      expect(kinds, contains(EpisodeKind.slippedPastYou));
      expect(kinds, isNot(contains(EpisodeKind.usedYou)));
    });
  });

  test('a Lady check is about the sides when it was made', () {
    // a switch card on quest 3: a check after quest 2 is from before it
    final states = switchStates([null, null, true, null, null], 4);
    expect(states, [false, false, true, true]);
    expect(states[2 - 1], isFalse);
    // variant two lays out cards for quests not yet played: only those
    // played count
    expect(switchStates([false, true, false, true, false], 2), [false, true]);
  });

  test('a Fail turned over by the sword was not what lost the quest', () {
    // the player (evil) played Fail but the sword made it a Success;
    // another evil player's Fail lost the quest
    final r = review(
        roles: const [
          Role.minion,
          Role.merlin,
          Role.loyal,
          Role.assassin,
          Role.percival,
          Role.loyal,
          Role.loyal,
        ],
        winner: null,
        proposals: [
          passed(1, 2, [0, 2, 3])
        ],
        history: [
          QuestResult([0, 2, 3], 1, false,
              excaliburHolder: 2, excaliburTarget: 0)
        ],
        cards: {
          0: {1: false},
          2: {1: true},
          3: {1: false}
        });
    final kinds = episodesWith(r, 2);
    expect(kinds, contains(EpisodeKind.letYouThrough));
    expect(kinds, isNot(contains(EpisodeKind.fooled)));
  });

  group('an old Lancelot game without its switch timeline', () {
    final roles = [
      Role.lancelotGood,
      Role.merlin,
      Role.loyal,
      Role.lancelotEvil,
      Role.percival,
      Role.assassin,
      Role.loyal,
    ];
    GameReview old() {
      final r = review(
          roles: roles,
          winner: '邪惡',
          expansions: const ExpansionSettings(lancelot: 1),
          switchedDuring: [false, false, true],
          switchedAtEnd: true,
          proposals: [
            passed(1, 1, [0, 1])
          ],
          history: [
            QuestResult([0, 1], 0, true)
          ],
          statements: [
            DiscussionStatement(
                speaker: 0,
                quest: 1,
                attempt: 1,
                text: '3號可疑',
                target: 2,
                position: DiscussionPosition.suspect)
          ]);
      final map =
          jsonDecode(jsonEncode(reviewToMap(r))) as Map<String, dynamic>;
      map.remove('switches');
      map.remove('switchedEnd');
      return reviewFromMap(map);
    }

    test('is not guessed: the win is unknown and nothing is learned', () {
      final r = old();
      expect(r.sidesKnown, isFalse);
      expect(r.sideKnown(0), isFalse);
      expect(r.sideKnown(2), isTrue);
      final match = MatchArchive(
          id: 'old',
          endedAt: DateTime(2026, 11, 1),
          difficulty: '高手',
          personas: [null, 'kai', 'mia', 'zhe', null, null, null],
          review: r);
      expect(match.summary.won, isNull);
      // the review and its text say so too, instead of a guessed result
      expect(r.outcome, isNull);
      expect(reviewText(r), contains('勝負不明'));
      expect(reviewText(r), isNot(contains('你輸了')));
      expect(reviewText(r), isNot(contains('你贏了')));
      expect(r.scores.single.value, '—');
      expect(match.summary.traits, isEmpty);
      // nothing that depends on the player's side is remembered
      expect(match.summary.episodes['mia'], isEmpty);
      expect(playerTraits(r), isEmpty);
    });

    test('a game saved with the timeline is told normally', () {
      final match = MatchArchive(
          id: 'new',
          endedAt: DateTime(2026, 11, 1),
          difficulty: '高手',
          personas: [null, 'kai', 'mia', 'zhe', null, null, null],
          review: reread(review(
              roles: roles,
              winner: '邪惡',
              expansions: const ExpansionSettings(lancelot: 1),
              switchedDuring: [false],
              switchedAtEnd: true,
              proposals: [
                passed(1, 1, [0, 1])
              ],
              history: [
                QuestResult([0, 1], 0, true)
              ])));
      expect(match.review.sidesKnown, isTrue);
      expect(match.summary.won, isTrue);
    });
  });

  test('a player who switched sides is described by the side at the time', () {
    // the player led a clean team as good, then switched and ended evil
    final r = review(
        roles: const [
          Role.lancelotGood,
          Role.merlin,
          Role.loyal,
          Role.lancelotEvil,
          Role.percival,
          Role.assassin,
          Role.loyal,
        ],
        winner: '邪惡',
        expansions: const ExpansionSettings(lancelot: 1),
        switchedDuring: [false, false, true],
        switchedAtEnd: true,
        proposals: [
          passed(1, 0, [0, 1])
        ],
        history: [
          QuestResult([0, 1], 0, true)
        ]);
    expect(r.switchedSides, isTrue);
    final lead = r.scores.firstWhere((s) => s.title == '當隊長');
    expect(lead.value, '1／1');
    expect(lead.detail, contains('符合你當時陣營'));
    expect(lead.detail, isNot(contains('有壞人上隊。')));
  });
}
