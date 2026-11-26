import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_tuning.dart';
import 'balance_test.dart' show Setup, play, randomSetup;

/// Tunes the computers' balance numbers (BotTuning) so that good wins about
/// [target] of all-computer games at every table size and with every kind
/// of expansion, at the normal level, with talk.
///
///   TUNE_ROUNDS=3 [TUNE_GAMES=1800] [TUNE_WORKERS=4] [TUNE_SEED=1]
///     flutter test test/tune_test.dart
///
/// Each round tries every number a step up and a step down on the same
/// games (fresh games each round), keeps what brings the win rates nearer,
/// and shrinks the step. Progress: build/llm/tune_log.txt; the result:
/// build/llm/tune_result.json (to copy into BotTuning.tuned).
///
/// TUNE_CHECK=file.json plays fresh games with those numbers (and with the
/// code's own) and only reports.
const target = .47;

/// Human-like play besides: how often the first quest fails, and how often
/// the Assassin finds Merlin (human tables: about 17% and 34%).
const firstFailTarget = .20, stabTarget = .35;

/// The share of games played without talk.
const quiet = .25;

/// What is tuned: the numbers that may differ between small and large
/// tables, and those that hold for all.
const split = [
  'merlinCover',
  'merlinVoiceInsight',
  'assassinNoise',
  'evilPush',
  'voteEvidence',
  'doubt',
  'questConceal',
  'evilLeaderCover',
];

/// Of [split], those set for each large table size on its own (7–10).
const perCount = ['voteEvidence', 'evilPush', 'merlinCover', 'assassinNoise'];

/// Of [split], those with a factor of their own at tables with Lancelot
/// (`name@Lan`, from 1).
const withLancelot = [
  'voteEvidence',
  'evilPush',
  'merlinCover',
  'assassinNoise',
  'questConceal',
  'evilLeaderCover',
];

const shared = [
  'firstQuestCover',
  'firstQuestCoverLarge',
  'lastChanceRisk',
  'tableDoubtWeight',
  'lancelotConceal',
  'lonelyFail',
  'switchAge',
  'ladyCorroboration',
  'callWeight',
  // this game's tactics (BotTactic)
  'lieLowShare',
  'earlyShare',
  'lieLowQ1',
  'lieLowQ2',
  'lieLowPair',
  'earlyCut',
  'hiddenShare',
  'guideShare',
  'hiddenCover',
  'guideCover',
];

/// Chances stay chances.
const _unit = {
  'merlinVoiceInsight',
  'questConceal',
  'firstQuestCover',
  'firstQuestCoverLarge',
  'lancelotConceal',
  'lonelyFail',
  'switchAge',
  'lieLowQ1',
  'lieLowQ2',
  'lieLowPair',
  'earlyCut',
};

double _default(String key) =>
    key.endsWith('@Lan') ? 1 : BotTuning.names[key.split('@').first]!;

/// One step of [key] from [value], up or down by [factor] (added, for
/// [doubt], which starts at nothing).
double _step(String key, double value, double factor, bool up) {
  final name = key.split('@').first;
  double next;
  if (name == 'doubt') {
    next = value + (up ? 1 : -1) * .08 * (factor - 1) / .3;
    next = next.clamp(-.25, .25);
  } else {
    next = up ? value * factor : value / factor;
    if (value == 0) next = up ? .05 : 0;
  }
  if (_unit.contains(name) && !key.endsWith('@Lan')) {
    next = next.clamp(0.0, 1.0);
  }
  return double.parse(next.toStringAsFixed(4));
}

/// Good wins and games, by table size and by kind of expansion.
class Tally {
  final wins = <String, int>{}, games = <String, int>{};
  void add(String group, bool goodWon) {
    games[group] = (games[group] ?? 0) + 1;
    if (goodWon) wins[group] = (wins[group] ?? 0) + 1;
  }

  double rate(String g) => (wins[g] ?? 0) / max(1, games[g] ?? 0);

  /// First quests failed, and stabs (wins['stab'] the hits).
  int firstFails = 0;
  double get firstFail => firstFails / max(1, games['all'] ?? 0);
  double get stab => (wins['stab'] ?? 0) / max(1, games['stab'] ?? 0);

