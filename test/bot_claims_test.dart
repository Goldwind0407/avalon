import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/player_speech.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_observation.dart';
import 'package:avalon_shadow_council/features/solo/bot_voice.dart';
import 'support/bot_dialogue_fixtures.dart';

const roles = {Role.merlin, Role.percival, Role.morgana, Role.assassin};

/// "I am Percival, and [morgana] is Morgana", said by [speaker].
DiscussionStatement claim(int speaker, int? morgana, {int quest = 3}) =>
    DiscussionStatement(
        speaker: speaker,
        quest: quest,
        generation: 4,
        attempt: 1,
        text: '我是派西維爾。',
        intent: DiscussionStatement.percivalClaim,
        target: morgana,
        position: morgana == null ? null : DiscussionPosition.suspect);

/// Seat 1 sat on both failed quests; seat 2 on neither.
final twoFails = [
  QuestResult([1, 3], 1, false),
  QuestResult([1, 4, 5], 1, false)
];

DiscussionStatement? said(BotObservation o, int seed,
    {bool approve = false, Set<int> allies = const {}}) {
  final brain = BotBrain(Random(seed), dialogueRandom: Random(seed));
  return brain.voice.claim(o, approve, brain.suspicion(o, asServant: true),
      brain.suspicion(o), allies);
}

