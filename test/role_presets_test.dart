import 'package:material_ui/material_ui.dart';
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
            [for (final r in rolePreset(n, lancelot: lancelot)!) r.label]);
        expect(room.roleIssue, isNull,
            reason: '$n players, lancelot $lancelot');
      }
    }
    // the setups most published tables recommend
    expect(rolePreset(5), {Role.percival, Role.morgana});
    expect(rolePreset(6), {Role.percival, Role.morgana});
    for (final n in [7, 8, 9]) {
      expect(rolePreset(n), {Role.percival, Role.morgana, Role.mordred});
    }
    expect(rolePreset(10),
        {Role.percival, Role.morgana, Role.mordred, Role.oberon});
  });

  test('Lancelot takes an evil place: Oberon goes first, then Mordred', () {
    expect(rolePreset(10, lancelot: true),
        {Role.percival, Role.morgana, Role.mordred});
    for (final n in [7, 8, 9]) {
      expect(rolePreset(n, lancelot: true), {Role.percival, Role.morgana});
    }
    // a setup that already has room keeps everything
    expect(fitForLancelot(10, {Role.percival, Role.mordred}),
        {Role.percival, Role.mordred});
  });

  testWidgets('changing the player count switches to its preset roles',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(theme: AvalonTheme.dark, home: const LocalPlayScreen()));
    await tester.pumpAndSettle();
    bool on(String role) =>
        tester
            .widget<Icon>(find.descendant(
                of: find.byKey(ValueKey('role$role')),
                matching: find.byType(Icon)))
            .icon ==
        Icons.check_circle;
    expect(on('派西維爾') && on('莫甘娜') && !on('莫德雷德'), isTrue);
    await tester.tap(find.byKey(const ValueKey('playerCount9')));
    await tester.pumpAndSettle();
    expect(on('莫德雷德') && on('莫甘娜') && !on('奧伯倫'), isTrue);
    // the player adjusts by hand; the next count change brings a new preset
    await tester.tap(find.byKey(const ValueKey('role奧伯倫')));
    await tester.pumpAndSettle();
    expect(on('奧伯倫'), isTrue);
    await tester.tap(find.byKey(const ValueKey('playerCount10')));
    await tester.pumpAndSettle();
    expect(on('莫甘娜') && on('莫德雷德') && on('奧伯倫'), isTrue);
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
    await tester.tap(find.byKey(const ValueKey('expansionLancelot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('變體一・每輪翻牌'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expansionSave')));
    await tester.pumpAndSettle();
    expect(find.text('蘭斯洛特（變體一）'), findsOneWidget);
    // the evil Lancelot needs a place: Mordred makes room for him
    bool on(String role) =>
        tester
            .widget<Icon>(find.descendant(
                of: find.byKey(ValueKey('role$role')),
                matching: find.byType(Icon)))
            .icon ==
        Icons.check_circle;
    expect(on('莫甘娜') && !on('莫德雷德'), isTrue);
    expect(find.textContaining('超過'), findsNothing);
    // fewer than 7: Lancelot is switched off and cannot be picked
    await tester.tap(find.byKey(const ValueKey('playerCount6')));
    await tester.pumpAndSettle();
    expect(find.textContaining('未使用'), findsOneWidget);
    await openExpansions();
    expect(find.textContaining('目前 6 人'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('expansionLancelot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('變體一・每輪翻牌'), warnIfMissed: false);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expansionSave')));
    await tester.pumpAndSettle();
    expect(find.textContaining('未使用'), findsOneWidget);
  });
}
