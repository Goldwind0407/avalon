import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/ambient_motion.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/game_screen.dart';
import 'package:avalon_shadow_council/features/game/game_session.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';
import 'package:avalon_shadow_council/features/table/components.dart';
import 'package:avalon_shadow_council/features/table/effects.dart';

Future<void> advance(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
      'decorative loops stop scheduling frames when idle and wake on touch',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: AmbientMotion(
      idleAfter: Duration(seconds: 1),
      child: Stack(children: [
        Particles(kind: ParticleKind.dust),
        Center(child: Floaty(child: PulseRing(diameter: 60))),
      ]),
    )));
    await advance(tester, 300);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await advance(tester, 1500);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.tapAt(const Offset(100, 100));
    await advance(tester, 100);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await advance(tester, 1500);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('idle stops floating without stopping the nested gameplay flip',
      (tester) async {
    var revealed = false;
    await tester.pumpWidget(MaterialApp(
        home: AmbientMotion(
      idleAfter: const Duration(milliseconds: 100),
      child: Center(
          child: Floaty(
              child: FlipCard(
        front: const Text('front'),
        back: const Text('back'),
        faceUp: true,
        flipOnMount: true,
        duration: const Duration(milliseconds: 900),
        onRevealed: () => revealed = true,
      ))),
    )));
    await advance(tester, 300);
    expect(revealed, isFalse);
    await advance(tester, 1000);
    expect(revealed, isTrue);
    expect(find.text('front'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('background disables ambient motion and foreground restores it',
      (tester) async {
    var enabled = false;
    await tester.pumpWidget(MaterialApp(home: AmbientMotion(
      child: Builder(builder: (context) {
        enabled = AmbientMotionScope.of(context);
        return const Particles(kind: ParticleKind.ember);
      }),
    )));
    expect(enabled, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(enabled, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(enabled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'real game rests on handoff and identity screens and remains playable',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final room = Room(
        code: '123456',
        players: List.generate(
            5, (i) => Player(id: '$i', name: '騎士$i', isReady: true)));
    await tester.pumpWidget(
        MaterialApp(theme: AvalonTheme.dark, home: GameScreen(room: room)));
    await advance(tester, 10000);
    expect(find.text('請將手機交給'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.tap(find.text('我是本人，開啟秘密畫面'));
    await advance(tester, 10000);
    expect(find.text('記住了，隱藏並交給下一位').hitTestable(), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.tap(find.text('記住了，隱藏並交給下一位'));
    await advance(tester, 1800);
    expect(find.text('請將手機交給'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final dynamic screen = tester.state(find.byType(GameScreen));
    final AvalonGame game = (screen.game as LocalGameSession).game;
    screen.act(() {
      while (game.phase == GamePhase.identity) {
        game.confirmIdentity();
      }
    });
    await advance(tester, 10000);
    expect(find.text('第 1 次遠征'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
