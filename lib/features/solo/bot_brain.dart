import 'dart:math';
import '../game/game_model.dart';
import '../game/discussion_model.dart';
import '../lobby/room_model.dart';
import 'bot_observation.dart';

/// A deliberately modest, reproducible first opponent. All deductions come
/// from the supplied observation. Strategies may be wrong; moves remain legal.
class BotBrain {
  BotBrain(this.random);
  final Random random;

  List<double> suspicion(BotObservation o) {
    final p = List.filled(o.count, Room.evilCount(o.count) / o.count);
    final privateBeliefs = <int, double>{};
    for (var q = 0; q < o.history.length; q++) {
      final result = o.history[q];
      final switchedThen =
          o.loyalty.take(q + 1).where((v) => v == true).length.isOdd;
      final ageWeight =
          o.expansions.lancelot > 0 && switchedThen != o.switched ? .4 : 1.0;
      // A public flip may have manufactured a Fail. Never attribute it as
      // proof of an evil player, including on successful two-Fail quests.
      var unexplained =
          max(0, result.fails - (result.excaliburTarget == null ? 0 : 1));
      if (o.ownCards[q + 1] == false && result.excaliburTarget != o.seat) {
        unexplained = max(0, unexplained - 1);
      }
      for (final seat in result.team) {
        if (seat == o.seat) continue;
        if (unexplained > 0) {
          p[seat] +=
              ageWeight * .18 * unexplained / max(1, result.team.length - 1);
        } else if (result.fails == 0 && result.excaliburTarget == null) {
          // Success is weak evidence: evil players may play Success.
          p[seat] -= ageWeight * .025;
        }
      }
    }
    final seesEvil = o.role == Role.merlin ||
        (o.role.isEvil && o.role != Role.oberon && o.role != Role.lancelotEvil);
    if (seesEvil) {
      for (final seat in o.visible) {
        // An initially evil teammate may be a now-switched Lancelot.
        p[seat] = o.switched && o.expansions.lancelot > 0 ? .65 : .99;
        privateBeliefs[seat] = p[seat];
      }
    }
    if (o.role == Role.percival) {
      // Either candidate can be Morgana; never label one as Merlin here.
      for (final seat in o.visible) {
        p[seat] = o.visible.length == 1 ? .01 : .5;
        if (o.visible.length == 1) privateBeliefs[seat] = p[seat];
      }
    }
    for (final fact in o.facts) {
      final knownEvil = fact.evil ?? (fact.originalCard == false ? true : null);
      if (knownEvil == null) continue;
      final uncertain =
          o.expansions.lancelot > 0 && fact.switched != o.switched;
      p[fact.target] =
          knownEvil ? (uncertain ? .65 : .99) : (uncertain ? .35 : .01);
      privateBeliefs[fact.target] = p[fact.target];
    }
    // A claim is not a private fact. Trust it only weakly, according to the
    // observer's own current view of its author, and discount old alignments.
    for (final claim in o.statements) {
      if (claim.claimedEvil == null ||
          claim.target == null ||
          claim.speaker == o.seat ||
          claim.quest != o.quest ||
          (claim.switched != null && claim.switched != o.switched)) {
        continue;
      }
      final trust = max(0.0, .5 - p[claim.speaker]) * .2;
      p[claim.target!] += claim.claimedEvil! ? trust : -trust;
    }
    for (final statement in o.statements) {
      if (statement.supportsTeam == null || statement.speaker == o.seat) {
        continue;
      }
      // Public positions are weak behavioural evidence, never proof of a role.
      if (statement.supportsTeam! && statement.team.any((s) => p[s] >= .95)) {
        p[statement.speaker] += .025;
      }
    }
    for (final entry in privateBeliefs.entries) {
      p[entry.key] = entry.value;
    }
    p[o.seat] = o.evil ? 1 : 0;
    return [for (final value in p) value.clamp(0.0, 1.0)];
  }

  /// Independent estimates are a heuristic, not calibrated probabilities.
  double teamRisk(BotObservation o, List<int> team) {
    return _risk(suspicion(o), team, o.failsRequired);
  }

  double _risk(List<double> p, List<int> team, int requiredFails) {
    final counts = List.filled(team.length + 1, 0.0)..[0] = 1;
    var size = 0;
    for (final seat in team) {
      final fail = p[seat] * .85;
      for (var k = ++size; k >= 0; k--) {
        counts[k] = counts[k] * (1 - fail) + (k > 0 ? counts[k - 1] * fail : 0);
      }
    }
    return counts.skip(requiredFails).fold(0.0, (a, b) => a + b);
  }

