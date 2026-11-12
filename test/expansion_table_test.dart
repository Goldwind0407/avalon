import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/game_screen.dart';
import 'package:avalon_shadow_council/features/game/game_session.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';
import 'package:avalon_shadow_council/features/table/expansion_pieces.dart';

/// A pass & play session already dealt and past the identity step.
LocalGameSession session(ExpansionSettings e, {int count = 7}) {
  final room = Room(
      code: '',
      players: List.generate(
          count, (i) => Player(id: '$i', name: '騎士$i', isReady: true)))
    ..expansions = e;
  final s = LocalGameSession(room, random: Random(3));
  for (var i = 0; i < count; i++) {
    s.game.confirmIdentity();
  }
  return s;
}

/// Plays one quest straight through the rules (everyone succeeds).
void quest(LocalGameSession s) {
  final g = s.game;
  final team = List.generate(g.requiredTeam, (i) => i);
  g.proposeTeam(team,
      excalibur: g.expansions.excalibur
          ? team.firstWhere((i) => i != g.leader)
          : null);
  for (var i = 0; i < g.players.length; i++) {
    g.vote(true);
  }
  g.continueVote();
  while (g.phase == GamePhase.quest) {
    g.playQuest(!g.mustFail(g.questActor));
  }
  if (g.phase == GamePhase.excalibur) g.useExcalibur(null);
}

void main() {
  late WidgetTester t;
  Future<void> settle([int ms = 1500]) async {
    for (var e = 0; e < ms; e += 50) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> show(GameSession s, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark, home: GameScreen.online(session: s)));
    await settle(2500);
  }

  testWidgets('Lady of the Lake: the holder examines a loyalty in secret',
      (tester) async {
    t = tester;
    final s = session(const ExpansionSettings(lady: true));
    quest(s);
    s.game.continueQuest();
    quest(s);
    s.game.continueQuest();
    expect(s.phase, GamePhase.lady);
    final holder = s.ladyHolder!;
    await show(s, const Size(844, 390));
    expect(find.text('請將手機交給'), findsOneWidget);
    expect(find.byType(LadyBadge), findsOneWidget);
    await tester.tap(find.text('我是本人，開啟秘密畫面'));
    await settle();
    expect(find.text('${playerLabel(holder, '騎士$holder')}　使用湖中女神'),
        findsOneWidget);
    // a past holder (the holder themselves) cannot be picked
    expect(find.byKey(ValueKey('pick$holder')), findsNothing);
    final target = (holder + 1) % 7;
    await tester.tap(find.byKey(ValueKey('pick$target')));
    await settle(400);
    await tester.tap(find.text('查驗陣營'));
    await settle(2000);
    // shown straight away to the same player, no second hand-off
    expect(find.text('${playerLabel(target, '騎士$target')} 的陣營是'),
        findsOneWidget);
    expect(find.text(s.game.roles[target].isEvil ? '邪惡陣營' : '正義陣營'),
        findsOneWidget);
    await tester.tap(find.text('記住了，隱藏並繼續'));
    await settle(2500);
    expect(s.phase, GamePhase.team);
    expect(s.ladyHolder, target);
    expect(find.byType(LadyBadge), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Excalibur: handed out with the team, then flips one card',
      (tester) async {
    t = tester;
    final s = session(const ExpansionSettings(excalibur: true), count: 5);
    await show(s, const Size(844, 390));
    final team = [s.leader, (s.leader + 1) % 5];
    for (final i in team) {
      await tester.tap(find.byKey(ValueKey('seat$i')));
      await settle(500);
    }
    await tester.tap(find.textContaining('提案並開始投票'));
    await settle(600);
    expect(find.text('把王者之劍交給哪位隊員？'), findsOneWidget);
    // the leader cannot keep the sword
    expect(find.byKey(ValueKey('excaliburTo${s.leader}')), findsNothing);
    await tester.tap(find.byKey(ValueKey('excaliburTo${team[1]}')));
    await settle(600);
    expect(s.excaliburHolder, team[1]);
    for (var i = 0; i < 5; i++) {
      await s.vote(i, true);
    }
    await s.continueVote();
    for (final _ in team) {
      await s.playQuest(-1, true);
    }
    expect(s.phase, GamePhase.excalibur);
    await settle(2500);
    expect(find.byType(ExcaliburBadge), findsOneWidget);
    await tester.tap(find.text('我是本人，開啟秘密畫面'));
    await settle();
    expect(find.byKey(ValueKey('pick${team[1]}')), findsNothing);
    await tester.tap(find.byKey(ValueKey('pick${team[0]}')));
    await settle(400);
    await tester.tap(find.text('翻轉這張牌'));
    await settle(2000);
    expect(find.text('${playerLabel(team[0], '騎士${team[0]}')} 原本打出的是'),
        findsOneWidget);
    expect(find.text('「任務成功」'), findsOneWidget);
    await tester.tap(find.text('記住了，隱藏並繼續'));
    await settle(6000);
    expect(s.phase, GamePhase.questResult);
    expect(s.history.last.fails, 1);
    expect(find.textContaining('王者之劍：'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lancelot loyalty cards lie by the board on small phones',
      (tester) async {
    t = tester;
    for (final variant in [1, 2]) {
      final s = session(ExpansionSettings(lancelot: variant));
      await show(s, const Size(667, 320));
      expect(find.byKey(const ValueKey('loyaltyStrip')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
