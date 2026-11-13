import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_observation.dart';
import 'package:avalon_shadow_council/features/solo/dialogue/bot_contract.dart';
import 'support/bot_dialogue_fixtures.dart';

DiscussionStatement opinion(int speaker, int target,
        {int quest = 2,
        int attempt = 1,
        DiscussionPosition position = DiscussionPosition.suspect,
        DiscussionCertainty certainty = DiscussionCertainty.tentative,
        List<String> evidence = const ['g4/quest/q1'],
        bool? support,
        int? questionTo,
        String? intent,
        bool switched = false}) =>
    DiscussionStatement(
        speaker: speaker,
        quest: quest,
        attempt: attempt,
        generation: 4,
        target: target,
        position: position,
        certainty: certainty,
        evidenceIds: evidence,
        supportsTeam: support,
        questionTo: questionTo,
        switched: switched,
        intent: intent ??
            (position == DiscussionPosition.suspect ? 'accuse' : 'defendOther'),
        text: '公開的立場');

DiscussionStatement ladyClaim(int speaker, bool evil,
        {int target = 2,
        int sourceQuest = 2,
        int quest = 3,
        int holder = 1,
        bool switched = false,
        int? quotedFrom}) =>
    DiscussionStatement(
        speaker: speaker,
        quest: quest,
        attempt: 1,
        generation: 4,
        target: target,
        claimedEvil: evil,
        switched: switched,
        intent: 'interpretLady',
        evidenceIds: ['g4/ladyUse/q$sourceQuest/$holder/$target'],
        quotedFrom: quotedFrom,
        text: '公開宣稱');