  List<int> chooseTeam(BotObservation o, int size) {
    final candidates = <List<int>>[];
    void collect(List<int> prefix, int from) {
      if (prefix.length == size) {
        candidates.add(prefix);
        return;
      }
      for (var i = from; i <= o.count - (size - prefix.length); i++) {
        collect([...prefix, i], i + 1);
      }
    }

    collect([], 0);
    final p = suspicion(o);
    final scored = [
      for (final team in candidates)
        (
          team,
          (o.evil ? 1 : -1) * _risk(p, team, o.failsRequired) +
              (team.contains(o.seat) ? .08 : 0) +
              random.nextDouble() * .06
        )
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.first.$1;
  }

  bool vote(BotObservation o) {
    if (o.rejections == 4) return !o.evil;
    final risk = teamRisk(o, o.team);
    if (o.evil) return risk > .45 || random.nextDouble() < .12;
    final threshold = (o.failures == 2 ? .48 : .65) + o.rejections * .035;
    return risk <= threshold;
  }

  bool questCard(BotObservation o) {
    if (!o.evil) return true;
    if (o.mustFail) return false;
    if (o.failures == 2 || o.successes == 2) return false;
    final p = suspicion(o);
    final allies = o.team.where((s) => p[s] >= .95).toList()..sort();
    if (allies.length > o.failsRequired &&
        allies.indexOf(o.seat) >= o.failsRequired) {
      return true;
    }
    return random.nextDouble() < (o.quest == 1 ? .22 : .08);
  }

  int swordHolder(BotObservation o, List<int> team) {
    final p = suspicion(o);
    final choices = team.where((s) => s != o.leader).toList()
      ..sort((a, b) => (o.evil ? p[b].compareTo(p[a]) : p[a].compareTo(p[b])));
    return choices.first;
  }

  int? swordTarget(BotObservation o) {
    final p = suspicion(o);
    final choices = o.team.where((s) => s != o.seat).toList()
      ..sort((a, b) => o.evil ? p[a].compareTo(p[b]) : p[b].compareTo(p[a]));
    final target = choices.first;
    return o.evil || p[target] >= .62 ? target : null;
  }

  int ladyTarget(BotObservation o) {
    final p = suspicion(o);
    final choices = [
      for (var s = 0; s < o.count; s++)
        if (!o.ladyPast.contains(s)) s
    ];
    double information(int s) =>
        1 -
        (p[s] - .5).abs() * 2 +
        o.history.where((q) => q.team.contains(s)).length * .025;
    choices.shuffle(random);
    choices.sort((a, b) => information(b).compareTo(information(a)));
    return choices.first;
  }

  int assassinate(BotObservation o) {
    final p = suspicion(o);
    double merlinScore(int seat) {
      var score = 1 - p[seat];
      for (final proposal in o.proposals) {
        final containsKnownEvil = proposal.team.any(o.visible.contains);
        if (proposal.leader == seat && !containsKnownEvil) score += .25;
        if (proposal.votes[seat] != containsKnownEvil) score += .12;
      }
      return score + random.nextDouble() * .3;
    }

    final scored = [
      for (var s = 0; s < o.count; s++)
        if (s != o.seat && !o.visible.contains(s)) (s, merlinScore(s))
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.first.$1;
  }

  DiscussionStatement speech(BotObservation o, bool approve) {
    final failed = o.history.indexWhere((q) => q.fails > 0);
    final variants = approve
        ? [
            '我傾向讓這隊試一次，投票結果出來後再一起看。',
            '目前這個組合我可以接受，我會投贊成。',
            '先支持這次提案，成功也不代表隊上每個人都能完全信任。'
          ]
        : ['我對這隊還有疑慮，這次會投反對，想再換個組合。', '這份隊伍名單我還不太放心，我會投反對。', '我希望換人看看，這次先不支持。'];
    var text = variants[random.nextInt(variants.length)];
    if (o.rejections == 4 && approve) {
      text = '已經連續四次否決了，再否決就輸，我會先讓任務出發。';
    } else if (failed >= 0) {
      final q = o.history[failed];
      text = '第 ${failed + 1} 次遠征有 ${q.fails} 張失敗牌，'
          '${q.excaliburTarget != null ? '但那次也用了王者之劍，要一起考慮。' : '還不能只靠這次就認定是哪一個人出的。'}$text';
    }
    return DiscussionStatement(
        speaker: o.seat,
        quest: o.quest,
        text: text,
        supportsTeam: approve,
        team: o.team);
  }
}
