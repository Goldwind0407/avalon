import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/audit/bot_audit.dart';
import 'package:avalon_shadow_council/features/solo/bot_vote_plan.dart';
import 'package:avalon_shadow_council/features/solo/game_review.dart';
import 'balance_test.dart' show Setup, play, randomSetup;

/// A game of five: seats 0-4, evil at 3 (Assassin) and 4 (Morgana), with
/// the quests and proposals given.
GameReview game(List<ReviewQuest> quests,
        {List<Role>? roles, List<LadyCheck> lady = const []}) =>
    GameReview(
        players: ['a', 'b', 'c', 'd', 'e'],
        roles: roles ??
            const [
              Role.merlin,
              Role.percival,
              Role.loyal,
              Role.assassin,
              Role.morgana
            ],
        styles: const [null, null, null, null, null],
        mySeat: 0,
        winner: null,
        result: null,
        quests: quests,
        endLines: const [],
        ladyChecks: lady,
        assassinTarget: null,
        expansions: const ExpansionSettings());

ReviewProposal proposal(int quest, int attempt, int leader, List<int> team,
        List<bool> votes,
        {Map<int, BotVoteDecision> decisions = const {},
        List<DiscussionStatement> lines = const []}) =>
    ReviewProposal(
        ProposalRecord(
            quest: quest,
            attempt: attempt,
            leader: leader,
            team: team,
            votes: votes),
        [for (final l in lines) ReviewLine(l, null)],
        decisions);

