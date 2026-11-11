import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/main.dart';
import 'package:avalon_shadow_council/features/rules/rules_screen.dart';

void main() {
  testWidgets('every rules topic fits small landscape phones', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final size in [const Size(667, 320), const Size(932, 430)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
          theme: AvalonTheme.dark, home: const RulesScreen()));
      await tester.pumpAndSettle();
      for (final topic in RulesTopic.values) {
        final tile = find.byKey(ValueKey('rules_${topic.name}'));
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(find.text(topic.title), findsWidgets);
        expect(tester.takeException(), isNull, reason: '${topic.name} $size');
      }
    }
    expect(find.byKey(const ValueKey('playersTable')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('rules_players')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rules_players')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('playersTable')), findsOneWidget);
  });

  testWidgets('the home screen opens the rules', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const AvalonApp(intro: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('openRules')));
    await tester.pumpAndSettle();
    expect(find.byType(RulesScreen), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('rulesNext')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rulesNext')));
    await tester.pumpAndSettle();
    expect(find.text('一輪怎麼玩'), findsWidgets);
  });
}
