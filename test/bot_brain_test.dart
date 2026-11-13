import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_difficulty.dart';
import 'package:avalon_shadow_council/features/solo/bot_observation.dart';
import 'package:avalon_shadow_council/features/solo/bot_style.dart';

BotObservation view(
        {Role role = Role.loyal,
        bool evil = false,
        int seat = 0,
        int count = 7,
        int rejects = 0,
        int failsRequired = 1,
        bool switched = false,
        List<int> visible = const [],
        List<QuestResult> history = const [],
        List<BotFact> facts = const [],
        Map<int, bool> ownCards = const {},
        ExpansionSettings expansions = const ExpansionSettings(),
        List<DiscussionStatement> statements = const [],
        List<int> team = const [0, 1]}) =>
    BotObservation(
        seat: seat,
        role: role,
        evil: evil,
        count: count,
        leader: 0,
        quest: history.length + 1,
        rejections: rejects,
        failsRequired: failsRequired,
        expansions: expansions,
        switched: switched,
        visible: visible,
        team: team,
        history: history,
        proposals: const [],
        ladyPast: const [0],
        facts: facts,
        statements: statements,
        ownCards: ownCards);

void main() {
  test('unknown-seat prior deducts self and authorized known seats', () {
    final brain = BotBrain(Random(1));
    expect(brain.suspicion(view(count: 5))[1], .5);
    expect(
        brain.suspicion(view(count: 5, role: Role.minion, evil: true))[1], .25);
    final merlin =
        brain.suspicion(view(count: 5, role: Role.merlin, visible: [1]));
    expect(merlin[1], 1);
    expect(merlin[2], closeTo(1 / 3, .000001));
  });
  test(
      'designated known allies supply both required Fail cards without random hiding',
      () {
    for (var seed = 0; seed < 40; seed++) {
      final brain = BotBrain(Random(seed));
      expect(
          brain.questCard(view(
              role: Role.assassin,
              evil: true,
              visible: [1],
              team: [0, 1, 2],
              failsRequired: 2)),
          isFalse);
      expect(
          brain.questCard(view(
              seat: 1,
              role: Role.minion,
              evil: true,
              visible: [0],
              team: [0, 1, 2],
              failsRequired: 2)),
          isFalse);
      expect(
          brain.questCard(view(
              seat: 2,
              role: Role.minion,
              evil: true,
              visible: [0, 1],
              team: [0, 1, 2],
              failsRequired: 2)),
          isTrue);
    }
  });
  test(
      'sword compares result utility, can decline, and accounts for own submitted card',
      () {
    final brain = BotBrain(Random(1));
    expect(brain.swordTarget(view(role: Role.merlin, visible: [1])), 1);
    expect(brain.swordTarget(view(role: Role.minion, evil: true, visible: [1])),
        isNull);
    expect(
        brain.swordTarget(view(
            role: Role.merlin,
            visible: [1],
            failsRequired: 2,
            ownCards: {1: true})),
        isNull);
    expect(
        brain.swordTarget(view(
            role: Role.minion,
            evil: true,
            failsRequired: 2,
            ownCards: {1: false})),
        1);
  });
  test(
      'forced Fail by own Lancelot is a constraint in risk, not an 85 percent guess',
      () {
    final brain = BotBrain(Random(1));
    final o = view(
        role: Role.lancelotGood,
        evil: true,
        switched: true,
        expansions: const ExpansionSettings(lancelot: 2));
    expect(brain.teamRisk(o, o.team), 1);
  });
  test(
      'fixed Percival candidates do not lose private Lady certainty on a Lancelot switch',
      () {
    final brain = BotBrain(Random(1));
    expect(
        brain.suspicion(view(
            role: Role.percival,
            visible: [1, 2],
            switched: true,
            expansions: const ExpansionSettings(lancelot: 1),
            facts: [
              BotFact(
                  owner: 0,
                  generation: 0,
                  quest: 1,
                  target: 1,
                  switched: false,
                  evil: false)
            ]))[1],
        0);
  });
  test('legal cards follow current allegiance and forced-Fail Lancelot variant',
      () {
    final brain = BotBrain(Random(1));
    for (var i = 0; i < 30; i++) {
      expect(
          brain.questCard(view(
              role: Role.lancelotEvil,
              evil: false,
              switched: true,
              expansions: const ExpansionSettings(lancelot: 2))),
          isTrue);
      expect(
          brain.questCard(view(
              role: Role.lancelotGood,
              evil: true,
              switched: true,
              expansions: const ExpansionSettings(lancelot: 2))),
          isFalse);
    }
  });
  test('Percival candidates stay ambiguous and Oberon has no teammate facts',
      () {
    final brain = BotBrain(Random(1));
    final p = brain.suspicion(view(role: Role.percival, visible: [1, 2]));
    expect(p[1], p[2]);
    final oberon = brain.suspicion(view(role: Role.oberon, evil: true));
    expect(oberon.skip(1).toSet(), hasLength(1));
  });
  test(
      'a successful two-Fail quest still adds evidence; sword-created failure does not',
      () {
    final brain = BotBrain(Random(1));
    final base = brain.suspicion(view())[1];
    expect(
        brain.suspicion(view(history: [
          QuestResult([1, 2, 3, 4], 1, true)
        ]))[1],
        greaterThan(base));
    expect(
        brain.suspicion(view(history: [
          QuestResult([1, 2, 3], 1, false,
              excaliburHolder: 2, excaliburTarget: 1)
        ]))[1],
        base);
    final ownFail =
        brain.suspicion(view(role: Role.minion, evil: true, history: [
      QuestResult([0, 1], 1, false)
    ], ownCards: {
      1: false
    }));
    // the partner's Success is no proof of anything, and never raises doubt
    expect(
        ownFail[1],
        lessThanOrEqualTo(
            brain.suspicion(view(role: Role.minion, evil: true))[1]));
  });
  test('Lady evidence ages across a switch; another player claim is not a fact',
      () {
    final brain = BotBrain(Random(1));
    final fact = BotFact(
        owner: 0,
        generation: 0,
        quest: 1,
        target: 2,
        switched: false,
        evil: false);
    expect(brain.suspicion(view(facts: [fact]))[2], 0);
    expect(
        brain.suspicion(view(
            facts: [fact],
            switched: true,
            expansions: const ExpansionSettings(lancelot: 1)))[2],
        .35);
    expect(
        brain.suspicion(view(statements: [
          DiscussionStatement(
              speaker: 1,
              quest: 1,
              target: 2,
              claimedEvil: false,
              text: '我宣稱他是好人')
        ]))[2],
        greaterThan(.1));
  });
  test('fifth rejection pressure and double-Fail risk are considered', () {
    final brain = BotBrain(Random(2));
    expect(brain.vote(view(rejects: 4)), isTrue);
    // a minority cannot stop the fifth proposal; rejecting only exposes evil
    expect(
        brain.vote(view(rejects: 4, role: Role.assassin, evil: true)), isTrue);
    expect(brain.teamRisk(view(failsRequired: 2), [1, 2, 3]),
        lessThan(brain.teamRisk(view(), [1, 2, 3])));
  });
  test('speech uses public evidence, not the source of private role knowledge',
      () {
    final text = BotBrain(Random(2))
        .speech(view(role: Role.merlin, visible: [2, 3]), false)
        .text;
    for (final secret in ['梅林', '我看見', '邪惡同伴', '莫甘娜']) {
      expect(text, isNot(contains(secret)));
    }
  });
  test(
      'snapshots copy caller collections and equivalent views make the same decision',
      () {
    final seats = <int>[1, 2];
    final a = view(visible: seats, role: Role.merlin);
    seats.clear();
    expect(a.visible, [1, 2]);
    expect(() => a.visible.add(3), throwsUnsupportedError);
    final b = view(visible: [1, 2], role: Role.merlin);
    expect(BotBrain(Random(44)).chooseTeam(a, 3),
        BotBrain(Random(44)).chooseTeam(b, 3));
  });
  test('a good player on a failed pair knows the partner is evil', () {
    final brain = BotBrain(Random(1));
    final p = brain.suspicion(view(count: 5, history: [
      QuestResult([0, 1], 1, false)
    ], ownCards: {
      1: true
    }));
    expect(p[1], 1);
    // one evil seat is left among the other three
    expect(p[2], closeTo(1 / 3, .1));
    // an outsider only knows one of the pair is evil
    final outside = brain.suspicion(view(count: 5, seat: 4, history: [
      QuestResult([0, 1], 1, false)
    ]));
    expect(outside[0], greaterThan(.5));
    expect(outside[0], lessThan(1));
    expect(outside[0], outside[1]);
    // once every evil seat is known, everyone else is cleared
    final solved = brain.suspicion(view(count: 5, history: [
      QuestResult([0, 1], 1, false),
      QuestResult([0, 2], 1, false)
    ], ownCards: {
      1: true,
      2: true
    }));
    expect([solved[1], solved[2], solved[3], solved[4]], [1, 1, 0, 0]);
  });
  test('a clean quest makes its members more trusted', () {
    final brain = BotBrain(Random(1));
    final p = brain.suspicion(view(history: [
      QuestResult([1, 2, 3], 0, true)
    ]));
    expect(p[1], lessThan(p[4]));
  });
  test('an evil leader does not stack the team with allies', () {
    for (var seed = 0; seed < 30; seed++) {
      final team = BotBrain(Random(seed)).chooseTeam(
          view(role: Role.assassin, evil: true, visible: [1, 2]), 3);
      expect(team.where([0, 1, 2].contains).length, 1, reason: '$team');
    }
  });
  test('a lone Fail is not wasted on a quest that needs two', () {
    for (var seed = 0; seed < 30; seed++) {
      // every ally is known and none is on the team: nobody adds a second
      expect(
          BotBrain(Random(seed)).questCard(view(
              role: Role.assassin,
              evil: true,
              visible: [5, 6],
              team: [0, 1, 2, 3],
              failsRequired: 2)),
          isTrue);
    }
  });
  test('evil sometimes goes along with a clean team; good refuses known evil',
      () {
    var approvals = 0;
    for (var seed = 0; seed < 200; seed++) {
      // after the first quest (before it nobody objects, see below)
      if (BotBrain(Random(seed))
          .vote(view(role: Role.assassin, evil: true, visible: [
        5,
        6
      ], team: [
        1,
        2
      ], history: [
        QuestResult([3, 4], 0, true)
      ]))) {
        approvals++;
      }
    }
    expect(approvals, inInclusiveRange(60, 160));
    for (var rejects = 0; rejects < 4; rejects++) {
      expect(
          BotBrain(Random(1)).vote(view(
              role: Role.merlin,
              visible: [1],
              team: [0, 1],
              rejects: rejects,
              history: [
                QuestResult([2, 3], 0, true)
              ])),
          isFalse);
    }
  });
  group('styles', () {
    int count(bool Function(BotBrain) act, BotStyle style) => [
          for (var seed = 0; seed < 400; seed++)
            if (act(BotBrain(Random(seed), style: style))) 1
        ].length;

    test('every computer player gets a style, as varied as possible', () {
      final dealt = BotStyle.deal(9, Random(1));
      expect(dealt, isNot(contains(BotStyle.balanced)));
      expect(dealt.take(6).toSet(), hasLength(6));
    });
    test('cautious players approve less than impulsive ones', () {
      // a team without this seat, after one failed quest by other players
      final o = view(count: 7, team: [
        1,
        2,
        3
      ], history: [
        QuestResult([4, 5], 1, false)
      ]);
      bool approves(BotBrain b) => b.vote(o);
      var cautious = 0, impulsive = 0;
      for (var rejects = 0; rejects < 4; rejects++) {
        final v = view(
            count: 7,
            team: [1, 2, 3],
            rejects: rejects,
            history: [
              QuestResult([4, 5], 1, false)
            ]);
        if (BotBrain(Random(1), style: BotStyle.cautious).vote(v)) cautious++;
        if (BotBrain(Random(1), style: BotStyle.impulsive).vote(v)) {
          impulsive++;
        }
      }
      expect(impulsive, greaterThan(cautious));
      expect(count(approves, BotStyle.cautious),
          lessThanOrEqualTo(count(approves, BotStyle.impulsive)));
    });
    test('an actor hides and blends in more than an aggressive player', () {
      final quest = view(role: Role.minion, evil: true, visible: [
        5,
        6
      ], team: [
        0,
        1
      ], history: [
        QuestResult([1, 2], 0, true)
      ]);
      bool success(BotBrain b) => b.questCard(quest);
      expect(count(success, BotStyle.actor),
          greaterThan(count(success, BotStyle.aggressive) + 40));
      final clean = view(role: Role.minion, evil: true, visible: [
        5,
        6
      ], team: [
        1,
        2
      ], history: [
        QuestResult([3, 4], 0, true)
      ]);
      bool approves(BotBrain b) => b.vote(clean);
      expect(count(approves, BotStyle.actor),
          greaterThan(count(approves, BotStyle.aggressive) + 80));
    });
    test('Merlin sometimes votes like a servant, never when a loss is near',
        () {
      // seat 1 is evil to Merlin; an ordinary servant would let this pass
      // seat 2 came back from a clean quest, so a servant trusts him; only
      // Merlin knows he is evil
      final o = view(role: Role.merlin, visible: [
        2
      ], team: [
        0,
        2
      ], history: [
        QuestResult([2, 3], 0, true)
      ]);
      bool approves(BotBrain b) => b.vote(o);
      // with nothing lost yet he mostly plays along; less after a failure
      final early = count(approves, BotStyle.actor);
      expect(early, inInclusiveRange(240, 380));
      final wary = view(role: Role.merlin, visible: [
        1
      ], team: [
        0,
        1
      ], history: [
        QuestResult([2, 3], 1, false)
      ]);
      expect(count((b) => b.vote(wary), BotStyle.actor), lessThan(early - 60));
      expect(count(approves, BotStyle.balanced), 0);
      final late = view(role: Role.merlin, visible: [
        1
      ], team: [
        0,
        1
      ], history: [
        QuestResult([2, 3], 1, false),
        QuestResult([4, 5, 6], 1, false)
      ]);
      expect(count((b) => b.vote(late), BotStyle.actor), 0);
    });
    test('Percival follows the candidate he trusts as leader', () {
      // candidate 1 has led a clean quest, candidate 2 a failed one
      BotObservation led(int leader) => BotObservation(
              seat: 0,
              role: Role.percival,
              evil: false,
              count: 7,
              leader: leader,
              quest: 3,
              rejections: 0,
              failsRequired: 1,
              expansions: const ExpansionSettings(),
              switched: false,
              visible: const [
                1,
                2
              ],
              team: const [
                0,
                3,
                5
              ],
              history: [
                QuestResult([1, 3], 0, true),
                QuestResult([2, 6, 4], 1, false)
              ],
              proposals: const [],
              ladyPast: const [],
              facts: const [],
              statements: const [],
              ownCards: const {});
      final brain = BotBrain(Random(1));
      final p = brain.suspicion(led(1));
      expect(p[1], lessThan(p[2]));
      expect(brain.vote(led(1)), isTrue);
      expect(brain.vote(led(2)), isFalse);
    });
  });
  group('roles and levels', () {
    ProposalRecord proposal(
            int quest, int leader, List<int> team, List<bool> votes,
            {int attempt = 1}) =>
        ProposalRecord(
            quest: quest,
            attempt: attempt,
            leader: leader,
            team: team,
            votes: votes);
    BotObservation seen(Role role,
            {bool evil = false,
            List<int> visible = const [],
            List<QuestResult> history = const [],
            List<ProposalRecord> proposals = const [],
            List<int> team = const [0, 1],
            List<int> ladyPast = const [0],
            int leader = 0,
            GamePhase phase = GamePhase.discussion}) =>
        BotObservation(
            seat: 0,
            role: role,
            evil: evil,
            count: 7,
            leader: leader,
            quest: history.length + 1,
            rejections: 0,
            failsRequired: 1,
            expansions: const ExpansionSettings(),
            switched: false,
            visible: visible,
            team: team,
            history: history,
            proposals: proposals,
            ladyPast: ladyPast,
            facts: const [],
            statements: const [],
            ownCards: const {},
            phase: phase);

    test('Percival: one candidate proven evil makes the other Merlin', () {
      final p = BotBrain(Random(1)).suspicion(seen(Role.percival, visible: [
        1,
        2
      ], history: [
        QuestResult([0, 1], 1, false)
      ]));
      expect(p[1], 1);
      expect(p[2], 0);
    });
    test('the Assassin counts himself as evil on a team, by level', () {
      // seat 3 turned down two early teams with evil on them and led a clean
      // one; seat 4 approved them
      final votes = [true, true, true, false, true, true, true];
      final o = seen(Role.assassin,
          evil: true,
          visible: [1],
          phase: GamePhase.assassination,
          history: [
            QuestResult([3, 5], 0, true),
            QuestResult([3, 5, 6], 0, true),
            QuestResult([3, 4, 5], 0, true)
          ],
          proposals: [
            proposal(1, 2, [0, 2], votes),
            proposal(1, 3, [3, 5], List.filled(7, true), attempt: 2),
            proposal(2, 4, [1, 4, 5], votes),
            proposal(2, 5, [3, 5, 6], List.filled(7, true), attempt: 2),
            proposal(3, 6, [3, 4, 5], List.filled(7, true)),
          ]);
      int hits(BotDifficulty level) => [
            for (var seed = 0; seed < 300; seed++)
              if (BotBrain(Random(seed), difficulty: level).assassinate(o) == 3)
                1
          ].length;
      expect(
          hits(BotDifficulty.expert), greaterThan(hits(BotDifficulty.normal)));
      expect(
          hits(BotDifficulty.normal), greaterThan(hits(BotDifficulty.novice)));
      expect(hits(BotDifficulty.expert), greaterThan(270));
    });
    test('Morgana likes to lead the players the table already trusts', () {
      // seats 4 and 5 came back from a clean first quest
      final o = seen(Role.morgana, evil: true, visible: [
        1,
        2
      ], history: [
        QuestResult([4, 5], 0, true)
      ]);
      int trusted(BotDifficulty level) => [
            for (var seed = 0; seed < 300; seed++)
              if (BotBrain(Random(seed), difficulty: level)
                  .chooseTeam(o, 2)
                  .any([4, 5].contains))
                1
          ].length;
      // a beginner picks a partner at random; posing as Merlin picks them
      expect(trusted(BotDifficulty.normal),
          greaterThan(trusted(BotDifficulty.novice) + 40));
      for (var seed = 0; seed < 50; seed++) {
        final team = BotBrain(Random(seed)).chooseTeam(o, 2);
        expect(team, contains(0));
        expect(team.any([1, 2].contains), isFalse);
      }
    });
    test('an evil Lady holder hands her to an ally about half the time', () {
      var ally = 0;
      for (var seed = 0; seed < 300; seed++) {
        final target = BotBrain(Random(seed))
            .ladyTarget(seen(Role.minion, evil: true, visible: [1, 2]));
        expect(target, isNot(0));
        if ([1, 2].contains(target)) ally++;
      }
      expect(ally, inInclusiveRange(100, 200));
      // Oberon knows no ally and simply looks for information
      expect(BotBrain(Random(1)).ladyTarget(seen(Role.oberon, evil: true)),
          isNot(0));
    });
    test('a beginner reasons less from a clean quest and may slip a vote', () {
      final o = seen(Role.loyal, history: [
        QuestResult([1, 2, 3], 0, true)
      ]);
      double gap(BotDifficulty level) {
        final p = BotBrain(Random(1), difficulty: level).suspicion(o);
        return p[4] - p[1];
      }

      expect(gap(BotDifficulty.novice), greaterThan(0));
      expect(gap(BotDifficulty.novice), lessThan(gap(BotDifficulty.normal)));
      expect(gap(BotDifficulty.normal), lessThan(gap(BotDifficulty.expert)));
      // Merlin sees evil on the team: only a beginner ever lets it through
      // by mistake (the balanced test style never disguises)
      final dirty = seen(Role.merlin, visible: [
        1
      ], history: [
        QuestResult([2, 3], 1, false),
        QuestResult([4, 5, 6], 1, false)
      ]);
      int slips(BotDifficulty level) => [
            for (var seed = 0; seed < 400; seed++)
              if (BotBrain(Random(seed), difficulty: level).vote(dirty)) 1
          ].length;
      expect(slips(BotDifficulty.normal), 0);
      expect(slips(BotDifficulty.novice), inInclusiveRange(5, 50));
    });
  });
  test('after a switch evil drops only Lancelot and keeps working together',
      () {
    BotObservation evil({int? lancelot, int failsRequired = 2}) =>
        BotObservation(
            seat: 0,
            role: Role.assassin,
            evil: true,
            count: 8,
            leader: 0,
            quest: 3,
            rejections: 0,
            failsRequired: failsRequired,
            expansions: const ExpansionSettings(lancelot: 1),
            switched: true,
            visible: const [1, 2],
            team: const [0, 1, 3, 4],
            history: [
              QuestResult([5, 6], 0, true),
              QuestResult([5, 6, 7], 0, true)
            ],
            proposals: const [],
            ladyPast: const [],
            facts: const [],
            statements: const [],
            ownCards: const {},
            loyalty: const [null, null, true, null, null],
            lancelotSeat: lancelot);
    final brain = BotBrain(Random(1));
    final known = brain.suspicion(evil(lancelot: 2));
    expect(known[1], 1);
    expect(known[2], 0);
    final unknown = brain.suspicion(evil());
    expect(unknown[1], lessThan(1));
    // the ally still on the team is a partner for the two Fails needed
    for (var seed = 0; seed < 20; seed++) {
      expect(BotBrain(Random(seed)).questCard(evil(lancelot: 2)), isFalse);
    }
    // a Lancelot seat that is not among the visible allies is refused
    expect(() => evil(lancelot: 5), throwsArgumentError);
  });
  test('before the first quest nobody has a reason to object', () {
    int approvals(BotObservation o, BotStyle style) => [
          for (var seed = 0; seed < 300; seed++)
            if (BotBrain(Random(seed), style: style).vote(o)) 1
        ].length;
    // evil goes along whatever its style
    final clean =
        view(role: Role.minion, evil: true, visible: [5, 6], team: [1, 2]);
    expect(approvals(clean, BotStyle.aggressive), greaterThan(250));
    // Merlin mostly lets a first team with evil on it through
    final merlin = view(role: Role.merlin, visible: [1], team: [0, 1]);
    expect(approvals(merlin, BotStyle.balanced), inInclusiveRange(150, 230));
    // and says a word without talking about records that do not exist
    final words = BotBrain(Random(1))
        .speech(view(role: Role.loyal, team: [1, 2]), true)
        .text;
    for (final record in ['紀錄', '投票', '第1次', '懷疑']) {
      expect(words, isNot(contains(record)));
    }
  });
}