  /// Distance from [target]: each group's squared miss, weighed by its
  /// share of the games; expansion kinds, each size with and without
  /// Lancelot, and games with and without talk count half.
  double get miss {
    final all = games['all'] ?? 1;
    var sum = 0.0;
    sum += pow(firstFail - firstFailTarget, 2) + pow(stab - stabTarget, 2);
    for (final g in games.keys) {
      if (g == 'all' || g == 'stab') continue;
      // n7: a size; c7Lan: a size with Lancelot; the rest: kinds, talk
      final w = (games[g]! / all) * (g.startsWith('n') ? 6 : 3);
      sum += w * pow(rate(g) - target, 2);
    }
    return sum;
  }

  String get line => [
        'all ${(rate('all') * 100).round()}%',
        'Q1敗 ${(firstFail * 100).round()}%',
        '刺中 ${(stab * 100).round()}%',
        for (final g
            in games.keys.where((g) => g != 'all' && g != 'stab').toList()
              ..sort())
          '$g ${(rate(g) * 100).round()}%/${games[g]}',
      ].join('  ');

  Map<String, Object> toJson() => {
        for (final g in games.keys) g: [wins[g] ?? 0, games[g]!],
        'firstFails': [firstFails, 0],
      };
}

String _kind(ExpansionSettings e) => e.lancelot > 0
    ? 'xLan${e.lancelot}'
    : 'x${e.lady ? 'Lady' : ''}${e.excalibur ? 'Sword' : ''}'
        .replaceFirst(RegExp(r'^x$'), 'xBase');

/// Plays [games] with [params] (the setups and seeds drawn from [seed]).
Map<String, Object> evaluate(Map<String, double> params, int games, int seed) {
  BotTuning.override(params);
  final r = Random(seed);
  final tally = Tally();
  for (var g = 0; g < games; g++) {
    final Setup setup = randomSetup(r);
    final s = r.nextInt(1 << 30);
    // a quarter of the games without talk, as a player may set it
    final talk = r.nextDouble() >= quiet;
    play(setup, s, talk, (session) {
      final good = session.winner == '正義';
      tally
        ..add('all', good)
        ..add('n${setup.count}', good)
        ..add(talk ? 'talk' : 'quiet', good)
        ..add(_kind(setup.expansions), good);
      // the sizes Lancelot may join, with him and without
      if (setup.count >= lancelotMinPlayers) {
        tally.add(
            'c${setup.count}${setup.expansions.lancelot > 0 ? 'Lan' : ''}',
            good);
      }
      if (!session.history.first.succeeded) tally.firstFails++;
      if (session.history.where((q) => q.succeeded).length >= 3) {
        tally.add('stab', !good);
      }
    });
  }
  BotTuning.override(const {});
  return {'miss': tally.miss, 'tally': tally.toJson()};
}

Tally _read(Map<String, Object?> result) {
  final t = Tally();
  for (final e in (result['tally'] as Map).entries) {
    final [w, n] = (e.value as List).cast<int>();
    if (e.key == 'firstFails') {
      t.firstFails = w;
      continue;
    }
    t.wins[e.key as String] = w;
    t.games[e.key as String] = n;
  }
  return t;
}

Future<List<Map<String, Object?>>> _many(
    List<Map<String, double>> sets, int games, int seed, int workers) async {
  final results = List<Map<String, Object?>?>.filled(sets.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < sets.length) {
      final i = next++;
      final params = sets[i];
      results[i] = await Isolate.run(() => evaluate(params, games, seed));
    }
  }

  await Future.wait([for (var w = 0; w < workers; w++) worker()]);
  return results.cast<Map<String, Object?>>();
}

