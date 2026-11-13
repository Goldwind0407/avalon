import 'dart:convert';
import 'dart:math';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:avalon_shadow_council/core/theme.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/home/local_play_screen.dart';
import 'package:avalon_shadow_council/features/solo/bot_difficulty.dart';
import 'package:avalon_shadow_council/features/solo/bot_style.dart';
import 'package:avalon_shadow_council/features/solo/bot_voice.dart';
import 'package:avalon_shadow_council/features/solo/game_review.dart';
import 'package:avalon_shadow_council/features/solo/memory/match_archive.dart';
import 'package:avalon_shadow_council/features/solo/memory/match_history_screen.dart';
import 'package:avalon_shadow_council/features/solo/memory/match_repository.dart';
import 'package:avalon_shadow_council/features/solo/memory/social_memory.dart';
import 'package:avalon_shadow_council/features/solo/persona/bot_persona.dart';
import 'package:avalon_shadow_council/features/solo/solo_session.dart';
import 'solo_session_test.dart' show soloRoom;
import 'support/bot_dialogue_fixtures.dart';

/// Plays [games] solo games in a row at one table and returns every line
/// said, game by game.
/// The repository is created inside the fake clock; read the results through
/// a fresh one over the same [storage].
List<List<DiscussionStatement>> playTable(int seed, MatchStorage storage,
    {int games = 1, int count = 6, int limit = 40}) {
  final lines = <List<DiscussionStatement>>[];
  fakeAsync((time) {
    var clock = DateTime(2026, 11, 13, 20);
    final repository = MatchRepository(storage: storage, limit: limit);
    final s = SoloGameSession(soloRoom(count, const ExpansionSettings()),
        random: Random(seed),
        personas: BotPersona.deal(count - 1, Random(seed)),
        archive: repository,
        now: () => clock = clock.add(const Duration(minutes: 30)),
        botDelay: const Duration(milliseconds: 1),
        speechDuration: const Duration(milliseconds: 1));
    for (var g = 0; g < games; g++) {
      time.flushMicrotasks();
      var steps = 0;
      while (s.phase != GamePhase.finished && steps++ < 4000) {
        if (s.hasPrivateInput ||
            [GamePhase.voteResult, GamePhase.questResult].contains(s.phase)) {
          switch (s.phase) {
            case GamePhase.identity:
              s.confirmIdentity(0);
            case GamePhase.team:
              s.proposeTeam(List.generate(s.requiredTeam, (i) => i));
            case GamePhase.discussion:
              s.expressOpinion(true);
            case GamePhase.vote:
              s.vote(0, true);
            case GamePhase.voteResult:
              s.continueVote();
            case GamePhase.quest:
              s.playQuest(0, !s.evilNow(0)!);
            case GamePhase.questResult:
              s.continueQuest();
            case GamePhase.assassination:
              s.assassinate(1);
            default:
              break;
          }
        } else {
          time.elapse(const Duration(milliseconds: 1));
        }
        time.flushMicrotasks();
      }
      expect(s.phase, GamePhase.finished);
      lines.add([...s.statements]);
      if (g + 1 < games) s.restart();
      time.flushMicrotasks();
    }
    s.dispose();
    time.flushMicrotasks();
  });
  return lines;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a table is dealt different regulars with varied styles', () {
    for (var seed = 0; seed < 30; seed++) {
      for (var count = 4; count <= 9; count++) {
        final table = BotPersona.deal(count, Random(seed));
        expect(table.length, count);
        expect(table.map((p) => p.id).toSet().length, count);
        expect(table.map((p) => p.style).toSet().length, min(count, 6));
        expect(table.every((p) => p.style != BotStyle.balanced), isTrue);
      }
    }
    expect(BotPersona.cast.map((p) => p.name).toSet().length, 9);
    expect(BotPersona.byId('zhe')!.name, '阿哲');
    expect(BotPersona.byId('nobody'), isNull);
  });

  test('a finished game is kept once and reads back as the same review',
      () async {
    final storage = MemoryMatchStorage();
    playTable(4, storage);
    final repository = MatchRepository(storage: storage);
    final list = await repository.summaries();
    expect(list.length, 1);
    final match = (await repository.load(list.single.id))!;
    expect(match.review.quests, isNotEmpty);
    expect(match.personas.first, isNull);
    expect(match.personas.skip(1).every((p) => BotPersona.byId(p) != null),
        isTrue);
    // writing it out again gives the same data: nothing was lost on the way
    final again = MatchArchive.fromMap(
        jsonDecode(jsonEncode(match.toMap())) as Map<String, dynamic>)!;
    expect(jsonEncode(again.toMap()), jsonEncode(match.toMap()));
    expect(list.single.won, match.review.iWon);
    expect(list.single.myRole, match.review.roles[0]);
    // every regular at the table has something to remember
    expect(list.single.episodes.keys.toSet(),
        match.personas.whereType<String>().toSet());
    await repository.save(match);
    expect((await repository.summaries()).length, 1);
  });

  test('old games are forgotten beyond the limit, bodies included', () async {
    final storage = MemoryMatchStorage();
    playTable(2, storage, games: 3, limit: 2);
    final repository = MatchRepository(storage: storage, limit: 2);
    final list = await repository.summaries();
    expect(list.length, 2);
    expect(list.first.endedAt.isAfter(list.last.endedAt), isTrue);
    // index + two bodies
    expect(storage.values.length, 3);
    await repository.delete(list.first.id);
    expect((await repository.summaries()).single.id, list.last.id);
    await repository.clear();
    expect(storage.values, isEmpty);
  });

  test('unreadable storage is an empty history, not a crash', () async {
    final storage = MemoryMatchStorage()
      ..values['avalon.solo.matches.v1'] = '{not json';
    final repository = MatchRepository(storage: storage);
    expect(await repository.summaries(), isEmpty);
    expect(await repository.load('missing'), isNull);
    storage.values['avalon.solo.match.v1/x'] = jsonEncode({'v': 99});
    expect(await repository.load('x'), isNull);
  });

  test('episodes are read off the finished game, from each bot\'s side', () {
    DiscussionStatement said(int by, int to, DiscussionPosition position) =>
        DiscussionStatement(
            speaker: by,
            quest: 1,
            attempt: 1,
            text: '…',
            target: to,
            position: position);
    // the player (seat 0) is the Assassin; 4 is the other evil player
    final review = GameReview.build(
        players: ['你', '甲', '乙', '丙', '丁'],
        roles: [
          Role.assassin,
          Role.loyal,
          Role.percival,
          Role.merlin,
          Role.morgana
        ],
        styles: List.filled(5, null),
        mySeat: 0,
        winner: '邪惡',
        result: '刺客刺中梅林',
        proposals: [
          ProposalRecord(
              quest: 1,
              attempt: 1,
              leader: 1,
              team: [0, 1],
              votes: [true, true, false, false, true])
        ],
        history: [
          QuestResult([0, 1], 1, false)
        ],
        statements: [
          said(2, 0, DiscussionPosition.suspect),
          said(0, 3, DiscussionPosition.suspect),
          said(0, 4, DiscussionPosition.suspect),
        ],
        sources: const {},
        decisions: const {},
        cardsBySeat: const {},
        ladyChecks: const [],
        assassinTarget: 3,
        expansions: const ExpansionSettings());
    expect(
        episodesWith(review, 1), [EpisodeKind.fooled, EpisodeKind.lostToYou]);
    expect(episodesWith(review, 2),
        [EpisodeKind.sawThrough, EpisodeKind.lostToYou]);
    expect(episodesWith(review, 3), [
      EpisodeKind.accusedByYou,
      EpisodeKind.stabbedByYou,
      EpisodeKind.lostToYou
    ]);
    expect(episodesWith(review, 4),
        [EpisodeKind.caughtByYou, EpisodeKind.wonTogether]);
  });

  test('the next game at the same table brings the last one up', () async {
    var recalled = 0;
    for (var seed = 0; seed < 6; seed++) {
      final storage = MemoryMatchStorage();
      final games = playTable(seed, storage, games: 2);
      final repository = MatchRepository(storage: storage);
      // nothing to remember in the first game
      expect(games[0].where((s) => s.intent == 'recall'), isEmpty);
      final memories = games[1].where((s) => s.intent == 'recall').toList();
      recalled += memories.length;
      // not the whole table at once
      expect(memories.length, lessThanOrEqualTo(2));
      for (final s in memories) {
        expect(s.quest, 1);
        expect(s.text, contains('上一局'));
        expect(s.text, contains('1號'));
        expect(s.target, 0);
        // words only: nothing the other bots weigh as an accusation or claim
        expect(s.position, isNull);
        expect(s.claimedEvil, isNull);
        expect(s.speaker, isNot(0));
      }
      expect((await repository.summaries()).length, 2);
    }
    expect(recalled, greaterThan(3));
  });

  test('an accusation from the player is answered with last time', () {
    final memory = BotMemory(4, const [
      MemoryEntry(0, [EpisodeKind.accusedByYou, EpisodeKind.wonTogether])
    ]);
    final accusation = DiscussionStatement(
        speaker: 4,
        quest: 2,
        generation: 4,
        attempt: 1,
        text: '我懷疑1號。',
        target: 0,
        position: DiscussionPosition.suspect);
    final o = observe(seat: 0, history: [
      QuestResult([0, 2, 3], 1, false)
    ], team: [
      1,
      4,
      5
    ], statements: [
      accusation
    ]);
    final neutral = List.filled(7, .3);
    final voice = BotVoice(Random(1), BotStyle.balanced, BotDifficulty.normal)
      ..memory = memory;
    final first = voice.speak(o, false, neutral, neutral, const {})!;
    expect(first.text, startsWith('上一局你也'));
    expect(first.text, contains('3號、4號'));
    // said once; the next answer goes straight to the record
    final second = voice.speak(o, false, neutral, neutral, const {})!;
    expect(second.text, isNot(contains('上一局')));
    // the same accusation from another bot gets no such answer
    final other = BotVoice(Random(1), BotStyle.balanced, BotDifficulty.normal)
      ..memory = BotMemory(6, memory.entries);
    expect(other.speak(o, false, neutral, neutral, const {})!.text,
        isNot(contains('上一局')));
  });

  test('memory only covers games played with that regular', () {
    MatchSummary summary(String id, Map<String, List<EpisodeKind>> episodes) =>
        MatchSummary(
            id: id,
            endedAt: DateTime(2026),
            players: 5,
            myRole: Role.loyal,
            won: true,
            winner: '正義',
            difficulty: '普通',
            episodes: episodes);
    final past = [
      summary('c', {
        'zhe': [EpisodeKind.wonTogether]
      }),
      summary('b', {
        'kai': [EpisodeKind.fooled, EpisodeKind.lostToYou]
      }),
      summary('a', {
        'zhe': [EpisodeKind.wronged, EpisodeKind.wonTogether]
      }),
    ];
    expect(BotMemory.of('mia', past, 0), isNull);
    final zhe = BotMemory.of('zhe', past, 0)!;
    expect(zhe.gamesTogether, 2);
    expect(zhe.entries.map((e) => e.ago), [0, 2]);
    expect(zhe.latest(EpisodeKind.wronged)!.ago, 2);
    expect(zhe.latest(EpisodeKind.wronged, within: 2), isNull);
    expect(memorySummary(zhe), '一起玩過 2 局・同陣營 2 局・你贏 2 局');
    expect(memorySummary(null), '還沒跟你玩過');
    // a summary written by a newer version drops what this one cannot read
    final map = past[1].toMap();
    (map['episodes'] as Map)['kai'] = ['fooled', 'somethingNew'];
    expect(MatchSummary.fromMap(map).episodes['kai'], [EpisodeKind.fooled]);
    for (final kind in EpisodeKind.values) {
      for (final line in memoryLines(kind, '上一局', '1號')) {
        expect(line, contains('上一局'));
        expect(line, contains('1號'));
      }
    }
  });

  testWidgets('the history lists games, reopens a review and can be cleared',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = MemoryMatchStorage();
    playTable(4, storage, games: 2);
    final repository = MatchRepository(storage: storage);
    final list = (await tester.runAsync(repository.summaries))!;
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark,
        home: MatchHistoryScreen(repository: repository)));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 局・你贏'), findsOneWidget);
    expect(find.text('電腦玩家記得的事'), findsOneWidget);
    expect(find.textContaining('一起玩過 2 局'), findsWidgets);
    await tester.tap(find.byKey(ValueKey('match_${list.first.id}')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('你的表現'), findsWidgets);
    Navigator.of(tester.element(find.text('你的表現').first)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clearHistory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirmClearHistory')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.textContaining('還沒有紀錄'), findsOneWidget);
    expect(find.textContaining('還沒跟你玩過'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('solo setup seats the regulars and shows who they are',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = MatchRepository(storage: MemoryMatchStorage());
    await tester.pumpWidget(MaterialApp(
        theme: AvalonTheme.dark,
        home: LocalPlayScreen(
            solo: true, random: Random(1), archive: repository)));
    await tester.pumpAndSettle();
    final table = BotPersona.deal(9, Random(1));
    expect(find.text('你'), findsOneWidget);
    for (final p in table.take(4)) {
      expect(find.text(p.name), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('playerName1')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text(table.first.bio), findsOneWidget);
    expect(find.byKey(const ValueKey('personaRecord')), findsOneWidget);
    expect(find.text('還沒跟你玩過'), findsOneWidget);
    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('matchHistory')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('對局紀錄'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
