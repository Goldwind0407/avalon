import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/main.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/lobby/lobby_screen.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';
import 'package:avalon_shadow_council/features/table/components.dart';

void main() {
  testWidgets('首頁能建立房間並進入大廳', (tester) async {
    await tester.pumpWidget(const AvalonApp());
    expect(find.text('AVALON'), findsOneWidget);
    await tester.tap(find.text('建立私人房間'));
    await tester.pumpAndSettle();
    expect(find.text('私人議會'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('新增同機玩家'), 300);
    expect(find.text('新增同機玩家'), findsOneWidget);
    await tester.tap(find.text('新增同機玩家'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '亞瑟');
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('亞瑟'), -250);
    expect(find.text('亞瑟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('從大廳開始，秘密交接與背景隱藏，完成發牌後組隊', (tester) async {
    // the app is landscape only
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The table has looping animations (current-quest glow), so the screen
    // never "settles"; advance time explicitly instead of pumpAndSettle.
    Future<void> settle([int ms = 1500]) async {
      for (var t = 0; t < ms; t += 50) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final repository = LocalRoomRepository();
    final room = repository.create('亞瑟');
    for (var i = 0; i < 4; i++) {
      repository.addDemoPlayer(room);
    }
    room.players.first.isReady = true;
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark,
        home: LobbyScreen(room: room, repository: repository)));
    await tester.scrollUntilVisible(find.text('開始對局'), 400);
    await tester.tap(find.text('開始對局'));
    // the role cards are dealt to every seat before the first hand-off
    await settle(3500);
    expect(find.text('請將手機交給'), findsOneWidget);
    expect(find.text('梅林'), findsNothing);
    await tester.tap(find.text('我是本人，開啟秘密畫面'));
    await settle();
    expect(find.text('請將手機交給'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle();
    expect(find.text('請將手機交給'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // Entrance animations are muted while the app is inactive. Let the
    // resumed handoff finish before attempting to press its button.
    await settle();
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('我是本人，開啟秘密畫面'));
      // The identity button appears after the card and all information lines;
      // fading controls now remain disabled until their entrance completes.
      await settle(2200);
      expect(find.text('記住了，隱藏並交給下一位').hitTestable(), findsOneWidget);
      await tester.tap(find.text('記住了，隱藏並交給下一位'));
      await settle();
    }
    expect(find.text('第 1 次遠征'), findsOneWidget);
    // every player has a seat at the table; the leader picks the team there
    expect(find.byType(SeatPlate), findsNWidgets(5));
    // let the "first quest" announcement pass before picking the team
    await settle(2500);
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await settle();
    expect(find.text('提案並開始投票（2/2）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
