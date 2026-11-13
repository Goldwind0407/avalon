import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_difficulty.dart';
import 'package:avalon_shadow_council/features/solo/bot_style.dart';
import 'package:avalon_shadow_council/features/solo/bot_voice.dart';
import 'package:avalon_shadow_council/features/solo/bot_vote_plan.dart';
import 'package:avalon_shadow_council/features/solo/dialogue/bot_catalog.dart';
import 'support/bot_dialogue_fixtures.dart';

void main() {
  test('new independent public claims can change an expert initial vote', () {
    final brain = BotBrain(Random(1), difficulty: BotDifficulty.expert);
    final history = [
      QuestResult([0, 1, 2], 0, true)
    ];
    final before = observe(history: history, team: [0, 1, 3]);
    final after = observe(history: history, team: [
      0,
      1,
      3
    ], statements: [
      for (final speaker in [1, 2])
        DiscussionStatement(
            speaker: speaker,
            quest: 2,
            generation: 4,
            attempt: 1,
            target: 3,
            claimedEvil: false,
            switched: false,
            text: '我比較相信4號，但不是保證。'),
    ]);
    final plan = BotVotePlan(9);
    expect(plan.evaluate(brain, before).approve, isFalse);
    expect(plan.evaluate(brain, after, lock: true).approve, isTrue);
    expect(plan.current!.suspicion[3], lessThan(plan.initial!.suspicion[3]));
    // Once ballots begin, even a changed observation cannot change the vote.
    expect(plan.evaluate(brain, before).approve, isTrue);
  });

  test('re-evaluation keeps one random preference and cannot reroll a disguise',
      () {
    for (var seed = 0; seed < 60; seed++) {
      final brain = BotBrain(Random(seed),
          style: BotStyle.actor, difficulty: BotDifficulty.expert);
      final o = observe(role: Role.merlin, visible: [2, 3, 4]);
      final plan = BotVotePlan(seed);
      final first = plan.evaluate(brain, o);
      for (var i = 0; i < 4; i++) {
        final next = plan.evaluate(brain, o);
        expect(next.approve, first.approve);
        expect(next.reason, first.reason);
        expect(next.suspicion, first.suspicion);
      }
      if (first.approve) expect(first.reason, 'merlinDisguise');
    }
  });

  test('one speaker repeating a claim or accusation is not multiple witnesses',
      () {
    final brain = BotBrain(Random(1), difficulty: BotDifficulty.expert);
    final history = [
      QuestResult([0, 1, 2], 0, true)
    ];
    final claim = DiscussionStatement(
        speaker: 1,
        quest: 2,
        generation: 4,
        attempt: 1,
        target: 3,
        claimedEvil: true,
        switched: false,
        position: DiscussionPosition.suspect,
        text: '我懷疑4號');
    expect(
        brain.suspicion(observe(history: history, statements: [claim])),
        brain.suspicion(
            observe(history: history, statements: List.filled(30, claim))));
  });

  test('public claims cannot erase a role-authorized certainty', () {
    final brain = BotBrain(Random(1), difficulty: BotDifficulty.expert);
    // after a clean first quest (before it Merlin often plays along)
    final o = observe(role: Role.merlin, visible: [
      2,
      3,
      4
    ], history: [
      QuestResult([5, 6], 0, true)
    ], statements: [
      for (final s in [1, 5, 6])
        DiscussionStatement(
            speaker: s,
            quest: 1,
            generation: 4,
            attempt: 1,
            target: 2,
            claimedEvil: false,
            text: '3號好人'),
    ]);
    expect(brain.suspicion(o)[2], 1);
    expect(brain.vote(o), isFalse);
  });

  test('two-Fail mission does not veto a team solely for one known evil', () {
    final brain = BotBrain(Random(1), difficulty: BotDifficulty.expert);
    final o = observe(role: Role.merlin, visible: [
      2,
      3,
      4
    ], history: [
      QuestResult([0, 2], 1, false),
      QuestResult([0, 1, 3], 1, false),
      QuestResult([0, 1, 5], 0, true)
    ], team: [
      0,
      1,
      2,
      5
    ]);
    expect(o.failsRequired, 2);
    expect(brain.vote(o), isTrue);
  });

  test('answer to a vote question quotes the actual published ballot', () {
    final ballot = proposal(1, [false, true, true, true, false, true, false]);
    final o = observe(rejections: 1, proposals: [
      ballot
    ], statements: [
      DiscussionStatement(
          speaker: 1,
          quest: 1,
          generation: 4,
          attempt: 2,
          questionTo: 0,
          text: '你上一票怎麼想？',
          evidenceIds: ['g4/ballot/q1/a1']),
    ]);
    final reply = BotBrain(Random(1)).speech(o, true);
    expect(reply.text, contains('我投的是反對'));
    expect(reply.supportsTeam, true);
    expect(reply.evidenceIds, contains('g4/ballot/q1/a1'));
    expect(reply.replyTo, 0);
  });

  test('a direct accusation gets a contextual answer, with no invented history',
      () {
    final brain = BotBrain(Random(2), difficulty: BotDifficulty.expert);
    final o = observe(statements: [
      DiscussionStatement(
          speaker: 1,
          quest: 1,
          generation: 4,
          attempt: 1,
          target: 0,
          position: DiscussionPosition.suspect,
          text: '我懷疑你')
    ]);
    final answer = brain.speech(o, true);
    expect(answer.intent, 'defendSelf');
    expect(answer.replyTo, 0);
    expect(answer.supportsTeam, true);
    expect(answer.evidenceIds, ['g4/statement/s0']);
    expect(answer.text, contains('2 號'));
  });

  test('a successful two-Fail quest is not described as a failed mission', () {
    final o = observe(history: [
      QuestResult([0, 1, 2], 1, true)
    ], statements: [
      DiscussionStatement(
          speaker: 3,
          quest: 2,
          generation: 4,
          attempt: 1,
          target: 1,
          position: DiscussionPosition.suspect,
          text: '我懷疑2號')
    ]);
    DiscussionStatement? result;
    for (var seed = 0; seed < 40 && result == null; seed++) {
      result = BotVoice(Random(seed), BotStyle.aggressive, BotDifficulty.expert)
          .speak(o, false, [0, .8, .6, .3, .3, .3, .3],
              [0, .8, .6, .3, .3, .3, .3], {});
    }
    expect(result, isNotNull);
    expect(result!.text, contains('失敗牌'));
    expect(result.text, isNot(contains('任務失敗')));
    expect(result.text, isNot(contains('失敗的隊伍')));
    expect(result.supportsTeam, false);
    expect(result.evidenceIds, contains('g4/quest/q1'));
  });

  test(
      'four variants per scenario and no exact repeat until variants exhausted',
      () {
    for (final rule in BotDialogueCatalog.bundled.rules) {
      expect(rule.templates.toSet(), hasLength(4), reason: rule.id);
    }
    final planner = plannerFor('G01');
    final lines = [for (var i = 0; i < 4; i++) say(planner, observe()).text];
    expect(lines.toSet(), hasLength(4));
  });
}
