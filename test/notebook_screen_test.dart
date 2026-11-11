import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/game_session.dart';
import 'package:avalon_shadow_council/features/game/game_screen.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';
import 'package:avalon_shadow_council/features/notebook/notebook_model.dart';
import 'package:avalon_shadow_council/features/notebook/notebook_screen.dart';
import 'notebook_model_test.dart' show MemoryNotebookStorage;
import 'voice_controller_test.dart' show FakeVoiceTransport;
import 'package:avalon_shadow_council/features/online/voice/voice_controller.dart';

ThemeData notebookTheme = AvalonTheme.dark;

class OnlineNotebookSession extends LocalGameSession {
  OnlineNotebookSession(super.room, this.notes);
  final GameNotebook notes;
  @override
  int? get mySeat => 0;
  @override
  GameNotebook get notebook => notes;
}

class PublicNotebookSession extends GameSession {
  PublicNotebookSession({this.count = 10, this.longNames = false});
  final int count;
  final bool longNames;
  @override
  List<String> get players => List.generate(
      count,
      (i) => longNames
          ? '玩家$i甲乙丙丁戊己庚辛壬癸甲乙丙'
          : ['亞瑟', '小明', '派派', '高文', '莉雅', '阿風', '小白', '小黑', '九日', '十里'][i]);
  @override
  List<String> get playerIds => List.generate(count, (i) => 'u$i');
  @override
  GamePhase phase = GamePhase.team;
  @override
  int leader = 2;
  @override
  int generation = 1;
  @override
  int rejections = 0;
  @override
  List<int> team = [0, 1, 2];
  @override
  List<bool> votes = [];
  @override
  List<QuestResult> history = [];
  @override
  int? get mySeat => 0;
  @override
  String get notebookScope => 'room/me/$generation';
  @override
  Role? roleOf(int seat) => throw StateError('notebook must never read roles');
  @override
  String knowledge(int seat) =>
      throw StateError('notebook must never read secret knowledge');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'opening information and rejected vote history are readable in notebook',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = PublicNotebookSession();
    final notes = GameNotebook(storage: MemoryNotebookStorage());
    await notes.synchronize(game.notebookScope,
        opening: '派西維爾\n候選人：1 號【亞瑟】、4 號【高文】',
        proposals: [
          ProposalRecord(quest: 1, attempt: 1, leader: 2, team: [
            0,
            3
          ], votes: [
            false,
            true,
            false,
            true,
            false,
            false,
            true,
            false,
            true,
            false
          ])
        ]);
    await tester.pumpWidget(MaterialApp(
        theme: notebookTheme,
        home: NotebookScreen(session: game, notebook: notes)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('開局情報'));
    await tester.pumpAndSettle();
    expect(find.textContaining('派西維爾\n候選人'), findsOneWidget);
    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('投票歷史'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 次提案・否決'), findsOneWidget);
    expect(find.text('隊長：3 號 【派派】'), findsOneWidget);
    expect(find.text('隊伍：1 號 【亞瑟】、4 號 【高文】'), findsOneWidget);
    expect(find.text('1 號 【亞瑟】：反對'), findsOneWidget);
    expect(find.text('2 號 【小明】：贊成'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    game.dispose();
    notes.dispose();
  });
  setUpAll(() async {
    if (Platform.environment['NOTEBOOK_CAPTURE'] == '1' && Platform.isWindows) {
      final font = FontLoader('NotebookPreview')
        ..addFont(File('C:/Windows/Fonts/msjh.ttc')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)));
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await Future.wait([font.load(), icons.load()]);
      notebookTheme = AvalonTheme.dark.copyWith(
          textTheme:
              AvalonTheme.dark.textTheme.apply(fontFamily: 'NotebookPreview'));
    }
  });

