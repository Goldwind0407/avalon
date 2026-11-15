import 'dart:io';
import 'dart:math';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_observation.dart';
import 'package:avalon_shadow_council/features/solo/bot_vote_plan.dart';
import 'package:avalon_shadow_council/features/solo/game_review.dart';
import 'package:avalon_shadow_council/features/solo/memory/match_repository.dart';
import 'package:avalon_shadow_council/features/solo/persona/bot_persona.dart';
import 'package:avalon_shadow_council/features/solo/solo_session.dart';
import 'solo_session_test.dart' show soloRoom;

/// Does what the regulars learn of the player help them? Opt-in:
///
///   MEMORY_TABLES=20 [MEMORY_GAMES=15] [MEMORY_OUT=file]
///     flutter test test/memory_eval_test.dart
///
/// The player's seat is played by a computer with one habit of its own;
/// each table plays a run of games twice on the same seeds, once with the
/// regulars using what they learned and once without.

/// As good, names someone at random as suspicious every time.
class WildCaller extends BotBrain {
  WildCaller(int seed) : super(Random(seed), dialogueRandom: Random(seed ^ 1));
  @override
  DiscussionStatement speech(BotObservation o, bool approve) {
    if (o.evil || o.history.isEmpty) return super.speech(o, approve);
    final others = [
      for (var s = 0; s < o.count; s++)
        if (s != o.seat) s
    ];
    final t = others[random.nextInt(others.length)];
    lastSpeechSource = const SpeechSource('亂點名', 'test');
    return DiscussionStatement(
        speaker: o.seat,
        quest: o.quest,
        generation: o.generation,
        attempt: o.proposalId.attempt,
        text: '我覺得${t + 1}號很可疑。',
        target: t,
        position: DiscussionPosition.suspect,
        supportsTeam: approve,
        team: o.team,
        switched: o.switched,
        intent: 'accuse');
  }
}

/// As good, names a player who really is evil (test only: it is told who).
/// The case where trusting the player's word pays.
class SharpCaller extends BotBrain {
  SharpCaller(int seed, this.evil)
      : super(Random(seed), dialogueRandom: Random(seed ^ 1));
  final bool Function(int seat) evil;
  @override
  DiscussionStatement speech(BotObservation o, bool approve) {
    if (o.evil || o.history.isEmpty) return super.speech(o, approve);
    final bad = [
      for (var s = 0; s < o.count; s++)
        if (s != o.seat && evil(s)) s
    ];
    final t = bad[random.nextInt(bad.length)];
    lastSpeechSource = const SpeechSource('說中', 'test');
    return DiscussionStatement(
        speaker: o.seat,
        quest: o.quest,
        generation: o.generation,
        attempt: o.proposalId.attempt,
        text: '我覺得${t + 1}號很可疑。',
        target: t,
        position: DiscussionPosition.suspect,
        supportsTeam: approve,
        team: o.team,
        switched: o.switched,
        intent: 'accuse');
  }
}

/// As evil, backs every team with an evil player on it and no other.
class CarelessEvil extends BotBrain {
  CarelessEvil(int seed)
      : super(Random(seed), dialogueRandom: Random(seed ^ 1));
  @override
  bool vote(BotObservation o, {Random? decisionRandom}) {
    final usual = super.vote(o, decisionRandom: decisionRandom);
    if (!o.evil || o.rejections == 4 || o.leader == o.seat) return usual;
    final dirty = o.team.any((s) => s == o.seat || o.visible.contains(s));
    final d = lastVoteDecision!;
    lastVoteDecision = BotVoteDecision(dirty, 'careless', d.risk, d.suspicion);
    return dirty;
  }
}

/// As Merlin, leads any team at all.
class ServantMerlin extends BotBrain {
  ServantMerlin(int seed)
      : super(Random(seed), dialogueRandom: Random(seed ^ 1));
  @override
  List<int> chooseTeam(BotObservation o, int size) {
    if (o.role != Role.merlin) return super.chooseTeam(o, size);
    final others = [
      for (var s = 0; s < o.count; s++)
        if (s != o.seat) s
    ]..shuffle(random);
    return [o.seat, ...others.take(size - 1)]..sort();
  }
}

class Tally {
  var games = 0, goodWins = 0;
  var goodVotes = 0, goodVotesRight = 0;
  var evilGames = 0, evilGoodWins = 0;
  var doubtWhenEvil = 0.0, doubtSamples = 0;
  var merlinStabs = 0, merlinStabbed = 0;

