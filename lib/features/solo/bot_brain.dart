import 'dart:math';
import '../game/game_model.dart';
import '../game/discussion_model.dart';
import '../lobby/room_model.dart';
import 'bot_observation.dart';
import 'dialogue/bot_dialogue_planner.dart';

/// A deliberately modest, reproducible first opponent. All deductions come
/// from the supplied observation. Strategies may be wrong; moves remain legal.
class BotBrain {
  BotBrain(this.random, {Random? dialogueRandom})
      : dialogue = BotDialoguePlanner(dialogueRandom ?? Random(0));
  final Random random;
  final BotDialoguePlanner dialogue;

  List<double> suspicion(BotObservation o) {
    final opening = <int, double>{o.seat: o.evil ? 1 : 0};
    final privateBeliefs = <int, double>{...opening};
    final seesEvil = o.role == Role.merlin ||
        (o.role.isEvil && o.role != Role.oberon && o.role != Role.lancelotEvil);
    if (seesEvil) {
      for (final seat in o.visible) {
        opening[seat] = o.switched && o.expansions.lancelot > 0 ? .65 : 1;
        privateBeliefs[seat] = opening[seat]!;
      }
    }
    if (o.role == Role.percival) {
      // The pair contains one Merlin and one Morgana, never a Lancelot.
      for (final seat in o.visible) {
        opening[seat] = o.visible.length == 1 ? 0 : .5;
        if (o.visible.length == 1) privateBeliefs[seat] = 0;
      }
    }
    final facts = [...o.facts]..sort((a, b) => a.quest.compareTo(b.quest));
    for (final fact in facts) {
      final knownEvil = fact.evil ?? (fact.originalCard == false ? true : null);
      if (knownEvil == null) continue;
      final canBeLancelot =
          !(o.role == Role.percival && o.visible.contains(fact.target));
      final uncertain = o.expansions.lancelot > 0 &&
          fact.switched != o.switched &&
          canBeLancelot;
      final estimate =
          knownEvil ? (uncertain ? .65 : 1.0) : (uncertain ? .35 : 0.0);
      // An old uncertain clue must not dilute a current definite clue.
      if (uncertain && [0.0, 1.0].contains(privateBeliefs[fact.target])) {
        continue;
      }
      opening[fact.target] = estimate;
      privateBeliefs[fact.target] = estimate;
    }
    final unknown = o.count - opening.length;
    final remaining =
        Room.evilCount(o.count) - opening.values.fold(0.0, (a, b) => a + b);
    final prior = unknown == 0 ? 0.0 : (remaining / unknown).clamp(0.0, 1.0);
    final p = List.filled(o.count, prior);
    for (final entry in opening.entries) {
      p[entry.key] = entry.value;
    }
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
    return _risk(o, suspicion(o), team);
  }

  double _risk(BotObservation o, List<double> p, List<int> team,
      {int? flipped}) {
    final counts = List.filled(team.length + 1, 0.0)..[0] = 1;
    var size = 0;
    for (final seat in team) {
      var fail = p[seat] * .85;
      if (seat == o.seat && o.mustFail) fail = 1;
      if (seat == o.seat && o.ownCards.containsKey(o.quest)) {
        fail = o.ownCards[o.quest]! ? 0 : 1;
      }
      if (seat == flipped) fail = 1 - fail;
      for (var k = ++size; k >= 0; k--) {
        counts[k] = counts[k] * (1 - fail) + (k > 0 ? counts[k - 1] * fail : 0);
      }
    }
    return counts.skip(o.failsRequired).fold(0.0, (a, b) => a + b);
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
          (o.evil ? 1 : -1) * _risk(o, p, team) +
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
    final p = suspicion(o);
    final knownAllies = <int>{o.seat};
    if ((!o.switched || o.expansions.lancelot == 0) &&
        o.role != Role.oberon &&
        o.role != Role.lancelotEvil) {
      knownAllies.addAll(o.visible);
    }
    for (final fact in o.facts) {
      if (fact.switched != o.switched && o.expansions.lancelot > 0) continue;
      if (fact.evil == true || fact.originalCard == false) {
        knownAllies.add(fact.target);
      } else if (fact.evil == false) {
        knownAllies.remove(fact.target);
      }
    }
    final allies = o.team.where(knownAllies.contains).toList()..sort();
    if (allies.length >= max(2, o.failsRequired)) {
      // A shared seat-order convention needs no secret communication. Every
      // designated saboteur commits; surplus allies conceal themselves.
      return !allies.take(o.failsRequired).contains(o.seat);
    }
    if (o.failures == 2 || o.successes == 2 || o.failsRequired == 2) {
      return false;
    }
    var conceal = o.quest == 1 ? .38 : .16;
    final holder = o.excaliburHolder;
    if (holder != null && holder != o.seat && p[holder] <= .15) conceal += .2;
    return random.nextDouble() < conceal;
  }

  int swordHolder(BotObservation o, List<int> team) {
    final p = suspicion(o);
    final choices = team.where((s) => s != o.leader).toList()
      ..sort((a, b) => (o.evil ? p[b].compareTo(p[a]) : p[a].compareTo(p[b])));
    return choices.first;
  }

  int? swordTarget(BotObservation o) {
    final p = suspicion(o);
    final baseline = _risk(o, p, o.team);
    var bestGain = .000001;
    int? target;
    for (final seat in o.team.where((s) => s != o.seat)) {
      final flipped = _risk(o, p, o.team, flipped: seat);
      final gain = o.evil ? flipped - baseline : baseline - flipped;
      if (gain > bestGain) {
        bestGain = gain;
        target = seat;
      }
    }
    return target;
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

  DiscussionStatement speech(BotObservation o, bool approve) =>
      dialogue.speak(o, approve, (team) => teamRisk(o, team));

  DiscussionStatement assassinationSpeech(BotObservation o, int target) {
    if (o.phase != GamePhase.assassination ||
        o.role != Role.assassin ||
        target < 0 ||
        target >= o.count ||
        target == o.seat) {
      throw ArgumentError(
          'Assassination declaration needs an authorized committed target');
    }
    return dialogue.speak(o, false, (team) => teamRisk(o, team),
        chosenTarget: target);
  }
}
