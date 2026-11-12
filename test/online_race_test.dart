import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/game_screen.dart';
import 'package:avalon_shadow_council/features/table/card_reveal.dart';
import 'package:avalon_shadow_council/features/online/online_session.dart';
import 'package:avalon_shadow_council/features/online/online_room_screen.dart';
import 'package:avalon_shadow_council/features/online/voice/voice_controller.dart';
import 'online_table_test.dart' show FakeServer, advance;
import 'voice_controller_test.dart' show FakeVoiceTransport;

Map<String, dynamic> roomData(
        {String phase = 'identity',
        int generation = 1,
        int count = 5,
        bool playing = true}) =>
    {
      'code': '123456',
      'hostUid': 'u0',
      'status': playing ? 'playing' : 'lobby',
      'players': [
        for (var i = 0; i < count; i++)
          {'uid': FakeServer.uids[i], 'name': '玩家$i'}
      ],
      'optionalRoles': ['percival', 'morgana'],
      'gen': generation,
      'game': !playing
          ? null
          : {
              'phase': phase,
              'leader': 0,
              'history': [],
              'confirmed': [0, 2, 3, 4],
              'voted': [],
              'played': [],
              'team': [0, 1],
              'rejections': 0,
              'votes': null,
              'proposals': [],
              'speechVersion': 0
            },
    };
Map<String, dynamic> card([int generation = 1]) => {
      'gen': generation,
      'seat': 1,
      'role': 'merlin',
      'visible': [3, 4],
    };

void main() {
  late FakeServer server;
  late OnlineGameSession session;
  setUp(() {
    server = FakeServer();
    session = OnlineGameSession(
        code: '123456',
        uid: 'me',
        room: server.rooms.stream,
        mine: server.mine.stream,
        call: server.call);
  });
  tearDown(() async {
    session.dispose();
    await server.rooms.close();
    await server.mine.close();
  });
  Future<void> flush() async {
    await Future<void>.value();
    await Future<void>.value();
  }

  Future<void> feed({String phase = 'identity', int generation = 1}) async {
    server.rooms.add(roomData(phase: phase, generation: generation));
    server.mine.add(card(generation));
    await flush();
  }

  test('room snapshots cannot erase a private-stream authorization failure',
      () async {
    await feed();
    expect(session.tableAvailable, isTrue);
    server.mine.addError(StateError('permission-denied'));
    await flush();
    expect(session.tableAvailable, isFalse);
    expect(session.roleOf(1), isNull);
    server.rooms.add(roomData());
    await flush();
    expect(session.error, isNotNull);
    expect(session.tableAvailable, isFalse);
    server.mine.add(card());
    await flush();
    expect(session.error, isNull);
    expect(session.tableAvailable, isTrue);
  });

  test('every game move captures its originating deal', () async {
    await feed(phase: 'vote', generation: 7);
    await session.vote(1, true);
    expect(server.calls.last.$2['generation'], 7);
    expect(server.calls.last.$2['historyLength'], 0);
    expect(server.calls.last.$2['rejections'], 0);
  });

  testWidgets('a delayed secret ballot is cancelled when a new deal arrives',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await feed(phase: 'vote');
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark, home: GameScreen.online(session: session)));
    await advance(tester, 1500);
    await tester.tap(find.text('贊成'));
    await advance(tester, 300);
    await tester.tap(find.text('蓋牌投出'));
    await advance(tester, 100);
    server.rooms.add(roomData(phase: 'vote', generation: 2));
    server.mine.add(card(2));
    await advance(tester, 1600);
    expect(server.calls.where((c) => c.$2['move'] == 'vote'), isEmpty);
    expect(session.generation, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'lobby transition never paints an old card using the shortened seat list',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await feed();
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark, home: GameScreen.online(session: session)));
    await advance(tester, 1800);
    expect(find.byKey(const ValueKey('identitySeen4')), findsOneWidget);
    server.rooms.add(roomData(playing: false, count: 4));
    await advance(tester, 600);
    expect(find.byKey(const ValueKey('identityKnowledge')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('catching up during a deal does not leave private actions blocked',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await feed();
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark, home: GameScreen.online(session: session)));
    await advance(tester, 100);
    final data = roomData(generation: 2);
    (data['game'] as Map)['confirmed'] = [0];
    server.rooms.add(data);
    server.mine.add(card(2));
    await advance(tester, 900);
    expect(find.byKey(const ValueKey('identitySeen4')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'permission loss closes the table and cannot auto-reopen it on public updates',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final transport = FakeVoiceTransport();
    final voice = VoiceController(createTransport: () => transport);
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark,
        home: OnlineRoomScreen(
            code: '123456', uid: 'me', session: session, voice: voice)));
    server.rooms.add(roomData());
    server.mine.add(card());
    await advance(tester, 1500);
    expect(find.byType(GameScreen), findsOneWidget);
    server.mine.addError(StateError('permission-denied'));
    await advance(tester, 800);
    expect(find.byType(GameScreen), findsNothing);
    server.rooms.add(roomData());
    await advance(tester, 800);
    expect(find.byType(GameScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    voice.dispose();
    await transport.events.close();
  });

  testWidgets(
      'catching up to another quest result discards the previous reveal order',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final first = {
      'team': [0, 1],
      'fails': 0,
      'succeeded': true,
      'order': [true, true]
    };
    final second = {
      'team': [0, 1, 2],
      'fails': 1,
      'succeeded': false,
      'order': [true, false, true]
    };
    final data = roomData(phase: 'questResult');
    (data['game'] as Map)['history'] = [first];
    server.rooms.add(data);
    server.mine.add(card());
    await flush();
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark, home: GameScreen.online(session: session)));
    await tester.pump(const Duration(milliseconds: 500));
    final dynamic screen = tester.state(find.byType(GameScreen));
    expect(screen.questOrder, [true, true]);
    final caughtUp = roomData(phase: 'questResult');
    (caughtUp['game'] as Map)['history'] = [first, second];
    server.rooms.add(caughtUp);
    await tester.pump();
    expect(screen.questOrder, [true, false, true]);
    expect(tester.widget<CardReveal>(find.byType(CardReveal)).items.length, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
