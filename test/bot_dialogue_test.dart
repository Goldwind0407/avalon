import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_observation.dart';
import 'package:avalon_shadow_council/features/solo/dialogue/bot_catalog.dart';
import 'package:avalon_shadow_council/features/solo/dialogue/bot_contract.dart';
import 'package:avalon_shadow_council/features/solo/dialogue/bot_dialogue_context.dart';

import 'package:avalon_shadow_council/features/solo/dialogue/bot_dialogue_planner.dart';
import 'support/bot_dialogue_fixtures.dart';

void main() {
  test('claiming most members changed requires more than half the team', () {
    final planner = plannerFor('G09');
    final history = [
      QuestResult([0, 1, 2], 0, true),
      QuestResult([0, 1, 2, 3], 1, false)
    ];
    say(planner,
        observe(count: 8, leader: 0, history: history, team: [0, 1, 4, 5]));
    expect(planner.lastTrace, isNull);
    say(planner,
        observe(count: 8, leader: 0, history: history, team: [0, 4, 5, 6]));
    expect(planner.lastTrace!.ruleId, 'G09');
  });
  test(
      'reusing last successful quest cites that quest rather than a more similar older failure',
      () {
    final planner = plannerFor('G08');
    final statement = say(
        planner,
        observe(leader: 0, team: [
          0,
          1,
          3
        ], history: [
          QuestResult([0, 1], 1, false),
          QuestResult([3, 4, 5], 0, true)
        ]));
    expect(planner.lastTrace!.ruleId, 'G08');
    expect(statement.evidenceIds, contains('g4/quest/q2'));
    expect(statement.evidenceIds, isNot(contains('g4/quest/q1')));
  });
  test(
      'activation manifest distinguishes guarded scenarios from dormant drafts',
      () {
    final supported = BotDialogueCatalog.bundled.rules
        .where((rule) =>
            BotDialogueContext(observe(), true, rule, (_) => .3, false)
                .hasRegisteredGuards)
        .map((r) => r.id)
        .toList();
    expect(supported, containsAll(['G16', 'G17', 'XLD03', 'XSW03', 'RLE01']));
    expect(supported, hasLength(104));
    expect(supported, contains('XSW04'));
    expect(supported, isNot(contains('G23')));
    // Exposes a useful rollout manifest without claiming every imported line
    // can already run; unsupported conditions must stay inactive.
    // ignore: avoid_print
    print(
        'Registered dialogue scenarios (${supported.length}): ${supported.join(', ')}');
  });
  test(
      'all draft roles, policies and placeholders compile into the canonical schema',
      () {
    final catalog = BotDialogueCatalog.bundled;
    expect(catalog.rules, hasLength(105));
    expect(catalog.rules.expand((r) => r.templates), hasLength(420));
    expect(catalog.rules.map((r) => r.id).toSet(), hasLength(105));
    expect(catalog.rules.firstWhere((r) => r.id == 'G07').policy,
        BotClaimPolicy.strategicOpinionBluff);
    expect(catalog.rules.map((r) => r.role).toSet(),
        containsAll(BotDialogueRole.values));
    for (final role in Role.values) {
      if (!role.isLancelot) {
        expect(BotDialogueRole.forPlayer(role, role.isEvil).name, role.name);
      }
    }
    expect(BotDialogueRole.forPlayer(Role.lancelotGood, true),
        BotDialogueRole.lancelotEvil);
    expect(BotDialogueRole.forPlayer(Role.lancelotEvil, false),
        BotDialogueRole.lancelotGood);
  });

  test('malformed catalog entries fail closed before any text is used', () {
    for (final override in [
      {'role': 'loyal_servant'},
      {'policy': 'unknown'},
      {'intent': 'unknown'},
      {'phase': 'unknown'},
      {'role': null},
      {'priority': 101},
      {
        'templates': ['{{privateRole}}']
      },
      {
        'templates': ['{{target_1}}']
      },
    ]) {
      expect(
          () => catalogOf([
                {...sourceRule('G01'), ...override}
              ]),
          throwsFormatException);
    }
    expect(() => catalogOf([sourceRule('G01'), sourceRule('G01')]),
        throwsFormatException);
    expect(() => BotDialogueCatalog.parse('{"schemaVersion":2,"rules":[]}'),
        throwsFormatException);
    expect(() => BotDialogueCatalog.parse('{"schemaVersion":1,"rules":[1]}'),
        throwsFormatException);
  });

  test('unknown scenarios and prerequisites cannot bypass evidence checks', () {
    for (final override in [
      {
        'id': 'UNKNOWN01',
        'templates': ['不得顯示']
      },
      {
        'requires': ['unregisteredPrivateAccess'],
        'templates': ['不得顯示']
      },
    ]) {
      final planner = plannerFor('G01', overrides: override);
      expect(say(planner, observe()).text, isNot(contains('不得顯示')));
      expect(planner.lastTrace, isNull);
    }
  });

  test(
      'private evidence requires explicit matching owner, generation and a valid shape',
      () {
    for (final fact in [
      BotFact(
          owner: 1,
          generation: 4,
          quest: 1,
          target: 2,
          switched: false,
          evil: true),
      BotFact(
          owner: 0,
          generation: 3,
          quest: 1,
          target: 2,
          switched: false,
          evil: true),
      BotFact(
          owner: 0,
          generation: 4,
          quest: 2,
          target: 2,
          switched: false,
          evil: true),
      BotFact(
          owner: 0,
          generation: 4,
          quest: 1,
          target: 7,
          switched: false,
          evil: true),
      BotFact(owner: 0, generation: 4, quest: 1, target: 2, switched: false),
      BotFact(
          owner: 0,
          generation: 4,
          quest: 1,
          target: 2,
          switched: false,
          evil: true,
          originalCard: false),
    ]) {
      expect(() => observe(facts: [fact]), throwsArgumentError);
    }
  });

  test(
      'public ledger has no ballot until all seats voted, and references are game scoped',
      () {
    final o = observe();
    expect(
        o.publicLedger.events.where((e) => e.id.kind == BotEvidenceKind.ballot),
        isEmpty);
    expect(
        o.publicLedger
            .resolve(BotEvidenceId(3, BotEvidenceKind.proposal, 'q1/a1')),
        isNull);
    expect(
        () => observe(proposals: [
              proposal(1, [true])
            ]).publicLedger,
        throwsArgumentError);
    final complete =
        observe(proposals: [proposal(1, List.filled(7, true))], rejections: 1);
    final ballot = complete.publicLedger.events
        .singleWhere((e) => e.id.kind == BotEvidenceKind.ballot);
    expect(ballot.ballots, hasLength(7));
    expect(() => ballot.ballots.add(false), throwsUnsupportedError);
    expect(() => complete.publicLedger.events.clear(), throwsUnsupportedError);
  });

  test(
      'quest cards keep their approved attempt after the rejection counter resets',
      () {
    final o = observe(
        phase: GamePhase.quest, proposals: [proposal(3, List.filled(7, true))]);
    expect(o.proposalId, const BotProposalId(4, 1, 3));
    expect(
        o.publicLedger.events
            .where((e) => e.id.kind == BotEvidenceKind.proposal),
        hasLength(1));
  });

  test('face-up future Lancelot cards are not past switch events', () {
    final o = observe(
        loyalty: [false, false, true, false, true],
        expansions: const ExpansionSettings(lancelot: 2));
    final events = o.publicLedger.events
        .where((e) => e.id.kind == BotEvidenceKind.loyalty);
    expect(events, hasLength(1));
    expect(events.single.switchOccurred, isFalse);
    final planner = plannerFor('XLC01');
    say(planner, o);
    expect(planner.lastTrace, isNull);
  });

  test('vote criticism only compares two completed public ballots', () {
    final planner = plannerFor('G16');
    say(planner, observe(proposals: [proposal(1, List.filled(7, true))]));
    expect(planner.lastTrace, isNull);
    final statement = say(
        planner,
        observe(rejections: 2, proposals: [
          proposal(1, List.filled(7, true)),
          proposal(2, [true, true, false, true, true, true, true]),
        ]));
    expect(planner.lastTrace!.ruleId, 'G16');
    expect(statement.target, 2);
    expect(statement.text, isNot(contains('這次卻反對')));
    expect(statement.evidenceIds.where((id) => id.contains('/ballot/')),
        hasLength(2));
  });

  test(
      'unbound optional event removes only that template, not the generic reply',
      () {
    final planner = plannerFor('G17', overrides: {
      'templates': ['我願意解釋，但先把你指的那一輪說清楚。', '第{{quest}}次的事情我會說明。']
    });
    final question = DiscussionStatement(
        speaker: 1,
        quest: 1,
        generation: 4,
        attempt: 1,
        questionTo: 0,
        text: '你怎麼看？');
    final statement = say(planner, observe(statements: [question]));
    expect(planner.lastTrace!.ruleId, 'G17');
    expect(statement.text, '我願意解釋，但先把你指的那一輪說清楚。');
    expect(statement.replyTo, 0);
    expect(statement.target, 1);
    expect(BotDialoguePlanner.render('第{{attempt}}次提案', {}), isNull);
    expect(BotDialoguePlanner.render('{{not_valid}}', {}), isNull);
  });

  test(
      'a sword disclosure needs that observer to be the actual recorded holder',
      () {
    final fact = BotFact(
        owner: 0,
        generation: 4,
        quest: 1,
        target: 2,
        switched: false,
        originalCard: false);
    final planner = plannerFor('XSW02');
    for (final holder in [null, 1]) {
      say(
          planner,
          observe(facts: [
            fact
          ], history: [
            QuestResult([0, 1, 2], 0, true,
                excaliburHolder: holder,
                excaliburTarget: holder == null ? null : 2)
          ]));
      expect(planner.lastTrace, isNull);
    }
    final statement = say(
        planner,
        observe(facts: [
          fact
        ], history: [
          QuestResult([0, 1, 2], 0, true,
              excaliburHolder: 0, excaliburTarget: 2)
        ]));
    expect(planner.lastTrace!.ruleId, 'XSW02');
    expect(statement.evidenceIds, contains('g4/swordUse/q1'));
    expect(statement.claimedEvil, isNull,
        reason: 'Seeing a card is not a Lady alignment claim');
  });

  test(
      'own Success can be claimed without being sword holder, with flip qualification',
      () {
    final planner = plannerFor('G12');
    say(
        planner,
        observe(history: [
          QuestResult([0, 1], 1, false)
        ], ownCards: {
          1: true
        }));
    expect(planner.lastTrace!.ruleId, 'G12');
    say(
        planner,
        observe(history: [
          QuestResult([0, 1], 1, false, excaliburHolder: 1, excaliburTarget: 0)
        ], ownCards: {
          1: true
        }));
    expect(planner.lastTrace, isNull);
  });

  test('Lady lies remain a public assertion and do not mutate the private fact',
      () {
    final fact = BotFact(
        owner: 0,
        generation: 4,
        quest: 1,
        target: 2,
        switched: false,
        evil: false);
    final o = observe(role: Role.minion, evil: true, facts: [
      fact
    ], history: [
      QuestResult([0, 1], 0, true)
    ], ladyChecks: [
      LadyCheck(0, 2, 1)
    ], statements: [
      DiscussionStatement(
          speaker: 0,
          quest: 1,
          generation: 4,
          target: 2,
          claimedEvil: true,
          switched: false,
          text: '我宣稱他是邪惡')
    ]);
    final planner = plannerFor('XLD03');
    final statement = say(planner, o);
    expect(planner.lastTrace!.ruleId, 'XLD03');
    expect(statement.claimedEvil, isTrue);
    expect(statement.evidenceIds, contains('g4/ladyUse/q1/0/2'));
    expect(o.facts.single.evil, isFalse);
    expect(statement.text, isNot(contains('我其實查到正義')));
  });

  test(
      'current Lancelot allegiance selects dialogue and future switches cannot activate it',
      () {
    final o = observe(
        role: Role.lancelotGood,
        evil: true,
        switched: true,
        expansions: const ExpansionSettings(lancelot: 2),
        loyalty: [true]);
    final evilPlanner = plannerFor('RLE01');
    say(evilPlanner, o);
    expect(evilPlanner.lastTrace!.ruleId, 'RLE01');
    final goodPlanner = plannerFor('RLG01');
    say(goodPlanner, o);
    expect(goodPlanner.lastTrace, isNull);
  });

  test(
      'public statements expose semantic intent and public evidence, not private rule IDs',
      () {
    final planner = plannerFor('RME01');
    final statement = say(planner, observe(role: Role.merlin, visible: [1, 2]),
        approve: false);
    expect(planner.lastTrace!.ruleId, 'RME01');
    expect(statement.supportsTeam, isFalse);
    final neutral = say(
        plannerFor('RPC01'),
        observe(role: Role.percival, visible: [
          1,
          2
        ], history: [
          QuestResult([1, 2], 1, false)
        ]),
        approve: false);
    expect(neutral.supportsTeam, isNull,
        reason: 'A neutral remark must not publish its private cached ballot');
    expect(neutral.target, isNull,
        reason: 'A neutral remark must not attach an incidental target');
    final publicText =
        [statement.text, statement.intent, ...statement.evidenceIds].join('/');
    for (final secret in ['RME01', 'privateStrategy', '梅林', '我看見']) {
      expect(publicText, isNot(contains(secret)));
    }
  });

  test('names are rendered once and speech never consumes strategy randomness',
      () {
    final planner = plannerFor('G04', overrides: {
      'templates': ['我對{{target}}有疑慮。']
    });
    final statement = say(
        planner,
        observe(history: [
          QuestResult([1, 2], 1, false)
        ], team: [
          0,
          2,
          3
        ]),
        approve: false);
    expect(statement.text, '我對3 號 【小明】有疑慮。');
    final a = BotBrain(Random(10)), b = BotBrain(Random(10));
    final o = observe();
    for (var i = 0; i < 10; i++) {
      a.speech(o, true);
    }
    expect(a.chooseTeam(o, 3), b.chooseTeam(o, 3));
    expect(BotBrain(Random(1)).speech(o, true).text,
        BotBrain(Random(1)).speech(observe(), true).text);
  });
}
