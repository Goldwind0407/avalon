import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/game_screen.dart';
import 'package:avalon_shadow_council/features/game/game_session.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';
import 'package:avalon_shadow_council/features/table/effects.dart';

Future<void> advance(WidgetTester tester, int ms) async {
  // Step through timers and flights rather than jumping over their callbacks.
  for (var elapsed = 0; elapsed < ms; elapsed += 20) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('fading controls ignore taps until fully visible',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
      child: Appear(
        delay: const Duration(seconds: 1),
        child: TextButton(onPressed: () => taps++, child: const Text('繼續')),
      ),
    ))));
    await tester.tapAt(tester.getCenter(find.text('繼續')));
    expect(taps, 0);
    await advance(tester, 1200);
    await tester.tapAt(tester.getCenter(find.text('繼續')));
    expect(taps, 0);
    await advance(tester, 300);
    await tester.tap(find.text('繼續'));
    expect(taps, 1);
  });

  for (final count in [5, 10]) {
    testWidgets(
        '$count players: last vote lands and flips before fifth-rejection verdict',
        (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final room = Room(
          code: '123456',
          players: List.generate(
              count, (i) => Player(id: '$i', name: '騎士$i', isReady: true)));
      await tester.pumpWidget(
          MaterialApp(theme: AvalonTheme.dark, home: GameScreen(room: room)));
      await advance(tester, 3500);
      final dynamic screen = tester.state(find.byType(GameScreen));
      final AvalonGame game = (screen.game as LocalGameSession).game;
      // Reach the fifth proposal without replaying the first four UI rounds.
      screen.act(() {
        for (var i = 0; i < count; i++) {
          game.confirmIdentity();
        }
        for (var attempt = 0; attempt < 4; attempt++) {
          game.proposeTeam(List.generate(game.requiredTeam, (i) => i));
          for (var i = 0; i < count; i++) {
            game.vote(false);
          }
          game.continueVote();
        }
        game.proposeTeam(List.generate(game.requiredTeam, (i) => i));
        for (var i = 0; i < count - 1; i++) {
          game.vote(false);
        }
      });
      await advance(tester, 1000);
      expect(game.rejections, 4);
      await tester.tap(find.text('我是本人，開啟秘密畫面'));
      await advance(tester, 800);
      await tester.tap(find.text('反對'));
      await advance(tester, 300);
      await tester.tap(find.text('蓋牌投出'));
      await advance(tester, 460);
      expect(game.phase, GamePhase.voteResult);

      // After two seconds the verdict used to start appearing even though
      // the last card's flight + stagger + flip was still in progress.
      await advance(tester, 2000);
      expect(find.text('否決'), findsNothing);
      expect(find.text('邪惡獲勝・查看結算'), findsNothing);
      expect(game.phase, GamePhase.voteResult);

      await advance(tester, 2200);
      expect(find.text('否決'), findsOneWidget);
      expect(find.text('邪惡獲勝・查看結算'), findsOneWidget);
      await tester.tap(find.text('邪惡獲勝・查看結算'));
      await advance(tester, 1500);
      expect(game.phase, GamePhase.finished);
      expect(game.rejections, 5);
      expect(game.winner, '邪惡');
      expect(find.text('邪惡陣營獲勝'), findsOneWidget);
      expect(() => game.proposeTeam([0, 1]), throwsStateError);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