void main() {
  test(
      'commenting on a public Lady claim cannot attach a different private inspection',
      () {
    final planner = plannerFor('ROB06');
    final result = say(
        planner,
        observe(
            role: Role.oberon,
            evil: true,
            expansions: const ExpansionSettings(lady: true),
            history: [
              QuestResult([0, 1], 0, true),
              QuestResult([0, 1, 3], 0, true),
              QuestResult([0, 2, 3], 1, false)
            ],
            ladyChecks: [
              LadyCheck(0, 4, 2),
              LadyCheck(4, 2, 3)
            ],
            facts: [
              BotFact(
                  owner: 0,
                  generation: 4,
                  quest: 2,
                  target: 4,
                  switched: false,
                  evil: true)
            ],
            statements: [
              ladyClaim(4, false, holder: 4, quest: 4, sourceQuest: 3)
            ]));
    expect(planner.lastTrace?.ruleId, 'ROB06');
    expect(result.target, 2);
    expect(result.claimedEvil, isNull);
    expect(result.evidenceIds, isNot(contains('g4/ladyUse/q2/0/4')));
  });
  final failed = [
    QuestResult([0, 1, 2], 1, false)
  ];
  final accusation = opinion(1, 2);
  final selfAccusation = opinion(1, 0);
  final backing = opinion(3, 2, position: DiscussionPosition.defend);
  final selfBacking = opinion(1, 0, position: DiscussionPosition.defend);
  final strong =
      opinion(1, 2, certainty: DiscussionCertainty.certain, evidence: []);
  final influence = [
    opinion(1, 2, position: DiscussionPosition.defend),
    backing
  ];
  final question =
      opinion(1, 2, questionTo: 0, evidence: [], intent: 'challengeClaim');
  final ladyHistory = [
    QuestResult([0, 1], 0, true),
    QuestResult([1, 2, 3], 0, true)
  ];
  final switchedHistory = [
    ...ladyHistory,
    QuestResult([0, 2, 3], 1, false)
  ];
  final cases = <(String, BotObservation, bool)>[
    ('G18', observe(history: failed, statements: [accusation]), true),
    (
      'G19',
      observe(history: failed, statements: [
        opinion(0, 2,
            quest: 1, position: DiscussionPosition.defend, evidence: [])
      ]),
      true
    ),
    ('G21', observe(history: failed, statements: [question]), true),
    ('RLS04', observe(history: failed, statements: [strong]), true),
    (
      'RLS05',
      observe(
          leader: 0,
          history: failed,
          team: [0, 2, 3],
          proposals: [proposal(1, List.filled(7, true))]),
      true
    ),
    (
      'RLS06',
      observe(history: failed, statements: [accusation, backing]),
      true
    ),
    (
      'RME04',
      observe(
          role: Role.merlin,
          visible: [2],
          history: failed,
          statements: [accusation]),
      true
    ),
    (
      'RME05',
      observe(
          role: Role.merlin,
          visible: [2],
          history: failed,
          statements: [question]),
      false
    ),
    (
      'RME06',
      observe(
          role: Role.merlin,
          visible: [4, 5],
          history: failed,
          configuredRoles: {Role.mordred}),
      true
    ),
    (
      'RPC02',
      observe(
          role: Role.percival,
          visible: [1, 2],
          history: failed,
          statements: [accusation]),
      true
    ),
    (
      'RPC04',
      observe(role: Role.percival, statements: [
        DiscussionStatement(
            speaker: 1,
            quest: 1,
            attempt: 1,
            generation: 4,
            claimsOpeningKnowledge: true,
            text: '我宣稱有開局情報')
      ]),
      true
    ),
    (
      'RPC05',
      observe(role: Role.percival, history: failed, statements: influence),
      true
    ),
    (
      'RPC07',
      observe(
          role: Role.percival,
          visible: [1, 2],
          history: ladyHistory,
          ladyChecks: [LadyCheck(1, 3, 2)],
          statements: [
            ladyClaim(1, false, target: 3),
            ladyClaim(2, true, target: 3)
          ]),
      true
    ),
    (
      'REV01',
      observe(role: Role.minion, evil: true, plannedQuestSuccess: true),
      true
    ),
    (
      'REV02',
      observe(
          role: Role.minion,
          evil: true,
          visible: [2],
          history: failed,
          statements: [accusation]),
      true
    ),
    (
      'REV04',
      observe(
          role: Role.minion,
          evil: true,
          history: failed,
          statements: [accusation]),
      true
    ),
    (
      'REV05',
      observe(
          role: Role.minion,
          evil: true,
          visible: [2],
          history: failed,
          statements: [
            accusation,
            opinion(3, 2),
            opinion(2, 1, support: true)
          ]),
      false
    ),
    (
      'RAS01',
      observe(
          role: Role.assassin,
          evil: true,
          visible: [2],
          history: failed,
          statements: [strong]),
      true
    ),
    (
      'RAS02',
      observe(
          role: Role.assassin,
          evil: true,
          visible: [4, 5],
          rejections: 2,
          team: [1, 2],
          proposals: [
            ProposalRecord(
                quest: 1,
                attempt: 1,
                leader: 1,
                team: [1, 2],
                votes: List.filled(7, false)),
            ProposalRecord(
                quest: 1,
                attempt: 2,
                leader: 1,
                team: [1, 3],
                votes: List.filled(7, false))
          ]),
      true
    ),
    (
      'RAS03',
      observe(
          role: Role.assassin,
          evil: true,
          history: failed,
          statements: influence),
      true
    ),
    (
      'RAS04',
      observe(
          role: Role.assassin,
          evil: true,
          visible: [2],
          history: failed,
          statements: [accusation]),
      true
    ),
    (
      'RAS05',
      observe(
          role: Role.assassin,
          evil: true,
          history: failed,
          statements: influence),
      true
    ),
    (
      'RMG02',
      observe(
          role: Role.morgana,
          evil: true,
          history: ladyHistory,
          ladyChecks: [LadyCheck(1, 2, 2)],
          statements: [ladyClaim(1, false), ladyClaim(3, true)]),
      true
    ),
    (
      'RMG04',
      observe(
          role: Role.morgana,
          evil: true,
          history: failed,
          statements: influence),
      true
    ),
    (
      'RMG05',
      observe(
          role: Role.morgana,
          evil: true,
          history: failed,
          statements: [selfAccusation]),
      true
    ),
    ('RMG06', observe(role: Role.morgana, evil: true, history: failed), true),
    (
      'RMG07',
      observe(
          role: Role.morgana,
          evil: true,
          history: failed,
          statements: [strong]),
      true
    ),
    (
      'RMD03',
      observe(
          role: Role.mordred,
          evil: true,
          history: failed,
          statements: [selfBacking]),
      true
    ),
    (
      'RMD04',
      observe(
          role: Role.mordred,
          evil: true,
          history: failed,
          statements: [selfAccusation]),
      true
    ),
    (
      'RMD05',
      observe(role: Role.mordred, evil: true, visible: [2], history: failed),
      true
    ),
    (
      'ROB03',
      observe(
          role: Role.oberon,
          evil: true,
          history: failed,
          statements: [selfAccusation]),
      true
    ),
    (
      'ROB04',
      observe(
          role: Role.oberon,
          evil: true,
          history: failed,
          statements: [selfBacking]),
      true
    ),
    ('ROB05', observe(role: Role.oberon, evil: true, history: failed), true),
    (
      'ROB06',
      observe(
          role: Role.oberon,
          evil: true,
          history: ladyHistory,
          ladyChecks: [LadyCheck(1, 2, 2)],
          statements: [ladyClaim(1, false)]),
      true
    ),
    (
      'RLG02',
      observe(
          role: Role.lancelotEvil,
          evil: false,
          switched: true,
          expansions: const ExpansionSettings(lancelot: 1),
          history: switchedHistory,
          loyalty: [false, false, true, false],
          ladyChecks: [LadyCheck(1, 2, 2)]),
      true
    ),
    (
      'RLG04',
      observe(
          role: Role.lancelotGood,
          expansions: const ExpansionSettings(lancelot: 1),
          history: failed,
          statements: [
            opinion(1, 2,
                position: DiscussionPosition.defend,
                certainty: DiscussionCertainty.permanent)
          ]),
      true
    ),
    (
      'RLG05',
      observe(
          role: Role.lancelotEvil,
          evil: false,
          switched: true,
          expansions: const ExpansionSettings(lancelot: 2),
          history: failed,
          loyalty: [false, true],
          statements: [selfAccusation]),
      true
    ),
    (
      'RLE03',
      observe(
          role: Role.lancelotGood,
          evil: true,
          switched: true,
          expansions: const ExpansionSettings(lancelot: 2),
          history: failed,
          loyalty: [
            false,
            true
          ],
          statements: [
            opinion(0, 2, quest: 1, support: true),
            opinion(1, 0, questionTo: 0, intent: 'challengeVote')
          ]),
      false
    ),
    (
      'RLE05',
      observe(
          role: Role.lancelotGood,
          evil: true,
          switched: true,
          expansions: const ExpansionSettings(lancelot: 1),
          history: switchedHistory,
          loyalty: [false, false, true, false],
          ladyChecks: [LadyCheck(1, 2, 2)]),
      true
    ),
    (
      'RLE06',
      observe(
          role: Role.lancelotEvil,
          evil: true,
          history: failed,
          statements: [selfAccusation]),
      true
    ),
    (
      'RLE07',
      observe(
          role: Role.lancelotGood,
          evil: true,
          switched: true,
          rejections: 1,
          expansions: const ExpansionSettings(lancelot: 2),
          history: failed,
          loyalty: [
            true,
            false
          ],
          statements: [
            DiscussionStatement(
                speaker: 1,
                quest: 2,
                attempt: 2,
                generation: 4,
                intent: 'discussLancelot',
                text: '談轉換')
          ]),
      true
    ),
    (
      'XLD04',
      observe(
          history: ladyHistory,
          ladyChecks: [LadyCheck(1, 2, 2)],
          statements: [ladyClaim(1, false), ladyClaim(1, true)]),
      true
    ),
    (
      'XLD05',
      observe(history: ladyHistory, ladyChecks: [
        LadyCheck(1, 2, 2)
      ], statements: [
        ladyClaim(1, false),
        opinion(3, 2,
            quest: 3,
            position: DiscussionPosition.defend,
            certainty: DiscussionCertainty.certain,
            evidence: ['g4/ladyUse/q2/1/2', 'g4/statement/s0'])
      ]),
      true
    ),
    (
      'XSW04',
      observe(history: [
        QuestResult([0, 1, 2], 1, false, excaliburHolder: 1, excaliburTarget: 2)
      ], statements: [
        DiscussionStatement(
            speaker: 3,
            quest: 2,
            attempt: 1,
            generation: 4,
            target: 2,
            claimedOriginalSuccess: false,
            originalCardQuest: 1,
            text: '我宣稱看過原始牌')
      ]),
      true
    ),
    (
      'XLC02',
      observe(
          history: switchedHistory,
          switched: true,
          expansions: const ExpansionSettings(lancelot: 1),
          loyalty: [false, false, true, false],
          ladyChecks: [LadyCheck(1, 2, 2)],
          statements: [ladyClaim(1, false)]),
      true
    ),
    (
      'XVR01',
      observe(history: failed, statements: [
        opinion(1, 2,
            quest: 1, position: DiscussionPosition.defend, evidence: [])
      ]),
      true
    ),
    (
      'XVR02',
      observe(statements: [
        DiscussionStatement(
            speaker: 1,
            quest: 1,
            attempt: 1,
            generation: 4,
            claimsOpeningKnowledge: true,
            text: '我宣稱有情報')
      ]),
      true
    ),
  ];
  for (final (id, o, approve) in cases) {
    test(
        '$id activates from matching public events and permitted private hints',
        () {
      final planner = plannerFor(id);
      if (id == 'G19') {
        planner.memory.record(BotDialogueTrace(
            ruleId: 'G18',
            proposal: const BotProposalId(4, 1, 1),
            intent: BotSpeechIntent.defendOther,
            policy: BotClaimPolicy.publicGrounded,
            plannedApprove: true,
            publicEvidence: [],
            semanticKey: 'prior'));
      }
      final result = say(planner, o, approve: approve);
      expect(planner.lastTrace?.ruleId, id);
      expect(result.text, isNot(contains('{{')));
      expect(result.text, isNot(contains(id)));
      expect(
          o.publicLedger.permitsAll(planner.lastTrace!.publicEvidence), isTrue);
      if (result.replyTo != null) {
        expect(result.replyTo!, lessThan(o.statements.length));
      }
      if (id == 'RLS06') {
        expect(result.questionTo, 3);
        expect(result.target, 2);
        expect(result.position, isNull,
            reason: 'Asking about a defense is not an endorsement');
      }
    });
  }

  test(
      'a selected assassination is declared by its actual actor and target only',
      () {
    final o = observe(
        role: Role.assassin,
        evil: true,
        phase: GamePhase.assassination,
        history: [
          for (var i = 0; i < 3; i++) QuestResult([0, 1, 2], 0, true)
        ]);
    final brain = BotBrain(Random(1));
    final statement = brain.assassinationSpeech(o, 2);
    expect(brain.dialogue.lastTrace?.ruleId, 'RAS06');
    expect(statement.target, 2);
    expect(statement.text, contains('3號'));
    expect(statement.quest, 3);
    expect(statement.attempt, isNull);
    expect(() => brain.assassinationSpeech(o, 0), throwsArgumentError);
    expect(() => brain.assassinationSpeech(observe(), 2), throwsArgumentError);
  });

  test(
      'no accusation, confidence or influence is invented from unstructured text',
      () {
    for (final id in [
      'G18',
      'RLS04',
      'RPC05',
      'RMG02',
      'XLD04',
      'XSW04',
      'XVR02'
    ]) {
      final planner = plannerFor(id);
      say(
          planner,
          observe(statements: [
            DiscussionStatement(
                speaker: 1, quest: 1, text: '我肯定小明有問題！我看過原始牌！大家都聽他！')
          ]));
      expect(planner.lastTrace, isNull, reason: id);
    }
  });
  test(
      'card owners, sword holders and quoted claims are not accused of impossible knowledge',
      () {
    final history = [
      QuestResult([0, 1, 2], 1, false, excaliburHolder: 1, excaliburTarget: 2)
    ];
    for (final author in [1, 2, 3]) {
      final statements = [
        DiscussionStatement(
            speaker: 1,
            quest: 2,
            attempt: 1,
            generation: 4,
            target: 2,
            originalCardQuest: 1,
            claimedOriginalSuccess: false,
            text: '宣稱'),
        DiscussionStatement(
            speaker: author,
            quest: 2,
            attempt: 1,
            generation: 4,
            target: 2,
            originalCardQuest: 1,
            claimedOriginalSuccess: false,
            quotedFrom: author == 3 ? 0 : null,
            text: '宣稱或引述')
      ];
      final planner = plannerFor('XSW04');
      say(planner, observe(history: history, statements: statements));
      expect(planner.lastTrace, isNull);
    }
  });
  test(
      'a switch between claims prevents treating differing alignments as a contradiction',
      () {
    final o = observe(
        history: ladyHistory,
        ladyChecks: [LadyCheck(1, 2, 2)],
        statements: [ladyClaim(1, false), ladyClaim(1, true, switched: true)]);
    final planner = plannerFor('XLD04');
    say(planner, o);
    expect(planner.lastTrace, isNull);
  });
  test(
      'future switches and two cancelling switches cannot invalidate an old inspection',
      () {
    for (final cards in [
      [false, false, false, false, true],
      [false, false, true, true, false]
    ]) {
      final planner = plannerFor('XLC02');
      say(
          planner,
          observe(
              history: switchedHistory,
              expansions: const ExpansionSettings(lancelot: 2),
              loyalty: cards,
              ladyChecks: [LadyCheck(1, 2, 2)],
              statements: [ladyClaim(1, false)]));
      expect(planner.lastTrace, isNull);
    }
  });
  test('new contrary evidence must occur after the cited endorsement', () {
    final planner = plannerFor('XVR01');
    say(planner, observe(history: failed, statements: [backing]));
    expect(planner.lastTrace, isNull);
  });
  test(
      'a hide line needs a committed own Success plan and the early-game context',
      () {
    final planner = plannerFor('REV01');
    for (final planned in [null, false]) {
      say(planner,
          observe(role: Role.minion, evil: true, plannedQuestSuccess: planned));
      expect(planner.lastTrace, isNull);
    }
  });
  test(
      'public statement references from another generation cannot enter an observation',
      () {
    expect(
        () => observe(statements: [
              DiscussionStatement(
                  speaker: 1, quest: 1, generation: 3, text: '舊局發言')
            ]),
        throwsArgumentError);
  });
}
