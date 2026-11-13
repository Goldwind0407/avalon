import 'dart:math';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/player_speech.dart';
import 'package:avalon_shadow_council/features/solo/game_review.dart';
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
}
