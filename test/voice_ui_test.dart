import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/game_screen.dart';
import 'package:avalon_shadow_council/features/home/local_play_screen.dart';
import 'package:avalon_shadow_council/features/online/online_room_screen.dart';
import 'package:avalon_shadow_council/features/online/online_session.dart';
import 'package:avalon_shadow_council/features/online/voice/voice_controller.dart';
import 'package:avalon_shadow_council/features/online/voice/voice_controls.dart';

class TestAudio implements VoiceTransport {
  final events = StreamController<VoiceUpdate>.broadcast();
  int connections = 0;
  int closes = 0;
  @override
  Stream<VoiceUpdate> get updates => events.stream;
  @override
  Future<void> connect() async {
    connections++;
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}
  @override
  Future<void> close() async {
    closes++;
  }
}

Future<void> advance(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
      'voice stays connected from lobby to table and closes when leaving the room',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final audio = TestAudio();
    final voice = VoiceController(createTransport: () => audio);
    final rooms = StreamController<Map<String, dynamic>?>.broadcast();
    final mine = StreamController<Map<String, dynamic>?>.broadcast();
    final session = OnlineGameSession(
        code: '123456',
        uid: 'u0',
        room: rooms.stream,
        mine: mine.stream,
        call: (_, data) async => {'ok': true});
    Map<String, dynamic> room(bool playing) => {
          'code': '123456',
          'hostUid': 'u0',
          'status': playing ? 'playing' : 'lobby',
          'players': [
            for (var i = 0; i < 5; i++) {'uid': 'u$i', 'name': '玩家$i'}
          ],
          'optionalRoles': <String>[],
          'gen': playing ? 1 : 0,
          'game': playing
              ? {
                  'phase': 'identity',
                  'leader': 0,
                  'history': [],
                  'confirmed': [],
                  'voted': [],
                  'played': [],
                  'team': [],
                  'rejections': 0
                }
              : null,
        };
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
                                uid: 'u0',
                                session: session,
                                voice: voice))),
                    child: const Text('進入房間'))))));
    await tester.tap(find.text('進入房間'));
    await advance(tester, 500);
    rooms.add(room(false));
    await tester.pumpAndSettle();
    expect(audio.connections, 0);
    await tester.tap(find.text('加入語音'));
    await tester.pumpAndSettle();
    expect(voice.connected, isTrue);
    expect(voice.microphone, isFalse);
    await tester.tap(find.byTooltip('開啟麥克風'));
    await tester.pumpAndSettle();
    expect(voice.microphone, isTrue);
    mine.add({'gen': 1, 'seat': 0, 'role': 'loyal', 'visible': []});
    rooms.add(room(true));
    await advance(tester, 5500);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(
        tester.widget<GameScreen>(find.byType(GameScreen)).voice, same(voice));
    expect(audio.connections, 1);
    expect(audio.closes, 0);
    // Voice controls must remain reachable above the secret-card overlay.
    await tester.tap(find.byTooltip('關閉麥克風').hitTestable());
    await advance(tester, 100);
    expect(voice.microphone, isFalse);
    await tester.tap(find.byTooltip('開啟麥克風').hitTestable());
    await advance(tester, 100);
    expect(voice.microphone, isTrue);
    audio.events.add(const VoiceUpdate(VoiceStatus.connected,
        microphone: true, speakers: {'u1'}));
    await advance(tester, 100);
    expect(find.byTooltip('說話中'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await advance(tester, 500);
    await tester.tap(find.text('暫時離開'));
    await advance(tester, 600);
    expect(find.byType(GameScreen), findsNothing);
    expect(voice.connected, isTrue);
    await tester.tap(find.byTooltip('離開房間'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await advance(tester, 800);
    expect(audio.closes, 1);
    expect(find.text('進入房間'), findsOneWidget);
    expect(voice.status, VoiceStatus.offline);
    expect(audio.closes, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    voice.dispose();
    session.dispose();
    await rooms.close();
    await mine.close();
    await audio.events.close();
  });

  testWidgets('local play never shows voice controls', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(theme: AvalonTheme.dark, home: const LocalPlayScreen()));
    expect(find.byType(VoiceControls), findsNothing);
    await tester.tap(find.text('開始遊戲'));
    await advance(tester, 3500);
    expect(find.byType(VoiceControls), findsNothing);
    expect(tester.widget<GameScreen>(find.byType(GameScreen)).voice, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