  void add(GameReview r) {
    games++;
    if (r.winner == '正義') goodWins++;
    for (final q in r.quests) {
      for (final round in q.proposals) {
        final p = round.record;
        if (p.attempt == 5) continue;
        final dirty = p.team.any((s) => r.evilIn(s, q.number));
        for (var s = 1; s < r.players.length; s++) {
          if (r.evilIn(s, q.number) || s == p.leader) continue;
          goodVotes++;
          if (p.votes[s] != dirty) goodVotesRight++;
        }
      }
    }
    if (r.evil(0)) {
      evilGames++;
      if (r.winner == '正義') evilGoodWins++;
      final last = r.quests.reversed
          .expand((q) => q.proposals.reversed)
          .map((p) => p.decisions)
          .firstWhere((d) => d.isNotEmpty, orElse: () => const {});
      for (final e in last.entries) {
        if (e.key == 0 || r.evil(e.key)) continue;
        doubtWhenEvil += e.value.suspicion[0];
        doubtSamples++;
      }
    }
    if (r.roles[0] == Role.merlin && r.assassinTarget != null) {
      merlinStabs++;
      if (r.assassinTarget == 0) merlinStabbed++;
    }
  }

  String pct(int a, int b) =>
      b == 0 ? '  -' : '${(100 * a / b).round().toString().padLeft(3)}%';
  @override
  String toString() => '$games 局 好人勝${pct(goodWins, games)}'
      '　好人電腦投票判斷正確${pct(goodVotesRight, goodVotes)}'
      '　你當壞人時好人勝${pct(evilGoodWins, evilGames)}（$evilGames 局）'
      '　最後好人電腦對你的懷疑 ${doubtSamples == 0 ? '-' : (doubtWhenEvil / doubtSamples).toStringAsFixed(2)}'
      '　你當梅林被刺中${pct(merlinStabbed, merlinStabs)}（$merlinStabs 局）';
}

/// Plays [games] games in a row at one table; tallies those from
/// [from] on (once the regulars have something to go on).
Tally runTable(
    int table, BotBrain Function(int, SoloGameSession Function()) habit,
    {required bool learns, int games = 15, int from = 5}) {
  final tally = Tally();
  fakeAsync((time) {
    var clock = DateTime(2026, 11, 15);
    final repository = MatchRepository(storage: MemoryMatchStorage());
    late final SoloGameSession s;
    s = SoloGameSession(soloRoom(7, const ExpansionSettings()),
        random: Random(table),
        personas: BotPersona.deal(6, Random(table)),
        archive: repository,
        now: () => clock = clock.add(const Duration(minutes: 30)),
        botDelay: const Duration(milliseconds: 1),
        speechDuration: const Duration(milliseconds: 1),
        autopilot: true,
        playerBrain: (seed) => habit(seed, () => s),
        learnsPlayer: learns);
    for (var g = 0; g < games; g++) {
      time.flushMicrotasks();
      var steps = 0;
      while (s.phase != GamePhase.finished && steps++ < 20000) {
        if (s.phase == GamePhase.voteResult) s.continueVote();
        if (s.phase == GamePhase.questResult) s.continueQuest();
        time.elapse(const Duration(milliseconds: 1));
        time.flushMicrotasks();
      }
      expect(s.phase, GamePhase.finished);
      if (g >= from) tally.add(s.review!);
      time.elapse(const Duration(milliseconds: 5));
      time.flushMicrotasks();
      if (g + 1 < games) s.restart();
      time.flushMicrotasks();
    }
    s.dispose();
    time.flushMicrotasks();
  });
  return tally;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final tables = int.tryParse(Platform.environment['MEMORY_TABLES'] ?? '');
  final games = int.tryParse(Platform.environment['MEMORY_GAMES'] ?? '') ?? 15;
  test('the regulars learn the player', () {
    final out = StringBuffer();
    final only = Platform.environment['MEMORY_HABITS']?.split(',');
    for (final (name, habit)
        in <(String, BotBrain Function(int, SoloGameSession Function()))>[
      ('亂點名的好人', (seed, _) => WildCaller(seed)),
      ('投票露餡的壞人', (seed, _) => CarelessEvil(seed)),
      ('亂帶隊的梅林', (seed, _) => ServantMerlin(seed)),
      (
        '點名很準的好人',
        (seed, session) =>
            SharpCaller(seed, (seat) => session().trulyEvil(seat))
      ),
    ]) {
      if (only != null && !only.any(name.contains)) continue;
      final on = Tally(), off = Tally();
      for (var t = 0; t < tables!; t++) {
        for (final (learns, tally) in [(true, on), (false, off)]) {
          final r = runTable(t, habit, learns: learns, games: games);
          tally
            ..games += r.games
            ..goodWins += r.goodWins
            ..goodVotes += r.goodVotes
            ..goodVotesRight += r.goodVotesRight
            ..evilGames += r.evilGames
            ..evilGoodWins += r.evilGoodWins
            ..doubtWhenEvil += r.doubtWhenEvil
            ..doubtSamples += r.doubtSamples
            ..merlinStabs += r.merlinStabs
            ..merlinStabbed += r.merlinStabbed;
        }
      }
      out
        ..writeln('== $name（每桌 $games 局，從第 6 局起算）')
        ..writeln('有記憶：$on')
        ..writeln('無記憶：$off');
    }
    final path = Platform.environment['MEMORY_OUT'];
    if (path != null) File(path).writeAsStringSync('$out');
    // ignore: avoid_print
    print(out);
  }, skip: tables == null ? 'set MEMORY_TABLES to run' : false);
}
