import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/home/local_play_screen.dart';
import 'package:avalon_shadow_council/features/lobby/role_presets.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';

void main() {
  test('every preset is a legal setup, with or without Lancelot', () {
    for (var n = 5; n <= 10; n++) {
      for (final lancelot in [false, if (n >= 7) true]) {
        final room = Room(
            code: '',
            players: List.generate(
                n, (i) => Player(id: '$i', name: '$i', isReady: true)))
          ..expansions = ExpansionSettings(lancelot: lancelot ? 1 : 0);
        room.specialRoles.addAll(
            [for (final r in rolePreset(n)!) r.label]);
        expect(room.roleIssue, isNull, reason: '$n players, lancelot $lancelot');
      }
    }
    expect(rolePreset(9), {Role.percival, Role.mordred});
    expect(rolePreset(10), {Role.percival, Role.morgana, Role.mordred});
  });

  testWidgets('changing the player count switches to its preset roles',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(theme: AvalonTheme.dark, home: const LocalPlayScreen()));
    await tester.pumpAndSettle();
    bool on(String role) => tester
        .widget<Icon>(find.descendant(
            of: find.byKey(ValueKey('role$role')),
            matching: find.byType(Icon)))
        .icon == Icons.check_circle;
    expect(on('派西維爾') && on('莫甘娜') && !on('莫德雷德'), isTrue);
    await tester.tap(find.byKey(const ValueKey('playerCount9')));
    await tester.pumpAndSettle();
    expect(on('莫德雷德') && !on('莫甘娜'), isTrue);
    // the player adjusts by hand; the next count change brings a new preset
    await tester.tap(find.byKey(const ValueKey('role奧伯倫')));
    await tester.pumpAndSettle();
    expect(on('奧伯倫'), isTrue);
    await tester.tap(find.byKey(const ValueKey('playerCount10')));
    await tester.pumpAndSettle();
    expect(on('莫甘娜') && on('莫德雷德') && !on('奧伯倫'), isTrue);
    // no expansion is switched on by a preset
    expect(find.textContaining('未使用'), findsOneWidget);
  });

  testWidgets('Lancelot needs 7 players in pass & play setup', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(theme: AvalonTheme.dark, home: const LocalPlayScreen()));
    await tester.pumpAndSettle();
    Future<void> openExpansions() async {
      await tester.tap(find.byKey(const ValueKey('expansions')));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const ValueKey('playerCount8')));
    await tester.pumpAndSettle();
    await openExpansions();
    await tester.tap(find.text('變體一・每輪翻牌'));
    await tester.tap(find.byKey(const ValueKey('expansionSave')));
    await tester.pumpAndSettle();
    expect(find.text('蘭斯洛特（變體一）'), findsOneWidget);
    // fewer than 7: Lancelot is switched off and cannot be picked
    await tester.tap(find.byKey(const ValueKey('playerCount6')));
    await tester.pumpAndSettle();
    expect(find.textContaining('未使用'), findsOneWidget);
    await openExpansions();
    expect(find.textContaining('目前 6 人'), findsOneWidget);
    await tester.tap(find.text('變體一・每輪翻牌'), warnIfMissed: false);
    await tester.tap(find.byKey(const ValueKey('expansionSave')));
    await tester.pumpAndSettle();
    expect(find.textContaining('未使用'), findsOneWidget);
  });
}