void main() {
  group('what a player can prove', () {
    test('a Fail on a team of two, one of them me, proves the other evil', () {
      final r = game([
        ReviewQuest(1, const [], QuestResult(const [2, 3], 1, false),
            const {2: true, 3: false}),
      ]);
      final view = DealView.of(r, 2, 2)!;
      expect(view.provenEvil(3), isTrue);
      // seat 1 was not on it: only "one of 2 and 3" for him
      final other = DealView.of(r, 1, 2, publicOnly: true)!;
      expect(other.provenEvil(3), isFalse);
      expect(other.evilShare(3), greaterThan(other.evilShare(0)));
    });

    test('Merlin sees the evil seats, but is judged as a servant', () {
      final r = game(const []);
      expect(DealView.of(r, 0, 1)!.provenEvil(3), isTrue);
      expect(DealView.of(r, 0, 1, publicOnly: true)!.provenEvil(3), isFalse);
    });

    test('Percival knows one of his two is evil', () {
      final view = DealView.of(game(const []), 1, 1)!;
      expect(view.evilShare(0) + view.evilShare(4), 1);
      expect(view.provenGood(1), isTrue);
    });

    test("a Lady check counts only for its holder, after it is made", () {
      final r = game(const [], lady: [const LadyCheck(2, 4, 2)]);
      expect(DealView.of(r, 2, 2)!.provenEvil(4), isFalse);
      expect(DealView.of(r, 2, 3)!.provenEvil(4), isTrue);
      expect(DealView.of(r, 1, 3, publicOnly: true)!.provenEvil(4), isFalse);
    });

    test('a quest Excalibur changed proves nothing', () {
      final r = game([
        ReviewQuest(
            1,
            const [],
            QuestResult(const [2, 3], 1, false,
                excaliburHolder: 2, excaliburTarget: 3),
            const {2: true, 3: true}),
      ]);
      expect(DealView.of(r, 2, 2)!.provenEvil(3), isFalse);
    });
  });

  group('the referee', () {
    test('a servant backing a team with a proven evil player is caught', () {
      final failed = ReviewQuest(1, const [],
          QuestResult(const [2, 3], 1, false), const {2: true, 3: false});
      final r = game([
        failed,
        ReviewQuest(2, [
          proposal(2, 1, 4, [3, 4, 0], [false, true, true, true, true]),
        ], null, const {}),
      ]);
      final rules = BotAudit(r).findings().map((f) => '${f.rule}/${f.seat}');
      expect(rules, contains('H1/2'));
      // Merlin is judged as a servant: 3 is not proven to him in public
      expect(rules, isNot(contains('H1/0')));
    });

    test('turning down the fifth proposal is caught, a slip is not', () {
      final r = game([
        ReviewQuest(1, [
          proposal(1, 5, 0, [0, 1], [true, false, false, true, true],
              decisions: {
                2: BotVoteDecision(false, 'noviceSlip', 0, [0, 0, 0, 0, 0])
              }),
        ], null, const {}),
      ]);
      final found = BotAudit(r).findings();
      expect(found.map((f) => '${f.rule}/${f.seat}'), ['H3/1']);
    });

    test('evil holding back the winning Fail is caught', () {
      ReviewQuest fail(int q) => ReviewQuest(q, const [],
          QuestResult(const [3, 2], 1, false), const {3: false, 2: true});
      final r = game([
        fail(1),
        fail(2),
        ReviewQuest(3, const [], QuestResult(const [4, 0], 0, true),
            const {4: true, 0: true}),
      ]);
      expect(BotAudit(r).findings().map((f) => '${f.rule}/${f.seat}'),
          contains('H4/4'));
    });

    test('speaking up for a proven evil player is caught', () {
      final failed = ReviewQuest(1, const [],
          QuestResult(const [2, 3], 1, false), const {2: true, 3: false});
      final r = game([
        failed,
        ReviewQuest(2, [
          proposal(2, 1, 0, [0, 1, 2], List.filled(5, true), lines: [
            DiscussionStatement(
                speaker: 2,
                quest: 2,
                attempt: 1,
                target: 3,
                position: DiscussionPosition.defend,
                text: '3號我信'),
          ]),
        ], null, const {}),
      ]);
      expect(BotAudit(r).findings().map((f) => '${f.rule}/${f.seat}'),
          contains('H5/2'));
    });
  });

  // The guard: the same 200 all-computer games every run, and no provable
  // mistake in them (Merlin's talk aside: he speaks against the good on
  // purpose, as cover). A change to the bots that breaks their logic fails
  // here, with the moves listed.
  test('the computers make no provable mistake', () {
    final r = Random(2026);
    final found = <String>[];
    for (var g = 0; g < 200; g++) {
      final setup = randomSetup(r);
      final seed = r.nextInt(1 << 30);
      play(setup, seed, true, (s) {
        final review = s.review!;
        for (final f in BotAudit(review).findings()) {
          if (!f.proven || !guarded.contains(f.rule)) continue;
          if (f.rule == 'H5' && review.roles[f.seat] == Role.merlin) continue;
          found.add('第$g局（${_label(setup)}，種子$seed）${f.where} '
              '${f.seat + 1}號${review.roles[f.seat].label} ${f.rule}：${f.what}'
              '${f.reason == null ? '' : '［${f.reason}］'}');
        }
      });
    }
    expect(found, isEmpty, reason: found.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 10)));

  // AUDIT_GAMES=1000 [AUDIT_SEED=1] [AUDIT_OUT=build/llm/audit.txt]
  //   flutter test test/bot_audit_test.dart
  // Plays all-computer games (with talk) and lists what the referee found.
  final games = int.tryParse(Platform.environment['AUDIT_GAMES'] ?? '');
  test('audit', () {
    final r = Random(int.parse(Platform.environment['AUDIT_SEED'] ?? '1'));
    final byRule = <String, List<String>>{};
    final byRole = <String, int>{};
    var audited = 0, skipped = 0, decisions = 0;
    for (var g = 0; g < games!; g++) {
      final setup = randomSetup(r);
      final seed = r.nextInt(1 << 30);
      play(setup, seed, true, (s) {
        final review = s.review!;
        final audit = BotAudit(review);
        if (!audit.supported) {
          skipped++;
          return;
        }
        audited++;
        for (final q in review.quests) {
          for (final p in q.proposals) {
            decisions += p.record.votes.length;
          }
        }
        for (final f in audit.findings()) {
          final role = review.roles[f.seat].label;
          byRole['${f.rule} $role'] = (byRole['${f.rule} $role'] ?? 0) + 1;
          byRule.putIfAbsent(f.rule, () => []).add(
              '第$g局（${_label(setup)}，種子$seed）${f.where} ${f.seat + 1}號$role：'
              '${f.what}${f.reason == null ? '' : '　［理由 ${f.reason}］'}');
        }
      });
    }
    final out = StringBuffer()
      ..writeln('裁判：$audited 局（跳過蘭斯洛特 $skipped 局），$decisions 張票')
      ..writeln();
    for (final rule in byRule.keys.toList()..sort()) {
      out.writeln('== $rule：${byRule[rule]!.length} 次');
      final roles = byRole.entries.where((e) => e.key.startsWith('$rule '));
      out.writeln('   ${[
        for (final e in roles) '${e.key.substring(rule.length + 1)} ${e.value}'
      ].join('、')}');
      for (final line in byRule[rule]!.take(12)) {
        out.writeln('   $line');
      }
      out.writeln();
    }
    if (byRule.isEmpty) out.writeln('沒有發現。');
    final path = Platform.environment['AUDIT_OUT'];
    if (path != null) File(path).writeAsStringSync('$out');
    // ignore: avoid_print
    print(out);
  },
      timeout: const Timeout(Duration(minutes: 60)),
      skip: games == null ? 'set AUDIT_GAMES to run' : false);
}

String _label(Setup s) => '${s.count}人 ${s.label}';

/// The provable mistakes the bots are held to (see [BotAudit]).
const guarded = {'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'H7', 'H8'};
