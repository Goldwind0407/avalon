import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_screen.dart';
import 'package:avalon_shadow_council/features/game/game_session.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';

/// A real local deal shown as one online seat, without the initial deal wait.
class IdentitySession extends LocalGameSession {
  IdentitySession(Role role, {this.online = true})
      : super(
            Room(
                code: 'identity',
                players: List.generate(
                    10,
                    (i) => Player(
                        id: 'u$i', name: '玩家$i甲乙丙丁戊己庚辛壬癸甲乙丙', isReady: true)))
              ..specialRoles.addAll({
                '派西維爾',
                '莫甘娜',
                '奧伯倫',
                if (role != Role.minion &&
                    role != Role.merlin &&
                    !role.isLancelot)
                  '莫德雷德'
              })
              ..expansions =
                  ExpansionSettings(lancelot: role.isLancelot ? 1 : 0),
            random: Random(42)) {
    seat = game.roles.indexOf(role);
    while (game.actor < seat) {
      game.confirmIdentity();
    }
  }
  final bool online;
  late final int seat;
  @override
  int? get mySeat => online ? seat : null;
  @override
  Set<int> get confirmedSeats => online
      ? {
          for (var i = 0; i < players.length; i++)
            if (i != seat) i
        }
      : super.confirmedSeats;
}

void main() {
  var theme = AvalonTheme.dark;
  final capture = Platform.environment['IDENTITY_CAPTURE'] == '1';
  setUpAll(() async {
    if (capture && Platform.isWindows) {
      final font = FontLoader('IdentityPreview')
        ..addFont(File('C:/Windows/Fonts/msjh.ttc')
            .readAsBytes()
            .then(ByteData.sublistView));
      await font.load();
      theme = AvalonTheme.dark.copyWith(
          textTheme:
              AvalonTheme.dark.textTheme.apply(fontFamily: 'IdentityPreview'));
    }
  });
  for (final role in Role.values) {
    testWidgets(
        '${role.name}: long names and larger text stay readable on landscape phones',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final size in [
        const Size(667, 320),
        const Size(844, 390),
        const Size(932, 430)
      ]) {
        for (final scale in [1.0, 1.3]) {
          tester.view.physicalSize = size;
          tester.view.padding =
              const FakeViewPadding(left: 45, right: 45, bottom: 21);
          final game = IdentitySession(role);
          expect(game.seat, greaterThanOrEqualTo(0));
          final boundary = GlobalKey();
          await tester.pumpWidget(MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: RepaintBoundary(
                  key: boundary,
                  child: GameScreen.online(key: UniqueKey(), session: game))));
          for (var t = 0; t < 2700; t += 100) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (capture &&
              role == Role.merlin &&
              size.width == 844 &&
              scale == 1) {
            await tester.runAsync(() async {
              for (final widget
                  in tester.widgetList<Image>(find.byType(Image))) {
                await precacheImage(widget.image, boundary.currentContext!);
              }
            });
            await tester.pump();
            await tester.runAsync(() async {
              final renderer = boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
              final picture = await renderer.toImage(pixelRatio: 1.5);
              final bytes =
                  await picture.toByteData(format: ui.ImageByteFormat.png);
              await File('build/identity-preview.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              picture.dispose();
            });
          }
          expect(tester.takeException(), isNull,
              reason: '$role / $size / $scale');
          final title =
              tester.renderObject<RenderParagraph>(find.text(role.label));
          expect(
              title
                  .getBoxesForSelection(TextSelection(
                      baseOffset: 0, extentOffset: role.label.length))
                  .length,
              1,
              reason: 'Role title must not split across lines');
          final panel = find.byKey(const ValueKey('identityKnowledge'));
          for (final seat in game.visiblePlayers(game.seat)) {
            final label = playerLabel(seat, game.players[seat]);
            final name = tester.renderObject<RenderParagraph>(
                find.descendant(of: panel, matching: find.text(label)));
            expect(
                name
                    .getBoxesForSelection(TextSelection(
                        baseOffset: 0, extentOffset: label.length))
                    .length,
                1,
                reason: 'A seat and nickname must stay together');
          }
          final reminder = roleInformation(role).reminder;
          final paragraph =
              tester.renderObject<RenderParagraph>(find.text(reminder));
          expect(
              paragraph
                  .getBoxesForSelection(TextSelection(
                      baseOffset: 0, extentOffset: reminder.length))
                  .length,
              reminder.split('\n').length,
              reason: 'Reminders only break at intentional line endings');
          expect(find.text('記住了').hitTestable(), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          game.dispose();
        }
      }
    });
  }
  testWidgets('local handoff and identity keep a long nickname intact',
      (tester) async {
    tester.view.physicalSize = const Size(667, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = IdentitySession(Role.merlin, online: false);
    addTearDown(game.dispose);
    await tester.pumpWidget(
        MaterialApp(theme: theme, home: GameScreen.online(session: game)));
    for (var t = 0; t < 3500; t += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final label = playerLabel(game.seat, game.players[game.seat]);
    final handoff = tester.renderObject<RenderParagraph>(find.text(label));
    expect(
        handoff
            .getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: label.length))
            .length,
        1);
    await tester.tap(find.text('我是本人，開啟秘密畫面'));
    for (var t = 0; t < 2700; t += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('identityKnowledge')), findsOneWidget);
    expect(find.text('記住了，隱藏並交給下一位').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
