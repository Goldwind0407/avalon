import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/game_screen.dart';
import 'package:avalon_shadow_council/features/online/online_session.dart';

/// One phone at an online table, fed by a fake server.
class FakeServer {
  final rooms = StreamController<Map<String, dynamic>?>.broadcast();
  final mine = StreamController<Map<String, dynamic>?>.broadcast();
  final calls = <(String, Map<String, Object?>)>[];

  Future<Map<String, dynamic>> call(
      String name, Map<String, Object?> data) async {
    calls.add((name, data));
    return {'ok': true};
  }

  static const uids = ['u0', 'me', 'u2', 'u3', 'u4'];

  void room(Map<String, dynamic> game) => rooms.add({
        'code': '123456',
        'hostUid': 'u0',
        'status': 'playing',
        'players': [
          for (final (i, uid) in uids.indexed) {'uid': uid, 'name': '騎士$i'}
        ],
        'playerUids': uids,
        'optionalRoles': <String>['percival', 'morgana'],
        'gen': 1,
        'step': 1,
        'game': {
          'phase': 'identity',
          'leader': 0,
          'rejections': 0,
          'team': <int>[],
          'confirmed': <int>[],
          'voted': <int>[],
          'votes': null,
          'played': <int>[],
          'history': <Object>[],
          'winner': null,
          'result': '',
          'assassinTarget': null,
          'revealedRoles': null,
          ...game,
        },
      });
}

Future<void> advance(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('online seat: own card, waiting, voting and the result',
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
    // the table only opens once the room is known
    server.room({});
    server.mine.add({
      'gen': 1,
      'seat': 1,
      'role': 'percival',
      'visible': [0, 3],
    });
    await tester.pump();
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark, home: GameScreen.online(session: session)));
    await advance(tester, 3500);

    // ── identity: straight to my own card, no hand-off ──
    // (the card turns over once the deal is done; let the text settle)
    await advance(tester, 1500);
    expect(find.text('請將手機交給'), findsNothing);
    expect(find.text('派西維爾'), findsOneWidget);
    final knowledge = find.byKey(const ValueKey('identityKnowledge'));
    expect(find.descendant(of: knowledge, matching: find.text('梅林候選人：')),
        findsOneWidget);
    expect(find.descendant(of: knowledge, matching: find.text('1 號 【騎士0】')),
        findsOneWidget);
    expect(find.descendant(of: knowledge, matching: find.text('4 號 【騎士3】')),
        findsOneWidget);
    expect(find.descendant(of: knowledge, matching: find.text('你無法分辨梅林與莫甘娜。')),
        findsOneWidget);
    await tester.tap(find.text('記住了'));
    await advance(tester, 600);
    expect(server.calls.last.$2['move'], 'confirmIdentity');
    // waiting for the others; my card is hidden again
    server.room({
      'confirmed': [1]
    });
    await advance(tester, 1200);
    expect(find.text('派西維爾'), findsNothing);
    expect(find.text('等待所有人確認身分（1/5）'), findsOneWidget);

    // ── team: someone else leads, so this phone only watches ──
    server.room({
      'phase': 'team',
      'confirmed': [0, 1, 2, 3, 4]
    });
    await advance(tester, 3500);
    expect(find.text('等待隊長 1 號 【騎士0】 挑選 2 名隊員'), findsOneWidget);
    expect(find.textContaining('提案並開始投票'), findsNothing);

    // ── vote: my cards come up on my own phone ──
    server.room({
      'phase': 'vote',
      'team': [0, 1],
      'voted': [0, 3]
    });
    await advance(tester, 1500);
    await tester.tap(find.text('反對'));
    await advance(tester, 300);
    await tester.tap(find.text('蓋牌投出'));
    await advance(tester, 600);
    expect(server.calls.last.$2, {
      'code': '123456',
      'move': 'vote',
      'generation': 1,
      'historyLength': 0,
      'rejections': 0,
      'approve': false
    });
    server.room({
      'phase': 'vote',
      'team': [0, 1],
      'voted': [0, 1, 3]
    });
    await advance(tester, 1500);
    expect(find.text('等待投票（3/5）'), findsOneWidget);

    // ── result: only the leader moves the game on ──
    server.room({
      'phase': 'voteResult',
      'team': [0, 1],
      'votes': [true, false, true, true, true],
    });
    await advance(tester, 6000);
    expect(find.text('等待隊長繼續'), findsOneWidget);
    await tester.tap(find.text('等待隊長繼續'));
    await advance(tester, 300);
    expect(server.calls.where((c) => c.$2['move'] == 'continueVote'), isEmpty);

    // ── the end: every role is revealed ──
    server.room({
      'phase': 'finished',
      'winner': '正義',
      'result': '刺客選擇 3 號 騎士2，未能找到梅林，正義陣營獲勝！',
      'assassinTarget': 2,
      'revealedRoles': ['merlin', 'percival', 'loyal', 'assassin', 'minion'],
    });
    await advance(tester, 6000);
    expect(find.text('刺殺失敗'), findsOneWidget);
    await tester.tap(find.text('揭曉全員身分'));
    await advance(tester, 5000);
    expect(find.text('正義陣營獲勝'), findsOneWidget);
    // only the host can deal again
    expect(find.text('相同配置，再玩一局'), findsNothing);
    expect(find.text('回到房間'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('online leader picks the team on their own phone',
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
    server.room({
      'phase': 'team',
      'leader': 1,
      'confirmed': [0, 1, 2, 3, 4]
    });
    server.mine.add({'gen': 1, 'seat': 1, 'role': 'loyal', 'visible': []});
    await tester.pump();
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark, home: GameScreen.online(session: session)));
    await advance(tester, 1500);
    await tester.tap(find.text('騎士1'));
    await tester.tap(find.text('騎士3'));
    await advance(tester, 800);
    await tester.tap(find.text('提案並開始投票（2/2）'));
    await advance(tester, 300);
    expect(server.calls.last.$2, {
      'code': '123456',
      'move': 'proposeTeam',
      'generation': 1,
      'historyLength': 0,
      'rejections': 0,
      'team': [1, 3]
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
