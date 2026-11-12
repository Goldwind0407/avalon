import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_observation.dart';

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
    expect(ownFail[1], brain.suspicion(view(role: Role.minion, evil: true))[1]);
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
    expect(
        brain.vote(view(rejects: 4, role: Role.assassin, evil: true)), isFalse);
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
}
