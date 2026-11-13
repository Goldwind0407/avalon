import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_difficulty.dart';
import 'package:avalon_shadow_council/features/solo/bot_style.dart';
import 'package:avalon_shadow_council/features/solo/bot_voice.dart';
import 'support/bot_dialogue_fixtures.dart';

BotVoice voice(int seed, [BotStyle style = BotStyle.balanced]) =>
    BotVoice(Random(seed), style, BotDifficulty.normal);

void main() {
  final cleanFirst = [
    QuestResult([1, 2], 0, true)
  ];
  final failedFirst = [
    QuestResult([2, 3], 1, false)
  ];

  test('a leader says why each member was picked, from the record', () {
    for (var seed = 0; seed < 20; seed++) {
      final said = voice(seed).evidence(
          observe(seat: 0, leader: 0, history: cleanFirst, team: [0, 1, 3]),
          true,
          const {});
      expect(said, isNotNull);
      expect(said!.intent, 'explainTeam');
      expect(said.text, contains('2號第1次出任務沒有失敗牌'));
      expect(said.text, contains('4號還沒出過任務'));
      expect(said.supportsTeam, isTrue);
    }
  });

  test('a leader mentions who was dropped after a failed quest', () {
    final said = voice(1).evidence(
        observe(seat: 0, leader: 0, history: failedFirst, team: [0, 1, 4]),
        true,
        const {});
    expect(said!.text, contains('3號、4號在第1次出失敗牌的隊上，這次先不帶'));
  });

  test('an objection names the member and the quest it is about', () {
    var named = 0;
    for (var seed = 0; seed < 30; seed++) {
      final said = voice(seed).evidence(
          observe(seat: 0, history: failedFirst, team: [1, 2, 4]),
          false,
          const {});
      expect(said, isNotNull);
      expect(said!.supportsTeam, isFalse);
      if (said.topic == 'member/2') {
        named++;
        expect(said.text, contains('3號'));
        expect(said.text, contains('第1次'));
        expect(said.target, 2);
        expect(said.position, DiscussionPosition.suspect);
      }
    }
    expect(named, greaterThan(15));
  });

  test('the next speaker agrees briefly instead of repeating the point', () {
    final first = [
      for (var seed = 0; seed < 10; seed++)
        voice(seed).evidence(
            observe(seat: 5, history: failedFirst, team: [1, 2, 4]),
            false,
            const {})!
    ].firstWhere((s) => s.topic == 'member/2');
    var agreed = 0;
    for (var seed = 0; seed < 30; seed++) {
      final said = voice(seed, BotStyle.follower).evidence(
          observe(
              seat: 0,
              history: failedFirst,
              team: [1, 2, 4],
              statements: [first.copyWithText(first.text)]),
          false,
          const {});
      if (said?.topic != first.topic) continue;
      agreed++;
      expect(said!.replyTo, 0);
      expect(said.text, contains('6號'));
      expect(said.text.length, lessThan(30));
    }
    expect(first.topic, 'member/2');
    expect(agreed, greaterThan(0));
  });

  test('nobody calls a player out and waves that player\'s team through', () {
    for (var seed = 0; seed < 40; seed++) {
      final said = voice(seed).evidence(
          observe(
              seat: 0,
              history: [
                QuestResult([0, 3], 1, false)
              ],
              team: [3, 4, 5]),
          true,
          const {});
      if (said == null) continue;
      expect(
          said.position == DiscussionPosition.suspect &&
              said.team.contains(said.target),
          isFalse,
          reason: said.text);
    }
  });

  test('an evil player never points the record at an ally', () {
    for (var seed = 0; seed < 40; seed++) {
      final said = voice(seed).evidence(
          observe(
              seat: 0,
              role: Role.assassin,
              evil: true,
              visible: [2],
              history: failedFirst,
              team: [1, 2, 4]),
          false,
          const {2});
      expect(said?.target, isNot(2));
      expect(said?.text ?? '', isNot(contains('3號、4號兩個人')));
    }
  });

  test('a vote that went wrong is owned up to once', () {
    final o = observe(seat: 0, history: failedFirst, team: [
      0,
      1,
      5
    ], proposals: [
      ProposalRecord(
          quest: 1,
          attempt: 1,
          leader: 2,
          team: [2, 3],
          votes: [true, true, true, true, false, false, true])
    ]);
    final speaker = voice(2, BotStyle.logical);
    final topics = [
      for (var i = 0; i < 12; i++) speaker.evidence(o, true, const {})?.topic
    ];
    expect(topics.where((t) => t == 'mistaken/1').length, 1);
  });

  test('an accused player answers with who else was on that quest', () {
    final accusation = DiscussionStatement(
        speaker: 4,
        quest: 2,
        generation: 4,
        attempt: 1,
        text: '我懷疑1號。',
        target: 0,
        position: DiscussionPosition.suspect);
    final o = observe(
        seat: 0,
        history: [
          QuestResult([0, 2, 3], 1, false)
        ],
        team: [1, 4, 5],
        statements: [accusation]);
    final neutral = List.filled(7, .3);
    final said = voice(1).speak(o, false, neutral, neutral, const {})!;
    expect(said.replyTo, 0);
    expect(said.text, contains('3號、4號'));
    expect(said.text, contains('第1次'));
  });
}
