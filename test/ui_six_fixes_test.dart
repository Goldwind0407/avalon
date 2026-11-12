import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_widgets.dart';
import 'package:avalon_shadow_council/features/game/local_vote_panel.dart';
import 'package:avalon_shadow_council/features/home/local_play_screen.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';
import 'package:avalon_shadow_council/features/table/components.dart';
import 'package:avalon_shadow_council/features/table/expansion_pieces.dart';
import 'package:avalon_shadow_council/features/online/online_session.dart';
import 'package:avalon_shadow_council/features/online/online_room_screen.dart';
import 'package:avalon_shadow_council/features/online/voice/voice_controller.dart';
import 'dart:async';
import 'voice_controller_test.dart' show FakeVoiceTransport;

final reviewKey = GlobalKey();
var reviewTheme = AvalonTheme.dark;
Future<void> pumpReview(WidgetTester tester, Widget app) =>
    tester.pumpWidget(RepaintBoundary(key: reviewKey, child: app));
Future<void> captureReview(WidgetTester tester, String name) async {
  if (Platform.environment['UI_SIX_CAPTURE'] != '1') return;
  await tester.runAsync(() async {
    final boundary =
        reviewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await File('build/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (Platform.environment['UI_SIX_CAPTURE'] == '1' && Platform.isWindows) {
      final font = FontLoader('Review')
        ..addFont(File('C:/Windows/Fonts/msjh.ttc')
            .readAsBytes()
            .then(ByteData.sublistView));
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await Future.wait([font.load(), icons.load()]);
      reviewTheme = AvalonTheme.dark.copyWith(
          textTheme: AvalonTheme.dark.textTheme.apply(fontFamily: 'Review'),
          elevatedButtonTheme: ElevatedButtonThemeData(
              style: AvalonTheme.dark.elevatedButtonTheme.style!.copyWith(
                  textStyle: const WidgetStatePropertyAll(TextStyle(
                      fontFamily: 'Review',
                      fontSize: 16,
                      fontWeight: FontWeight.bold)))));
    }
  });
  test('public ballots validate atomically and retain one complete proposal',
      () {
    final room = Room(
        code: '',
        players: List.generate(
            5, (i) => Player(id: '$i', name: '玩家$i', isReady: true)));
    final game = AvalonGame(room, random: Random(2));
    for (var i = 0; i < 5; i++) {
      game.confirmIdentity();
    }
    game.proposeTeam([0, 1]);
    expect(() => game.recordVotes([true]), throwsArgumentError);
    expect(game.actor, 0);
    expect(game.proposals, isEmpty);
    game.recordVotes([true, false, true, false, true]);
    expect(game.phase, GamePhase.voteResult);
    expect(game.teamApproved, isTrue);
    expect(game.proposals.single.votes, [true, false, true, false, true]);
    expect(() => game.recordVotes(List.filled(5, false)), throwsStateError);
    expect(game.proposals.length, 1);
  });

  test(
      'private hints mention only configured roles and actual Lancelot variant',
      () {
    const base = {Role.merlin, Role.assassin, Role.percival};
    expect(
        roleInformation(Role.merlin, configuredRoles: base).reminder, isEmpty);
    final percival = roleInformation(Role.percival, configuredRoles: base);
    expect(percival.heading, '你看見的梅林');
    expect(percival.reminder, isNot(contains('莫甘娜')));
    expect(roleInformation(Role.assassin, configuredRoles: base).reminder,
        isEmpty);
    expect(
        roleInformation(Role.merlin, configuredRoles: {...base, Role.mordred})
            .reminder,
        contains('莫德雷德'));
    expect(
        roleInformation(Role.assassin, configuredRoles: {...base, Role.oberon})
            .reminder,
        contains('奧伯倫'));
    expect(
        roleInformation(Role.percival, configuredRoles: {...base, Role.morgana})
            .heading,
        '梅林候選人');
    expect(
        roleInformation(Role.lancelotGood,
                expansions: const ExpansionSettings(lancelot: 2))
            .reminder,
        contains('公開'));
  });

  testWidgets('public ballot table fits every phone with ten long nicknames',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    List<bool>? received;
    for (final size in [
      const Size(667, 320),
      const Size(844, 390),
      const Size(932, 430)
    ]) {
      tester.view.physicalSize = size;
      tester.view.padding =
          const FakeViewPadding(left: 59, right: 59, bottom: 21);
      await pumpReview(
          tester,
          MaterialApp(
              theme: reviewTheme,
              home: Scaffold(
                  body: SafeArea(
                      child: LocalVotePanel(
                          key: ValueKey(size),
                          players: List.filled(10, '甲乙丙丁戊己庚辛壬癸甲乙丙丁戊己'),
                          leader: 3,
                          team: [0, 4, 5],
                          onSubmit: (v) async {
                            received = v;
                          })))));
      await tester.pump();
      final confirm = find.byKey(const ValueKey('submitLocalVotes'));
      expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.byKey(ValueKey('localVote$i/${i.isEven}')));
        await tester.pump();
      }
      expect(confirm.hitTestable(), findsOneWidget);
      await tester.tap(confirm);
      await tester.pump();
      expect(received, List.generate(10, (i) => i.isEven));
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.takeException(), isNull);
      if (size.width == 844) {
        await captureReview(tester, 'public-votes-preview');
      }
    }
  });

  testWidgets('all expansion controls remain visible without scrolling',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final size in [const Size(667, 320), const Size(844, 390)]) {
      tester.view.physicalSize = size;
      tester.view.padding =
          const FakeViewPadding(left: 59, right: 59, bottom: 21);
      ExpansionSettings? chosen;
      await pumpReview(
          tester,
          MaterialApp(
              theme: reviewTheme,
              home: Scaffold(
                  body: Builder(
                      builder: (context) => TextButton(
                          onPressed: () async {
                            chosen = await editExpansions(
                                context, const ExpansionSettings(),
                                players: 7);
                          },
                          child: const Text('設定擴充'))))));
      await tester.tap(find.text('設定擴充'));
      await tester.pumpAndSettle();
      expect(find.byType(Scrollable), findsNothing);
      expect(find.byKey(const ValueKey('expansionLady')).hitTestable(),
          findsOneWidget);
      expect(find.byKey(const ValueKey('expansionLancelot')).hitTestable(),
          findsOneWidget);
      final sword = find.byKey(const ValueKey('expansionExcalibur'));
      expect(sword.hitTestable(), findsOneWidget);
      await tester.tap(sword);
      await tester.pumpAndSettle();
      if (size.width == 844) await captureReview(tester, 'expansions-preview');
      await tester.tap(find.byKey(const ValueKey('expansionSave')));
      await tester.pumpAndSettle();
      expect(chosen?.excalibur, isTrue);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'Lancelot characters are visible and locked only while expansion is enabled',
      (tester) async {
    tester.view.physicalSize = const Size(667, 320);
    tester.view.devicePixelRatio = 1;
    tester.view.padding =
        const FakeViewPadding(left: 59, right: 59, bottom: 21);
    addTearDown(tester.view.reset);
    await pumpReview(
        tester, MaterialApp(theme: reviewTheme, home: const LocalPlayScreen()));
    await tester.tap(find.byKey(const ValueKey('playerCount7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('role正義蘭斯洛特')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('expansions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expansionLancelot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('變體一・每輪翻牌').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expansionSave')));
    await tester.pumpAndSettle();
    for (final role in ['正義蘭斯洛特', '邪惡蘭斯洛特']) {
      final tile = find.byKey(ValueKey('role$role'));
      expect(tile, findsOneWidget);
      expect(tester.widget<InkWell>(tile).onTap, isNull);
    }
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
    await captureReview(tester, 'lancelot-setup-preview');
    await tester.tap(find.byKey(const ValueKey('expansions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expansionLancelot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不使用').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expansionSave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('role正義蘭斯洛特')), findsNothing);
    expect(find.byKey(const ValueKey('role邪惡蘭斯洛特')), findsNothing);
  });

  testWidgets('Lady and sword have a separate lane from every vote card',
      (tester) async {
    for (final right in [true, false]) {
      final voteKey = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: SeatPlate(
                      number: 1,
                      name: '玩家',
                      scale: 1,
                      tokensOnRight: right,
                      isLeader: true,
                      vote: SeatVote.approve,
                      voteKey: voteKey,
                      badges: const [
            LadyBadge(scale: 1),
            ExcaliburBadge(scale: 1)
          ])))));
      await tester.pump(const Duration(seconds: 2));
      final vote = tester.getRect(find.byKey(voteKey));
      expect(tester.getRect(find.byType(LadyBadge)).overlaps(vote), isFalse);
      expect(
          tester.getRect(find.byType(ExcaliburBadge)).overlaps(vote), isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'online role grid also shows and locks the two expansion characters',
      (tester) async {
    tester.view.physicalSize = const Size(667, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rooms = StreamController<Map<String, dynamic>?>.broadcast();
    final mine = StreamController<Map<String, dynamic>?>.broadcast();
    final session = OnlineGameSession(
        code: '123456',
        uid: 'u0',
        room: rooms.stream,
        mine: mine.stream,
        call: (_, data) async => {});
    final transport = FakeVoiceTransport();
    final voice = VoiceController(createTransport: () => transport);
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark,
        home: OnlineRoomScreen(
            code: '123456', uid: 'u0', session: session, voice: voice)));
    rooms.add({
      'code': '123456',
      'hostUid': 'u0',
      'status': 'lobby',
      'players': List.generate(7, (i) => {'uid': 'u$i', 'name': '玩家$i'}),
      'optionalRoles': ['percival', 'morgana'],
      'gen': 0,
      'game': null,
      'expansions': {'lady': false, 'excalibur': false, 'lancelot': 1}
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    for (final role in [Role.lancelotGood, Role.lancelotEvil]) {
      final tile = find.byKey(ValueKey('onlineRole${role.name}'));
      expect(tile, findsOneWidget);
      expect(tester.widget<InkWell>(tile).onTap, isNull);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    voice.dispose();
    await tester.pump();
    await rooms.close();
    await mine.close();
    await transport.events.close();
  });
}
