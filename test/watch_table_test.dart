import 'dart:io';
import 'dart:math';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/lobby/role_presets.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';
import 'package:avalon_shadow_council/features/solo/game_review.dart';
import 'package:avalon_shadow_council/features/solo/memory/match_repository.dart';
import 'package:avalon_shadow_council/features/solo/persona/bot_persona.dart';
import 'package:avalon_shadow_council/features/solo/solo_session.dart';

/// Watch whole games with nobody at the table (the player's seat is played
/// by a computer too) and write every line, vote and card out for review.
/// Runs only when asked for:
///   WATCH_OUT=watch.txt [WATCH_TABLES=10x3,8x3] [WATCH_EXP=lady+excalibur+lancelot1]
///   flutter test test/watch_table_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // WATCH_EXP: any of lady, excalibur, lancelot1, lancelot2 joined by '+'
  final exp = (Platform.environment['WATCH_EXP'] ?? '').split('+');
  final expansions = ExpansionSettings(
      lady: exp.contains('lady'),
      excalibur: exp.contains('excalibur'),
      lancelot: exp.contains('lancelot2')
          ? 2
          : exp.contains('lancelot1')
              ? 1
              : 0);

  void table(StringSink out, int seed, int count, int games) {
    final cast = BotPersona.deal(count - 1, Random(seed));
    final room = Room(code: '', players: [
      Player(id: '0', name: '玩家', isReady: true),
      for (final (i, p) in cast.indexed)
        Player(id: '${i + 1}', name: p.name, isReady: true)
    ])
      ..specialRoles.addAll([for (final r in rolePreset(count)!) r.label])
      ..discussion = DiscussionSettings.recommended
      ..expansions = expansions;
    fakeAsync((time) {
      var clock = DateTime(2026, 11, 13, 20);
      final s = SoloGameSession(room,
          random: Random(seed),
          personas: cast,
          archive: MatchRepository(storage: MemoryMatchStorage()),
          now: () => clock = clock.add(const Duration(minutes: 30)),
          botDelay: const Duration(milliseconds: 1),
          speechDuration: const Duration(milliseconds: 1),
          autopilot: true);
      for (var g = 0; g < games; g++) {
        time.flushMicrotasks();
        var steps = 0;
        while (s.phase != GamePhase.finished && steps++ < 20000) {
          if (s.phase == GamePhase.voteResult) s.continueVote();
          if (s.phase == GamePhase.questResult) s.continueQuest();
          time.elapse(const Duration(milliseconds: 1));
          time.flushMicrotasks();
        }
        expect(s.phase, GamePhase.finished,
            reason:
                '${s.phase} speaker=${s.speaker} leader=${s.leader} q=${s.questNumber}');
        time.elapse(const Duration(milliseconds: 50));
        time.flushMicrotasks();
        write(out, s.review!, '$count人桌 seed$seed 第${g + 1}局 ${exp.join('+')}',
            s.loyalty);
        if (g + 1 < games) s.restart();
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 5));
        time.flushMicrotasks();
      }
      s.dispose();
      time.flushMicrotasks();
    });
  }

  test('watch', () {
    final out = StringBuffer();
    // WATCH_TABLES=10x3,8x3 : players x games in a row, one table each
    final tables = Platform.environment['WATCH_TABLES'] ?? '7x5,6x3,9x2,5x3';
    for (final (i, t) in tables.split(',').indexed) {
      final [count, games] = t.split('x').map(int.parse).toList();
      final base = int.parse(Platform.environment['WATCH_SEED'] ?? '11');
      table(out, base + 13 * i, count, games);
    }
    File(Platform.environment['WATCH_OUT']!).writeAsStringSync('$out');
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: Platform.environment['WATCH_OUT'] == null
          ? 'set WATCH_OUT to a file path to watch games'
          : false);
}

void write(StringSink out, GameReview r, String title, List<bool?> loyalty) {
  String n(int s) => '${s + 1}號${r.players[s]}';
  out.writeln('\n########## $title');
  out.writeln([
    for (var s = 0; s < r.players.length; s++)
      '${n(s)}=${r.roles[s].label}${r.styles[s] == null ? '' : '(${r.styles[s]})'}'
  ].join('  '));
  for (final q in r.quests) {
    for (final p in q.proposals) {
      final rec = p.record;
      out.writeln(
          '\n-- 任務${q.number} 提案${rec.attempt}：${rec.leader + 1}號帶 ${rec.team.map((s) => s + 1).join('、')}');
      for (final l in p.lines) {
        final st = l.statement;
        out.writeln(
            '   ${st.speaker + 1}號[${l.source?.label ?? '?'}]${st.supportsTeam == null ? '' : st.supportsTeam! ? '(挺)' : '(反)'}：${st.text}');
      }
      out.writeln('   票：${[
        for (var s = 0; s < rec.votes.length; s++)
          '${s + 1}${rec.votes[s] ? '○' : '✕'}${p.decisions[s] == null ? '' : '(${voteReasonLabels[p.decisions[s]!.reason] ?? p.decisions[s]!.reason})'}'
      ].join(' ')}');
    }
    if (loyalty[q.number - 1] case final turned?) {
      out.writeln('   [蘭斯洛特] 第${q.number}次翻到：${turned ? '轉換陣營' : '不變'}');
    }
    if (q.result case final res?) {
      if (res.excaliburHolder case final h?) {
        out.writeln(
            '   [王者之劍] ${h + 1}號持劍，${res.excaliburTarget == null ? '沒有翻牌' : '翻了${res.excaliburTarget! + 1}號的牌'}');
      }
      out.writeln(
          '   >> 任務${res.succeeded ? '成功' : '失敗'}（${res.fails} 張失敗）出牌：${q.cards.entries.map((e) => '${e.key + 1}${e.value ? '成' : '敗'}').join(' ')}');
    }
  }
  for (final c in r.ladyChecks) {
    out.writeln(
        '   [湖中女神] 第${c.quest}次後 ${c.holder + 1}號查驗 ${c.target + 1}號（實際身分：${r.roles[c.target].label}）');
  }
  for (final l in r.endLines) {
    out.writeln('   [結尾] ${l.statement.speaker + 1}號：${l.statement.text}');
  }
  out.writeln('== ${r.winner} 勝：${r.result}');
}
