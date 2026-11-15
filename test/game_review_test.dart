import 'dart:math';
import 'package:fake_async/fake_async.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/player_speech.dart';
import 'package:avalon_shadow_council/features/solo/game_review.dart';
import 'package:avalon_shadow_council/features/solo/review_export.dart';
import 'package:avalon_shadow_council/features/solo/review_screen.dart';
import 'package:avalon_shadow_council/features/solo/solo_session.dart';
import 'solo_session_test.dart' show soloRoom;

/// Plays one solo game to the end as a simple human, saying a few things.
GameReview played(int seed, {int count = 7, ExpansionSettings? e}) {
  late GameReview review;
  fakeAsync((time) {
    final s = SoloGameSession(soloRoom(count, e ?? const ExpansionSettings()),
        random: Random(seed),
        botDelay: const Duration(milliseconds: 1),
        speechDuration: const Duration(milliseconds: 1));
    expect(s.review, isNull, reason: 'no review while the game is on');
    var steps = 0;
    while (s.phase != GamePhase.finished && steps++ < 4000) {
      if (s.hasPrivateInput ||
          [GamePhase.voteResult, GamePhase.questResult].contains(s.phase)) {
        switch (s.phase) {
          case GamePhase.identity:
            s.confirmIdentity(0);
          case GamePhase.team:
            final team = List.generate(s.requiredTeam, (i) => i);
            s.proposeTeam(team,
                excalibur: s.expansions.excalibur ? team[1] : null);
          case GamePhase.discussion:
            s.say(const PlayerSpeech(PlayerSpeechKind.suspect, target: 2));
            s.expressOpinion(s.questNumber.isOdd);
          case GamePhase.vote:
            s.vote(0, true);
          case GamePhase.voteResult:
            s.continueVote();
          case GamePhase.quest:
            s.playQuest(0, !s.evilNow(0)!);
          case GamePhase.questResult:
            s.continueQuest();
          case GamePhase.lady:
            s.useLady(List.generate(count, (i) => i)
                .firstWhere((i) => !s.ladyPast.contains(i)));
          case GamePhase.ladyResult:
            s.continueLady();
          case GamePhase.excalibur:
            s.useExcalibur(null);
          case GamePhase.excaliburResult:
            s.continueExcalibur();
          case GamePhase.assassination:
            s.assassinate(1);
          default:
            break;
        }
      } else {
        time.elapse(const Duration(milliseconds: 1));
      }
      time.flushMicrotasks();
    }
    review = s.review!;
    s.dispose();
    time.flushMicrotasks();
  });
  return review;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the review holds every proposal, vote reason, line source and card',
      () {
    for (var seed = 0; seed < 6; seed++) {
      final r =
          played(seed, e: const ExpansionSettings(lady: true, excalibur: true));
      expect(r.quests, isNotEmpty);
      for (final q in r.quests) {
        expect(q.proposals, isNotEmpty);
        for (final round in q.proposals) {
          // every bot's final ballot is explained, and matches the record
          for (var s = 1; s < r.players.length; s++) {
            final d = round.decisions[s];
            expect(d, isNotNull, reason: 'seed $seed q${q.number} seat $s');
            expect(d!.approve, round.record.votes[s]);
          }
          for (final l in round.lines) {
            if (l.statement.speaker == 0) {
              expect(l.source, isNull);
            } else {
              expect(l.source, isNotNull,
                  reason: 'bot line without a source: ${l.statement.text}');
            }
          }
        }
        if (q.result case final result?) {
          expect(q.cards.keys.toSet(), result.team.toSet());
          // the original cards, with a sword flip applied, add up to the
          // Fail cards that were shown
          final shown = {
            for (final e in q.cards.entries)
              e.key: e.key == result.excaliburTarget ? !e.value : e.value
          };
          expect(shown.values.where((c) => !c).length, result.fails);
        }
      }
      expect(r.scores.map((s) => s.title), containsAll(['投票', '當隊長', '點名']));
      expect(r.roles.length, r.players.length);
    }
  });

  testWidgets('every review page fits a small landscape phone', (tester) async {
    final r = played(3, e: const ExpansionSettings(lady: true));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final size in [const Size(667, 320), const Size(932, 430)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
          theme: AvalonTheme.dark,
          home: ReviewScreen(key: UniqueKey(), review: r)));
      await tester.pumpAndSettle();
      expect(find.text('你的表現'), findsWidgets);
      for (var p = 0; p <= r.quests.length + 1; p++) {
        final tile = find.byKey(ValueKey('reviewPage$p'));
        if (tile.evaluate().isEmpty) continue;
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'page $p at $size');
      }
    }
  });

  test('the whole game can be written out as text', () {
    final r = played(5,
        count: 8, e: const ExpansionSettings(lady: true, excalibur: true));
    final text =
        reviewText(r, difficulty: '一般', endedAt: DateTime(2026, 11, 15, 21, 5));
    expect(text, contains('時間：2026-11-15 21:05'));
    expect(text, contains('難度：一般'));
    expect(text, contains('擴充：湖中女神、王者之劍'));
    for (var s = 0; s < r.players.length; s++) {
      expect(text, contains('${s + 1}號${r.players[s]}：${r.roles[s].label}'));
    }
    expect(text, contains('← 你'));
    for (final q in r.quests) {
      expect(text, contains('== 第${q.number}次遠征'));
      for (final round in q.proposals) {
        expect(text, contains('提案${round.record.attempt}：'));
        for (final line in round.lines) {
          expect(text, contains(line.statement.text));
        }
      }
    }
    // where a computer line came from, and the player's own
    expect(text, contains('［你］'));
    expect(text, contains('［'));
    // every vote, with the computer's reason
    expect(RegExp(r'   \d+[○✕]').allMatches(text).length,
        r.quests.expand((q) => q.proposals).length * r.players.length);
    expect(text, contains('隊伍風險'));
    final out = Platform.environment['REVIEW_SAMPLE'];
    if (out != null) File(out).writeAsStringSync(text);
  });

  testWidgets('the review copies the whole game as text', (tester) async {
    final r = played(3);
    tester.view.physicalSize = const Size(932, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark,
        home: ReviewScreen(review: r, difficulty: '一般')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reviewShare')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reviewCopy')));
    await tester.pumpAndSettle();
    expect(copied, contains('阿瓦隆 單人模式 復盤'));
    expect(copied, contains('== 第1次遠征'));
    expect(find.text('已複製整局復盤文字'), findsOneWidget);
  });
}
