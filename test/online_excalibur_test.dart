import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/game_screen.dart';
import 'package:avalon_shadow_council/features/online/online_session.dart';
import 'online_table_test.dart' show FakeServer, advance;

void main() {
  testWidgets('online: the sword holder sees the card they flipped',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = FakeServer();
    final session = OnlineGameSession(
        code: '123456',
        uid: 'me',
        room: server.rooms.stream,
        mine: server.mine.stream,
        call: server.call);
    addTearDown(session.dispose);
    const sword = {'lady': false, 'lancelot': 0, 'excalibur': true};
    // seat 1 (me) holds the sword on a team of 0 and 1; both cards are in
    server.room({
      'phase': 'excalibur',
      'leader': 0,
      'team': [0, 1],
      'played': [0, 1],
      'confirmed': [0, 1, 2, 3, 4],
      'expansions': sword,
      'excaliburHolder': 1,
    });
    final card = {
      'gen': 1,
      'seat': 1,
      'role': 'loyal',
      'visible': <int>[],
      'reveals': <Object>[],
    };
    server.mine.add(card);
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark, home: GameScreen.online(session: session)));
    await advance(tester, 2500);
    expect(find.text('翻轉這張牌'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pick0')));
    await advance(tester, 400);
    await tester.tap(find.text('翻轉這張牌'));
    await advance(tester, 300);
    expect(server.calls.last.$2['move'], 'useExcalibur');
    expect(server.calls.last.$2['target'], 0);
    // the server moves on, then the holder's private document arrives,
    // in either order
    server.room({
      'phase': 'excaliburResult',
      'leader': 0,
      'team': [0, 1],
      'played': [0, 1],
      'confirmed': [0, 1, 2, 3, 4],
      'expansions': sword,
      'excaliburHolder': 1,
    });
    await advance(tester, 300);
    server.mine.add({
      ...card,
      'reveals': [
        {'seat': 1, 'kind': 'excalibur', 'quest': 1, 'target': 0, 'card': false}
      ],
    });
    await advance(tester, 2500);
    expect(find.textContaining('原本打出的是'), findsOneWidget);
    expect(find.text('「任務失敗」'), findsOneWidget);
    expect(find.text('記住了，繼續'), findsOneWidget);
  });
}