  testWidgets(
      'table opens the book and preserves notes on return without changing the game',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final notes = GameNotebook(storage: MemoryNotebookStorage());
    final room = Room(
        code: 'local',
        players: List.generate(
            5, (i) => Player(id: 'u$i', name: '玩家$i', isReady: true)));
    final session = OnlineNotebookSession(room, notes);
    while (session.phase == GamePhase.identity) {
      await session.confirmIdentity(0);
    }
    addTearDown(session.dispose);
    addTearDown(notes.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: notebookTheme, home: GameScreen.online(session: session)));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('玩家筆記'));
    await tester.pumpAndSettle();
    expect(find.byType(NotebookScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('markevil0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回遊戲'));
    await tester.pumpAndSettle();
    expect(session.phase, GamePhase.team);
    expect(session.team, isEmpty);
    await tester.tap(find.byTooltip('玩家筆記'));
    await tester.pumpAndSettle();
    expect(notes.player('seat0').side, SuspectedSide.evil);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      '10-player book paginates, edits with keyboard, marks and keeps local notes',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = PublicNotebookSession();
    final notes = GameNotebook(storage: MemoryNotebookStorage());
    final audio = FakeVoiceTransport();
    final voice = VoiceController(createTransport: () => audio);
    await voice.join();
    addTearDown(() async {
      voice.dispose();
      await audio.events.close();
    });
    addTearDown(game.dispose);
    addTearDown(notes.dispose);
    final capture = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        theme: notebookTheme,
        home: RepaintBoundary(
            key: capture,
            child:
                NotebookScreen(session: game, notebook: notes, voice: voice))));
    await tester.pumpAndSettle();
    expect(find.text('玩家筆記'), findsOneWidget);
    await tester.tap(find.byTooltip('開啟麥克風'));
    await tester.pumpAndSettle();
    expect(voice.microphone, isTrue);
    expect(audio.connections, 1);
    expect(find.byKey(const ValueKey('playerNote2')), findsOneWidget);
    expect(find.byKey(const ValueKey('playerNote3')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('markgood1')));
    await tester.pumpAndSettle();
    expect(notes.player('u1').side, SuspectedSide.good);
    await tester.tap(find.byKey(const ValueKey('playerNote1')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 230);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('notebookEditor')), '第一輪發言積極，先觀察');
    await tester.ensureVisible(find.byKey(const ValueKey('saveNotebookNote')));
    await tester.tap(find.byKey(const ValueKey('saveNotebookNote')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(find.text('第一輪發言積極，先觀察'), findsOneWidget);
    expect(notes.player('u1').side, SuspectedSide.good);
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('下一頁玩家'));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('playerNote9')), findsOneWidget);
    expect(find.text('4 / 4 頁'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notebookQuest4')));
    await tester.pumpAndSettle();
    expect(find.text('第 5 次遠征'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('questNote')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('notebookEditor')), '第五輪需要重新討論隊伍');
    await tester.tap(find.byKey(const ValueKey('saveNotebookNote')));
    await tester.pumpAndSettle();
    expect(notes.quest(4), '第五輪需要重新討論隊伍');
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('上一頁玩家'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('notebookQuest0')));
    await tester.pumpAndSettle();
    await notes.setQuestText(0, '2、4 號的說法有出入，下一輪再確認');
    await tester.pumpAndSettle();
    if (Platform.environment['NOTEBOOK_CAPTURE'] == '1') {
      await tester.runAsync(() async {
        final boundary = capture.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build').create(recursive: true);
        await File('build/notebook-preview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.byTooltip('清空本局筆記'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(notes.player('u1').text, isNotEmpty);
    await tester.tap(find.byTooltip('清空本局筆記'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(notes.player('u1').text, isEmpty);
    expect(notes.player('u1').side, isNull);
    expect(notes.quest(4), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(voice.connected, isTrue);
    expect(audio.closes, 0);
  });

  testWidgets(
      'book fits small landscape phones, uses only public results, resets new deal',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = PublicNotebookSession(longNames: true);
    final notes = GameNotebook(storage: MemoryNotebookStorage());
    addTearDown(game.dispose);
    addTearDown(notes.dispose);
    for (final size in [
      const Size(667, 320),
      const Size(844, 390),
      const Size(932, 430)
    ]) {
      tester.view.physicalSize = size;
      tester.view.padding =
          const FakeViewPadding(left: 45, right: 45, bottom: 21);
      await tester.pumpWidget(MaterialApp(
          theme: notebookTheme,
          home: NotebookScreen(session: game, notebook: notes)));
      await tester.pumpAndSettle();
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.takeException(), isNull);
    }
    game.history = [
      QuestResult([0, 2], 1, false)
    ];
    game.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.textContaining('任務失敗\n成功 1 張・失敗 1 張'), findsOneWidget);
    await notes.setPlayerText('u0', '上一局筆記');
    await tester.pumpAndSettle();
    game.generation++;
    game.history = [];
    game.notifyListeners();
    await tester.pumpAndSettle();
    expect(notes.player('u0').text, isEmpty);
    expect(find.textContaining('尚未公布遠征結果'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