void main() {
  final env = Platform.environment;
  final rounds = int.tryParse(env['TUNE_ROUNDS'] ?? '');
  final check = env['TUNE_CHECK'];
  final games = int.parse(env['TUNE_GAMES'] ?? '1800');
  final workers = int.parse(env['TUNE_WORKERS'] ?? '4');
  final seed = int.parse(env['TUNE_SEED'] ?? '1');
  Directory('build/llm').createSync(recursive: true);
  final log = File('build/llm/tune_log.txt');
  void say(String line) {
    log.writeAsStringSync('$line\n', mode: FileMode.append);
    // ignore: avoid_print
    print(line);
  }

  test('tune', () async {
    var params = <String, double>{
      for (final k in split) ...{
        '$k@small': BotTuning.of(k, _default(k), 5),
        if (perCount.contains(k))
          for (final n in [7, 8, 9, 10])
            '$k@$n': BotTuning.of(k, _default(k), n)
        else
          '$k@large': BotTuning.of(k, _default(k), 9),
      },
      for (final k in shared) k: BotTuning.of(k, _default(k), 9),
      for (final k in withLancelot)
        '$k@Lan': BotTuning.tuned['$k@Lan'] ?? 1.0,
    };
    // TUNE_ONLY=@Lan|@7 steps only the numbers whose key matches
    final only = env['TUNE_ONLY'] == null ? null : RegExp(env['TUNE_ONLY']!);
    // TUNE_FROM=2 starts at the third step (to refine settled numbers)
    final factors = [1.35, 1.18, 1.08, 1.04]
        .skip(int.parse(env['TUNE_FROM'] ?? '0'))
        .toList();
    for (var round = 0; round < rounds!; round++) {
      final factor = factors[min(round, factors.length - 1)];
      final roundSeed = seed * 1000 + round;
      final keys = [
        for (final k in params.keys)
          if (only == null || only.hasMatch(k)) k
      ];
      final sets = [
        params,
        for (final k in keys)
          for (final up in [true, false])
            {...params, k: _step(k, params[k]!, factor, up)},
      ];
      final started = DateTime.now();
      final results = await _many(sets, games, roundSeed, workers);
      final base = results.first['miss'] as double;
      say('== 第 ${round + 1} 輪（步伐 ×$factor，${sets.length} 組，'
          '${DateTime.now().difference(started).inMinutes} 分鐘）'
          '起點 miss ${base.toStringAsFixed(5)}  ${_read(results.first).line}');
      // the better of up and down for every number, where it helps
      final moves = <String, (double, double)>{};
      for (var i = 0; i < keys.length; i++) {
        for (final j in [1 + 2 * i, 2 + 2 * i]) {
          final miss = results[j]['miss'] as double;
          if (miss < base &&
              (moves[keys[i]] == null || miss < moves[keys[i]]!.$2)) {
            moves[keys[i]] = (sets[j][keys[i]]!, miss);
          }
        }
      }
      for (final m in moves.entries.toList()
        ..sort((a, b) => a.value.$2.compareTo(b.value.$2))) {
        say('   ${m.key}: ${params[m.key]} → ${m.value.$1}'
            '（miss ${m.value.$2.toStringAsFixed(5)}）');
      }
      if (moves.isEmpty) {
        say('   沒有更好的方向');
        continue;
      }
      // all the helpful moves together, or else the best one alone
      final together = {
        ...params,
        for (final m in moves.entries) m.key: m.value.$1,
      };
      final best =
          moves.entries.reduce((a, b) => a.value.$2 <= b.value.$2 ? a : b);
      final joint = (await _many([together], games, roundSeed, workers)).single;
      final jointMiss = joint['miss'] as double;
      if (jointMiss < best.value.$2) {
        params = together;
        say('   全部一起：miss ${jointMiss.toStringAsFixed(5)}  ${_read(joint).line}');
      } else {
        params = {...params, best.key: best.value.$1};
        say('   全部一起反而較差（${jointMiss.toStringAsFixed(5)}），只採用 ${best.key}');
      }
      File('build/llm/tune_result.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(params));
    }
  },
      timeout: const Timeout(Duration(hours: 12)),
      skip: rounds == null ? 'set TUNE_ROUNDS to run' : false);

  test('check', () async {
    final tuned = (jsonDecode(File(check!).readAsStringSync()) as Map)
        .map((k, v) => MapEntry(k as String, (v as num).toDouble()));
    // the code's own numbers (not BotTuning.tuned) against these
    final original = {for (final k in tuned.keys) k: _default(k)};
    final results =
        await _many([original, tuned], games, seed * 7919 + 13, workers);
    say('== 驗證（新牌局 $games 局）');
    say('   原本：miss ${(results[0]['miss'] as double).toStringAsFixed(5)}  '
        '${_read(results[0]).line}');
    say('   調後：miss ${(results[1]['miss'] as double).toStringAsFixed(5)}  '
        '${_read(results[1]).line}');
  },
      timeout: const Timeout(Duration(hours: 2)),
      skip: check == null ? 'set TUNE_CHECK to run' : false);
}
