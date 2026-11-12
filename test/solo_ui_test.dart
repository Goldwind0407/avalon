import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/home/home_screen.dart';
import 'package:avalon_shadow_council/features/home/local_play_screen.dart';
import 'package:avalon_shadow_council/features/game/game_screen.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/solo/solo_session.dart';
import 'solo_session_test.dart' show soloRoom, humanMove;

Future<void> advanceSolo(WidgetTester tester, int ms) async {
  for (var n = 0; n < ms; n += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  var theme = AvalonTheme.dark;
  final capture = Platform.environment['SOLO_CAPTURE'] == '1';
  setUpAll(() async {
    if (capture && Platform.isWindows) {
      final font = FontLoader('SoloPreview')
        ..addFont(File('C:/Windows/Fonts/msjh.ttc')
            .readAsBytes()
            .then(ByteData.sublistView));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      theme = theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'SoloPreview'));
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'a complete solo game keeps shared table animations and secrets safe',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final room = soloRoom(
        7, const ExpansionSettings(lady: true, excalibur: true, lancelot: 2));
    final session = SoloGameSession(room,
        random: Random(8),
        botDelay: const Duration(milliseconds: 50),
        speechDuration: const Duration(milliseconds: 250));
    await tester.pumpWidget(
        MaterialApp(theme: theme, home: GameScreen.online(session: session)));
    await advanceSolo(tester, 5000);
    final rng = Random(50);
    var steps = 0;
    while (session.phase != GamePhase.finished && steps++ < 800) {
      if (session.hasPrivateInput ||
          [GamePhase.voteResult, GamePhase.questResult]
              .contains(session.phase)) {
        if ([GamePhase.voteResult, GamePhase.questResult]
            .contains(session.phase)) {
          await advanceSolo(tester, 2200);
        }
        humanMove(session, rng);
      }
      await advanceSolo(tester, 100);
      expect(find.text('請將手機交給'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(session.phase, GamePhase.finished);
    await advanceSolo(tester, 5000);
    if (session.assassinTarget != null) {
      await tester.tap(find.text('揭曉全員身分'));
      await advanceSolo(tester, 5000);
    }
    expect(find.text('${session.winner}陣營獲勝'), findsOneWidget);
    final generation = session.generation;
    await tester.tap(find.text('相同配置，再玩一局'));
    await advanceSolo(tester, 5000);
    expect(session.generation, generation + 1);
    expect(session.phase, GamePhase.identity);
    expect(find.text('記住了'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets('home opens solo setup and keeps all 5–10 seats visible',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final size in [const Size(667, 320), const Size(844, 390)]) {
      tester.view.physicalSize = size;
      await tester
          .pumpWidget(MaterialApp(theme: theme, home: const HomeScreen()));
      await tester.tap(find.byKey(const ValueKey('openSolo')));
      await tester.pumpAndSettle();
      expect(tester.widget<LocalPlayScreen>(find.byType(LocalPlayScreen)).solo,
          isTrue);
      expect(find.text('跟電腦遊玩'), findsOneWidget);
      for (var count = 5; count <= 10; count++) {
        await tester.tap(find.byKey(ValueKey('playerCount$count')));
        await tester.pumpAndSettle();
        expect(find.text('開始遊戲').hitTestable(), findsOneWidget);
        expect(find.byKey(ValueKey('playerName${count - 1}')).hitTestable(),
            findsOneWidget);
        expect(find.byType(Scrollable), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets(
      'solo hides BOT identities, displays speech and pauses while reading history',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = SoloGameSession(soloRoom(7, const ExpansionSettings()),
        random: Random(3));
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: RepaintBoundary(
            key: boundary, child: GameScreen.online(session: session))));
    await advanceSolo(tester, 5000);
    expect(find.text(session.roleOf(0)!.label), findsOneWidget);
    expect(find.text('記住了，隱藏並交給下一位'), findsNothing);
    await tester.tap(find.text('記住了'));
    await advanceSolo(tester, 4500);
    if (session.phase == GamePhase.team) {
      await session.proposeTeam([0, 1]);
      await tester.pump();
    }
    if (session.speaker == 0) {
      await session.expressOpinion(true);
      await tester.pump();
    }
    await advanceSolo(tester, 100);
    expect(session.phase, GamePhase.discussion);
    expect(find.byKey(const ValueKey('botSpeech')), findsOneWidget);
    expect(find.text('稍後自動過麥'), findsOneWidget);
    for (var s = 1; s < 7; s++) {
      expect(session.roleOf(s), isNull);
      expect(find.byKey(ValueKey('identitySeen$s')), findsNothing);
    }
    if (capture) {
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/solo-discussion-preview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    final version = session.speechVersion;
    await tester.tap(find.byTooltip('討論紀錄'));
    await advanceSolo(tester, 9000);
    expect(session.speechVersion, version);
    expect(find.text('返回對局'), findsOneWidget);
    await tester.tap(find.text('返回對局'));
    await advanceSolo(tester, 5500);
    expect(session.speechVersion, greaterThan(version));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('solo setup lets the player choose the computer level',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final size in [const Size(667, 320), const Size(932, 430)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
          theme: AvalonTheme.dark,
          home: LocalPlayScreen(key: UniqueKey(), solo: true)));
      await tester.pumpAndSettle();
      expect(find.text('難度：一般'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size');
      await tester.tap(find.byKey(const ValueKey('botDifficulty')));
      await tester.pumpAndSettle();
      expect(find.text('新手'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('botDifficulty_expert')));
      await tester.pumpAndSettle();
      expect(find.text('難度：高手'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size');
    }
    // pass & play has no computer players, so no level to choose
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark, home: LocalPlayScreen(key: UniqueKey())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('botDifficulty')), findsNothing);
  });
}
