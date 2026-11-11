import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/home/local_play_screen.dart';

void main() {
  testWidgets('5–10 player setup fits landscape screens without scrolling',
      (tester) async {
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
      await tester.pumpWidget(
          MaterialApp(theme: AvalonTheme.dark, home: const LocalPlayScreen()));
      for (var count = 5; count <= 10; count++) {
        await tester.tap(find.byKey(ValueKey('playerCount$count')));
        await tester.pumpAndSettle();
        for (var i = 0; i < count; i++) {
          expect(find.byKey(ValueKey('playerName$i')).hitTestable(),
              findsOneWidget);
        }
        expect(find.text('開始遊戲').hitTestable(), findsOneWidget);
        expect(find.byKey(const ValueKey('role奧伯倫')).hitTestable(),
            findsOneWidget);
        expect(find.byType(Scrollable), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
      'role capacity disables start and recovers when the player count grows',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(theme: AvalonTheme.dark, home: const LocalPlayScreen()));
    await tester.tap(find.byKey(const ValueKey('role莫甘娜')));
    await tester.tap(find.byKey(const ValueKey('role莫德雷德')));
    await tester.pumpAndSettle();
    expect(find.text('邪惡角色超過本局邪惡陣營名額'), findsOneWidget);
    ElevatedButton start() => tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '開始遊戲'));
    expect(start().onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('playerCount10')));
    await tester.pumpAndSettle();
    expect(start().onPressed, isNotNull);
    expect(find.text('邪惡角色超過本局邪惡陣營名額'), findsNothing);
  });
}
