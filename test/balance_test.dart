import 'dart:io';
import 'dart:math';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/lobby/role_presets.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_voice.dart';
import 'package:avalon_shadow_council/features/solo/persona/bot_persona.dart';
import 'package:avalon_shadow_council/features/solo/solo_session.dart';

/// Win balance over many random all-computer games: 5 to 10 players and a
/// random mix of expansions. Each setup is played twice, with and without
/// the spoken discussion, so the effect of talk can be told apart.
/// Runs only when asked for:
///   BALANCE_GAMES=1000 [BALANCE_SEED=1] [BALANCE_OUT=balance.txt]
///   flutter test test/balance_test.dart
class Tally {
  int games = 0, goodWins = 0, completed = 0, stabs = 0, stabHits = 0;
  int evilByFails = 0, evilByRejections = 0;
  // quests sent out: by a good / evil leader, and how many carried evil
  int goodLed = 0, goodLedDirty = 0, evilLed = 0, evilLedDirty = 0;
  int dirtyApprovals = 0, dirtyGoodVoters = 0;
  // games in which someone claimed to be Percival, and two or more did
  int claimGames = 0, rivalGames = 0, claimGoodWins = 0;
  void add(SoloGameSession s) {
    games++;
    final claimants = {
      for (final st in s.statements)
        if (st.claimsPercival) st.speaker
    };
    if (claimants.isNotEmpty) {
      claimGames++;
      if (s.winner == '正義') claimGoodWins++;
    }
    if (claimants.length > 1) rivalGames++;
    bool evil(int seat) => s.roleOf(seat)!.isEvil;
    for (final p in s.proposalHistory.where((p) => p.approved)) {
      final dirty = p.team.any(evil);
      if (evil(p.leader)) {
        evilLed++;
        if (dirty) evilLedDirty++;
      } else {
        goodLed++;
        if (dirty) goodLedDirty++;
      }
      if (dirty && p.attempt < 5) {
        dirtyApprovals++;
        dirtyGoodVoters += [
          for (var i = 0; i < p.votes.length; i++)
            if (p.votes[i] && !evil(i)) i
        ].length;
      }
    }
    final good = s.winner == '正義';
    if (good) goodWins++;
    final successes = s.history.where((q) => q.succeeded).length;
    if (successes >= 3) {
      completed++;
      stabs++;
      if (!good) stabHits++;
    } else if (!good) {
      if (s.result.contains('五次')) {
        evilByRejections++;
      } else {
        evilByFails++;
      }
    }
  }

  static String pc(int a, int b) =>
      b == 0 ? '  -  ' : '${(100 * a / b).toStringAsFixed(0).padLeft(3)}% ';
  String row(String label) => '${label.padRight(16)}'
      '${games.toString().padLeft(5)}  好人勝 ${pc(goodWins, games)}'
      '完成三任務 ${pc(completed, games)}刺中梅林 ${pc(stabHits, stabs)}'
      '三次失敗 ${pc(evilByFails, games)}五次否決 ${pc(evilByRejections, games)}'
      '| 好人隊長帶到壞人 ${pc(goodLedDirty, goodLed)}壞人隊長 ${pc(evilLedDirty, evilLed)}'
      '有壞人的隊平均 ${dirtyApprovals == 0 ? '-' : (dirtyGoodVoters / dirtyApprovals).toStringAsFixed(1)} 個好人贊成'
      ' | 有人跳派西 ${pc(claimGames, games)}對跳 ${pc(rivalGames, games)}跳了之後好人勝 ${pc(claimGoodWins, claimGames)}';
}

class Setup {
  Setup(this.count, this.expansions);
  final int count;
  final ExpansionSettings expansions;
  String get label => [
        if (expansions.lady) '女神',
        if (expansions.excalibur) '劍',
        if (expansions.lancelot > 0) '蘭${expansions.lancelot}',
      ].join('+').ifEmpty('基本');
}

extension on String {
  String ifEmpty(String other) => length == 0 ? other : this;
}

Setup randomSetup(Random r) {
  // BALANCE_PLAYERS=7-10 narrows the table sizes; BALANCE_EXP=lancelot2
  // (or none, lady, excalibur, lancelot1, joined by '+') fixes the rules
  final range = (Platform.environment['BALANCE_PLAYERS'] ?? '5-10')
      .split('-')
      .map(int.parse)
      .toList();
  final count = range.first + r.nextInt(range.last - range.first + 1);
  final fixed = Platform.environment['BALANCE_EXP']?.split('+');
  if (fixed != null) {
    return Setup(
        count,
        ExpansionSettings(
            lady: fixed.contains('lady'),
            excalibur: fixed.contains('excalibur'),
            lancelot: fixed.contains('lancelot2')
                ? 2
                : fixed.contains('lancelot1')
                    ? 1
                    : 0));
  }
  return Setup(
      count,
      ExpansionSettings(
          lady: r.nextBool(),
          excalibur: r.nextBool(),
          lancelot: (count >= lancelotMinPlayers)
              ? const [0, 0, 1, 2][r.nextInt(4)]
              : 0));
}

