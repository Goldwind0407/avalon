import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/game_screen.dart';
import 'package:avalon_shadow_council/features/online/online_room_screen.dart';
import 'package:avalon_shadow_council/features/online/online_session.dart';
import 'package:avalon_shadow_council/features/online/voice/voice_controller.dart';

class SilentAudio implements VoiceTransport {
  @override
  Stream<VoiceUpdate> get updates => const Stream.empty();
  @override
  Future<void> connect() async {}
  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}
  @override
  Future<void> close() async {}
}

Future<void> advance(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A room document as the server writes it.
Map<String, dynamic> roomDoc(
        {required bool playing,
        int players = 5,
        int step = 1,
        String? notice,
        int? noticeStep}) =>
    {
      'code': '123456',
      'hostUid': 'u0',
      'status': playing ? 'playing' : 'lobby',
      'players': [
        for (var i = 0; i < players; i++) {'uid': 'u$i', 'name': '玩家$i'}
      ],
      'optionalRoles': <String>[],
      'gen': 1,
      'step': step,
      'notice': notice,
      'noticeStep': noticeStep,
      'game': playing
          ? {
              'phase': 'team',
              'leader': 0,
              'history': [],
              'confirmed': [0, 1, 2, 3, 4],
              'voted': [],
              'played': [],
              'team': [],
              'rejections': 0,
            }
          : null,
    };

void main() {
  late StreamController<Map<String, dynamic>?> rooms, mine;
  late List<(String, Map<String, Object?>)> calls;
  late OnlineGameSession session;

  setUp(() {
    rooms = StreamController.broadcast();
    mine = StreamController.broadcast();
    calls = [];
    session = OnlineGameSession(
        code: '123456',
        uid: 'u1',
        room: rooms.stream,
        mine: mine.stream,
        call: (name, data) async {
          calls.add((name, data));
          return {'left': true, 'ended': true};
        });
  });
  tearDown(() => session.dispose());

  Future<void> openRoom(WidgetTester tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final voice = VoiceController(createTransport: SilentAudio.new);
    addTearDown(voice.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark,
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => OnlineRoomScreen(
                                code: '123456',
                                uid: 'u1',
                                session: session,
                                voice: voice))),
                    child: const Text('首頁'))))));
    await tester.tap(find.text('首頁'));
    await advance(tester, 500);
  }

  testWidgets('leaving mid-game from the table gives up the seat',
      (tester) async {
    await openRoom(tester);
    rooms.add(roomDoc(playing: true));
    mine.add({'gen': 1, 'seat': 1, 'role': 'loyal', 'visible': []});
    await advance(tester, 1500);
    expect(find.byType(GameScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await advance(tester, 500);
    expect(find.text('暫時離開'), findsOneWidget);
    await tester.tap(find.text('離開房間'));
    await advance(tester, 800);
    expect(calls.last.$1, 'leaveRoom');
    expect(calls.last.$2, {'code': '123456'});
    // back on the home screen; updates for the old seat are ignored
    expect(find.text('首頁'), findsOneWidget);
    rooms.add(roomDoc(playing: false, players: 4));
    await advance(tester, 300);
    expect(find.text('首頁'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('when someone else leaves, the table closes for everyone',
      (tester) async {
    await openRoom(tester);
    rooms.add(roomDoc(playing: true, step: 3));
    mine.add({'gen': 1, 'seat': 1, 'role': 'loyal', 'visible': []});
    await advance(tester, 1500);
    expect(find.byType(GameScreen), findsOneWidget);
    // 玩家4 leaves: the server ends the game and writes a notice
    rooms.add(roomDoc(
        playing: false,
        players: 4,
        step: 4,
        notice: '玩家4 離開了房間，對局已中止',
        noticeStep: 4));
    await advance(tester, 1200);
    expect(find.byType(GameScreen), findsNothing);
    expect(find.byType(OnlineRoomScreen), findsOneWidget);
    expect(find.text('玩家4 離開了房間，對局已中止'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the leave button in the lobby gives up the seat',
      (tester) async {
    await openRoom(tester);
    rooms.add(roomDoc(playing: false, notice: '舊通知', noticeStep: 1));
    await advance(tester, 500);
    // a notice from before this phone came in is not shown again
    expect(find.text('舊通知'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('leaveRoom')));
    await advance(tester, 800);
    expect(calls.last.$1, 'leaveRoom');
    expect(calls.last.$2, {'code': '123456'});
    expect(find.text('首頁'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