void main() {
  group('coming out as Percival', () {
    // six players, so every quest fails on a single Fail card
    BotObservation percival(List<QuestResult> history) => observe(
        role: Role.percival,
        count: 6,
        visible: [1, 2],
        history: history,
        team: [1, 4, 5],
        configuredRoles: roles);

    test('waits until one more failed quest loses the game', () {
      final early = percival([
        twoFails.first,
        QuestResult([2, 4, 5], 0, true)
      ]);
      for (var seed = 0; seed < 40; seed++) {
        expect(said(early, seed), isNull);
      }
      final late = percival([
        twoFails.first,
        QuestResult([2, 4, 5], 0, true),
        twoFails.last
      ]);
      final real = BotBrain(Random(1)).suspicion(late);
      expect(real[1] - real[2], greaterThanOrEqualTo(.45));
      final claims = [
        for (var seed = 0; seed < 40; seed++)
          if (said(late, seed) case final s?) s
      ];
      expect(claims, isNotEmpty);
      for (final s in claims) {
        expect(s.claimsPercival, isTrue);
        expect(s.target, 1);
        expect(s.position, DiscussionPosition.suspect);
        // the other candidate, who must be Merlin, is never named
        expect(s.text, contains('2號'));
        expect(s.text, contains('莫甘娜'));
        expect(s.text, isNot(contains('3號')));
        expect(s.supportsTeam, isFalse);
      }
    });

    test('never happens in a game without Percival and Morgana', () {
      final o = observe(
          role: Role.percival,
          visible: [1, 2],
          history: twoFails,
          team: [1, 4, 6],
          configuredRoles: const {Role.merlin, Role.assassin});
      for (var seed = 0; seed < 40; seed++) {
        expect(said(o, seed), isNull);
      }
    });

    test('nobody calls a member Morgana and approves that team', () {
      final o = percival([
        twoFails.first,
        QuestResult([2, 4, 5], 0, true),
        twoFails.last
      ]);
      for (var seed = 0; seed < 40; seed++) {
        expect(said(o, seed, approve: true), isNull);
      }
    });

    test('Morgana, named, claims it back', () {
      final o = observe(
          seat: 2,
          role: Role.morgana,
          evil: true,
          visible: [5],
          history: twoFails,
          team: [0, 3, 4],
          statements: [claim(0, 2)],
          configuredRoles: roles);
      final answers = [
        for (var seed = 0; seed < 40; seed++)
          if (said(o, seed, allies: {2, 5}) case final s?) s
      ];
      final counters = answers.where((s) => s.claimsPercival).toList();
      expect(counters.length, greaterThan(20));
      for (final s in counters) {
        expect(s.target, 0);
        expect(s.text, contains('1號'));
        expect(s.text, contains('才是莫甘娜'));
      }
    });

    test('the real Percival calls out a false claimant, but not Merlin', () {
      // a stranger to his pair claims: plainly a lie
      final stranger = observe(
          role: Role.percival,
          visible: [1, 2],
          history: [twoFails.first],
          team: [3, 4, 5],
          statements: [claim(6, 4)],
          configuredRoles: roles);
      final answer = said(stranger, 3)!;
      expect(answer.claimsPercival, isTrue);
      expect(answer.text, contains('7號在說謊'));
      // one of his two naming the other is how Merlin would help
      final helper = observe(
          role: Role.percival,
          visible: [1, 2],
          history: [twoFails.first],
          team: [3, 4, 5],
          statements: [claim(2, 1)],
          configuredRoles: roles);
      for (var seed = 0; seed < 20; seed++) {
        expect(said(helper, seed), isNull);
      }
    });

    test('a player called Morgana denies it once', () {
      final o = observe(
          seat: 4,
          history: [twoFails.first],
          statements: [claim(0, 4)],
          configuredRoles: roles);
      final brain = BotBrain(Random(1));
      DiscussionStatement? next() => brain.voice
          .claim(o, false, brain.suspicion(o), brain.suspicion(o), const {});
      final first = next()!;
      expect(first.claimsPercival, isFalse);
      expect(first.text, contains('我不是莫甘娜'));
      expect(next(), isNull);
    });
  });

  group('what the others make of a claim', () {
    test('a claim raises doubt about the player it names', () {
      BotObservation o(List<DiscussionStatement> statements) => observe(
          seat: 3,
          // the claimant has a clean quest behind him
          history: [
            QuestResult([0, 5], 0, true),
            QuestResult([0, 5, 6], 0, true)
          ],
          statements: statements,
          configuredRoles: roles);
      final brain = BotBrain(Random(1));
      final before = brain.suspicion(o(const []));
      final after = brain.suspicion(o([claim(0, 4)]));
      expect(after[4], greaterThan(before[4] + .1));
    });

    test('a loyal player called Morgana knows the claimant lies', () {
      final o = observe(
          seat: 4,
          history: [twoFails.first],
          statements: [claim(0, 4)],
          configuredRoles: roles);
      expect(BotBrain(Random(1)).suspicion(o)[0], greaterThanOrEqualTo(.95));
    });

    test('of two claimants the worse record is taken for the liar', () {
      // seat 1 sat on the failed quest, seat 0 did not
      BotObservation o(List<DiscussionStatement> statements) => observe(
          seat: 4,
          history: [
            QuestResult([1, 3], 1, false)
          ],
          statements: statements,
          configuredRoles: roles);
      final brain = BotBrain(Random(1));
      final before = brain.suspicion(o(const []));
      final after = brain.suspicion(o([claim(0, 1), claim(1, 0)]));
      expect(after[1], greaterThan(before[1] + .2));
      expect(after[1], greaterThan(after[0]));
    });

    test('the real Percival knows who is lying', () {
      BotObservation o(DiscussionStatement rival) => observe(
          role: Role.percival,
          visible: [1, 2],
          history: [
            QuestResult([5, 6], 0, true)
          ],
          statements: [rival],
          configuredRoles: roles);
      final brain = BotBrain(Random(1));
      // a claimant outside his two cannot be Percival, Merlin or Morgana
      expect(brain.suspicion(o(claim(4, 5)))[4], greaterThanOrEqualTo(.9));
      // one of his two calling him Morgana is Morgana; the other is Merlin
      final p = brain.suspicion(o(claim(1, 0)));
      expect(p[1], 1);
      expect(p[2], 0);
    });

    test('Merlin sides with the claimant he does not see as evil', () {
      final o = observe(
          seat: 3,
          role: Role.merlin,
          visible: [2],
          history: [
            QuestResult([1, 2], 1, false)
          ],
          team: [3, 4, 5],
          statements: [claim(1, 2, quest: 2), claim(2, 1, quest: 2)],
          configuredRoles: roles);
      var sided = 0;
      for (var seed = 0; seed < 60; seed++) {
        final brain = BotBrain(Random(seed), dialogueRandom: Random(seed));
        final line =
            brain.voice.evidence(o, true, const {}, brain.suspicion(o));
        if (!(line?.topic?.startsWith('claims/') ?? false)) continue;
        sided++;
        expect(line!.topic, 'claims/1/2/1');
        expect(line.target, 2);
        expect(line.text, contains('信2號'));
      }
      expect(sided, greaterThan(0));
    });
  });

  group('what a claim tells the Assassin', () {
    BotObservation assassin(List<DiscussionStatement> statements) => observe(
        seat: 6,
        role: Role.assassin,
        evil: true,
        visible: [5],
        phase: GamePhase.assassination,
        history: [
          QuestResult([0, 1], 0, true),
          QuestResult([0, 1, 2], 0, true),
          QuestResult([0, 1], 0, true)
        ],
        statements: statements,
        configuredRoles: roles);

    test('a good claimant who names a good player has named Merlin', () {
      for (var seed = 0; seed < 30; seed++) {
        expect(BotBrain(Random(seed)).assassinate(assassin([claim(0, 3)])), 3);
      }
    });

    test('calling the Assassin Morgana is the mistake Merlin makes', () {
      for (var seed = 0; seed < 30; seed++) {
        expect(BotBrain(Random(seed)).assassinate(assassin([claim(4, 6)])), 4);
      }
    });
  });

  group('what the player types', () {
    final names = List.generate(7, (i) => '玩家${i + 1}');
    test('a claim with the player it points at', () {
      final s = PlayerSpeech.parse('我是派西維爾，3號是莫甘娜', names, 0);
      expect(s.kind, PlayerSpeechKind.claimPercival);
      expect(s.target, 2);
    });
    test('a bare claim', () {
      final s = PlayerSpeech.parse('我跳派西', names, 0);
      expect(s.kind, PlayerSpeechKind.claimPercival);
      expect(s.target, isNull);
    });
    test('naming Merlin says nothing about Morgana', () {
      final s = PlayerSpeech.parse('我才是派西維爾，5號是梅林', names, 0);
      expect(s.kind, PlayerSpeechKind.claimPercival);
      expect(s.target, isNull);
    });
  });
}