/// game, players, good won, quests completed, stabbed Merlin, then for the
/// first Percival claim: quest, who made it (role), whether the player it
/// named really is Morgana, and how many claimed in all.
String gameLine(int g, Setup setup, SoloGameSession s) {
  final first = s.statements.where((st) => st.claimsPercival).firstOrNull;
  final claimants = {
    for (final st in s.statements)
      if (st.claimsPercival) st.speaker
  };
  final successes = s.history.where((q) => q.succeeded).length;
  return [
    g,
    setup.count,
    s.winner == '正義' ? 1 : 0,
    successes >= 3 ? 1 : 0,
    successes >= 3 && s.winner != '正義' ? 1 : 0,
    first?.quest ?? 0,
    first == null ? '-' : s.roleOf(first.speaker)!.name,
    first?.target == null
        ? '-'
        : s.roleOf(first!.target!) == Role.morgana
            ? 'right'
            : s.roleOf(first.target!)!.name,
    claimants.length,
  ].join(',');
}

void play(
    Setup setup, int seed, bool talk, void Function(SoloGameSession) done) {
  final cast = BotPersona.deal(setup.count - 1, Random(seed));
  final room = Room(code: '', players: [
    Player(id: '0', name: '玩家', isReady: true),
    for (final (i, p) in cast.indexed)
      Player(id: '${i + 1}', name: p.name, isReady: true)
  ])
    ..specialRoles.addAll([for (final r in rolePreset(setup.count)!) r.label])
    ..discussion =
        talk ? DiscussionSettings.recommended : const DiscussionSettings()
    ..expansions = setup.expansions;
  fakeAsync((time) {
    final s = SoloGameSession(room,
        random: Random(seed),
        personas: cast,
        botDelay: const Duration(milliseconds: 1),
        speechDuration: const Duration(milliseconds: 1),
        autopilot: true);
    var steps = 0;
    while (s.phase != GamePhase.finished && steps++ < 20000) {
      if (s.phase == GamePhase.voteResult) s.continueVote();
      if (s.phase == GamePhase.questResult) s.continueQuest();
      time.elapse(const Duration(milliseconds: 1));
      time.flushMicrotasks();
    }
    expect(s.phase, GamePhase.finished, reason: '${setup.label} seed $seed');
    done(s);
    s.dispose();
    time.flushMicrotasks();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final games = int.tryParse(Platform.environment['BALANCE_GAMES'] ?? '');

  test('balance', () {
    final r = Random(int.parse(Platform.environment['BALANCE_SEED'] ?? '1'));
    final out = StringBuffer();
    // BALANCE_LOG=file: one line a game, to compare two runs game by game
    final logPath = Platform.environment['BALANCE_LOG'];
    final log = logPath == null ? null : StringBuffer();
    // the same setups and seeds for both runs
    final setups = [for (var g = 0; g < games!; g++) randomSetup(r)];
    final seeds = [for (var g = 0; g < games; g++) r.nextInt(1 << 30)];
    // BALANCE_TALK=on|off runs only that one; both by default
    // BALANCE_CLAIMS=off: nobody claims a role
    if (Platform.environment['BALANCE_CLAIMS'] == 'off') {
      BotVoice.percivalClaimChance =
          BotVoice.morganaClaimChance = BotVoice.merlinClaimChance = 0;
    }
    final mode = Platform.environment['BALANCE_TALK'];
    for (final talk in [
      if (mode != 'off') true,
      if (mode != 'on') false,
    ]) {
      final all = Tally();
      final byCount = <int, Tally>{}, byExpansion = <String, Tally>{};
      for (var g = 0; g < games; g++) {
        final setup = setups[g];
        play(setup, seeds[g], talk, (s) {
          log?.writeln(gameLine(g, setup, s));
          all.add(s);
          byCount.putIfAbsent(setup.count, Tally.new).add(s);
          byExpansion.putIfAbsent(setup.label, Tally.new).add(s);
        });
      }
      out.writeln('\n===== ${talk ? '有對話' : '不對話'}（$games 局）');
      out.writeln(all.row('全部'));
      out.writeln('-- 依人數');
      for (final c in byCount.keys.toList()..sort()) {
        out.writeln(byCount[c]!.row('$c 人'));
      }
      out.writeln('-- 依擴充');
      final labels = byExpansion.keys.toList()
        ..sort(
            (a, b) => byExpansion[b]!.games.compareTo(byExpansion[a]!.games));
      for (final l in labels) {
        out.writeln(byExpansion[l]!.row(l));
      }
    }
    if (logPath != null) File(logPath).writeAsStringSync('$log');
    final path = Platform.environment['BALANCE_OUT'];
    if (path != null) File(path).writeAsStringSync('$out');
    // ignore: avoid_print
    print(out);
  },
      timeout: const Timeout(Duration(minutes: 60)),
      skip: games == null ? 'set BALANCE_GAMES to run' : false);
}
