import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/discussion_widgets.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/game_session.dart';
import 'package:avalon_shadow_council/features/game/game_screen.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';

Room room({int free = 0}) => Room(
    code: '',
    players:
        List.generate(5, (i) => Player(id: '$i', name: '玩家$i', isReady: true)))
  ..discussion = DiscussionSettings(enabled: true, freeSeconds: free);

AvalonGame game({int free = 0}) {
  final g = AvalonGame(room(free: free), random: Random(42));
  for (var i = 0; i < 5; i++) {
    g.confirmIdentity();
  }
  return g;
}

void main() {
  testWidgets('speech panel fits narrow phones, long names and enlarged text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final setup = Room(
        code: '',
        players: List.generate(10,
            (i) => Player(id: '$i', name: '甲乙丙丁戊己庚辛壬癸甲乙丙丁戊己', isReady: true)))
      ..discussion = const DiscussionSettings(enabled: true);
    final session = LocalGameSession(setup);
    for (var i = 0; i < 10; i++) {
      await session.confirmIdentity(i);
    }
    await session.proposeTeam([0, 1, 2]);
    for (final size in [const Size(667, 320), const Size(844, 390)]) {
      tester.view.physicalSize = size;
      tester.view.padding =
          const FakeViewPadding(left: 45, right: 45, bottom: 21);
      await tester.pumpWidget(MaterialApp(
          theme: AvalonTheme.dark,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!),
          home: GameScreen.online(session: session)));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  test('speech order wraps after leader; stale pass cannot skip a seat', () {
    final g = game()..proposeTeam([0, 1], now: 1000);
    expect(g.phase, GamePhase.discussion);
    final leader = g.leader;
    for (var i = 1; i <= 5; i++) {
      final version = g.speechVersion;
      expect(g.speaker, (leader + i) % 5);
      expect(() => g.vote(true), throwsStateError);
      expect(
          () => g.endSpeech(
              seat: (g.speaker! + 1) % 5, expectedVersion: version, now: 1001),
          throwsStateError);
      g.endSpeech(seat: g.speaker, expectedVersion: version, now: 1001);
      g.endSpeech(seat: leader, expectedVersion: version, now: 1001);
      expect(g.speechVersion, version + 1);
    }
    expect(g.phase, GamePhase.vote);
    expect(g.speechDeadline, isNull);
  });

  test('expiry advances and optional free discussion lasts full sixty seconds',
      () {
    final g = game(free: 60)..proposeTeam([0, 1], now: 1000);
    g.endSpeech(
        seat: (g.speaker! + 1) % 5,
        expectedVersion: g.speechVersion,
        now: 46000);
    while (g.phase == GamePhase.discussion) {
      g.endSpeech(
          seat: g.speaker, expectedVersion: g.speechVersion, now: 46000);
    }
    expect(g.phase, GamePhase.freeDiscussion);
    expect(g.speechDeadline, 106000);
    expect(() => g.endSpeech(expectedVersion: g.speechVersion, now: 105999),
        throwsStateError);
    g.endSpeech(expectedVersion: g.speechVersion, now: 106000);
    expect(g.phase, GamePhase.vote);
  });

  test('every proposal is a stable snapshot, published only after all ballots',
      () {
    final g = game();
    g.proposeTeam([0, 1]);
    while (g.phase == GamePhase.discussion) {
      g.endSpeech(expectedVersion: g.speechVersion);
    }
    for (var i = 0; i < 4; i++) {
      g.vote(false);
    }
    expect(g.proposals, isEmpty);
    g.vote(true);
    final rejected = g.proposals.single;
    expect(rejected.approved, isFalse);
    expect(rejected.attempt, 1);
    g.continueVote();
    g.proposeTeam([2, 3]);
    while (g.phase == GamePhase.discussion) {
      g.endSpeech(expectedVersion: g.speechVersion);
    }
    for (var i = 0; i < 5; i++) {
      g.vote(true);
    }
    expect(g.proposals.last.attempt, 2);
    expect(g.proposals.last.leader, g.leader);
    expect(rejected.team, [0, 1]);
    expect(rejected.votes, [false, false, false, false, true]);
    g.continueVote();
    while (g.phase == GamePhase.quest) {
      g.playQuest(true);
    }
    g.continueQuest();
    g.proposeTeam([0, 1, 2]);
    while (g.phase == GamePhase.discussion) {
      g.endSpeech(expectedVersion: g.speechVersion);
    }
    for (var i = 0; i < 5; i++) {
      g.vote(true);
    }
    expect(g.proposals.last.quest, 2);
    expect(g.proposals.last.attempt, 1);
  });

  testWidgets('local speech timer continues without notebook or voice',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = LocalGameSession(room(), random: Random(2));
    for (var i = 0; i < 5; i++) {
      await session.confirmIdentity(i);
    }
    await session.proposeTeam([0, 1]);
    final first = session.speaker;
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark, home: GameScreen.online(session: session)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(DiscussionPanel), findsOneWidget);
    expect(find.byTooltip('玩家筆記'), findsNothing);
    expect(find.byTooltip('加入語音'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('結束發言 / 下一位'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(session.speaker, (first! + 1) % 5);
    final version = session.speechVersion;
    await tester.pump(const Duration(seconds: 46));
    expect(session.speechVersion, version + 1);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
