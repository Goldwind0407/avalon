import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/main.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/home/local_play_screen.dart';
import 'package:avalon_shadow_council/features/table/components.dart';

void main() {
  testWidgets('一機遊玩直接設定玩家並開始遊戲', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const AvalonApp(intro: false));
    expect(find.text('AVALON'), findsOneWidget);
    await tester.tap(find.text('一機遊玩'));
    await tester.pumpAndSettle();
    expect(tester.widget<LocalPlayScreen>(find.byType(LocalPlayScreen)).solo,
        isFalse);
    expect(find.text('建立私人房間'), findsNothing);
    expect(find.text('返回本機房間'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('playerName0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '亞瑟');
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(find.text('亞瑟'), findsOneWidget);
    await tester.tap(find.text('開始遊戲'));
    for (var elapsed = 0; elapsed < 3500; elapsed += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('請將手機交給'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('橫向首頁顯示三個遊玩模式，不需要捲動', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.padding =
        const FakeViewPadding(left: 59, right: 59, bottom: 21);
    addTearDown(tester.view.reset);
    for (final size in [
      const Size(667, 320),
      const Size(844, 390),
      const Size(932, 430)
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const AvalonApp(intro: false));
      await tester.pumpAndSettle();
      expect(find.text('AVALON'), findsOneWidget);
      expect(find.text('一機遊玩').hitTestable(), findsOneWidget);
      expect(find.text('多機遊玩').hitTestable(), findsOneWidget);
      expect(find.text('跟電腦遊玩（測試中）').hitTestable(), findsOneWidget);
      expect(find.byType(Scrollable), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    }
    // online play opens its own page (it only connects when a room is made)
    await tester.tap(find.text('多機遊玩'));
    await tester.pumpAndSettle();
    expect(find.text('建立房間'), findsOneWidget);
    expect(find.text('加入'), findsOneWidget);
    await tester.tap(find.byTooltip('返回首頁'));
    await tester.pumpAndSettle();
    expect(find.text('一機遊玩').hitTestable(), findsOneWidget);
  });

  testWidgets('一機遊玩：秘密交接與背景隱藏，完成發牌後組隊', (tester) async {
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

    await tester.pumpWidget(
        MaterialApp(theme: AvalonTheme.dark, home: const LocalPlayScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始遊戲'));
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
