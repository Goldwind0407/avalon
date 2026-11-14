import 'dart:math';
import '../game/game_model.dart';
import '../game/discussion_model.dart';
import '../lobby/room_model.dart';
import 'bot_difficulty.dart';
import 'bot_observation.dart';
import 'bot_style.dart';
import 'bot_voice.dart';
import 'bot_vote_plan.dart';
import 'dialogue/bot_dialogue_planner.dart';

/// A deliberately modest, reproducible first opponent. All deductions come
/// from the supplied observation. Strategies may be wrong; moves remain legal.
class BotBrain {
  BotBrain(this.random,
      {Random? dialogueRandom,
      this.style = BotStyle.balanced,
      this.difficulty = BotDifficulty.normal})
      : dialogue = BotDialoguePlanner(dialogueRandom ?? Random(0));
  final Random random;
  final BotStyle style;
  final BotDifficulty difficulty;

  /// How readily Merlin votes like a servant while no quest has failed
  /// (times his style's disguise; halved after the first failed quest).
  static const merlinCover = 3.0;

  /// How often Merlin turns down a team he knows is clean, and only while
  /// at most this many proposals of the quest have been turned down.
  static const merlinFalseAlarm = .3;
  static const merlinSpareRejections = 2;
  final BotDialoguePlanner dialogue;

  /// With [asServant], what this seat would think without its opening role
  /// knowledge: the view Merlin pretends to have.
  List<double> suspicion(BotObservation o, {bool asServant = false}) {
    final opening = <int, double>{o.seat: o.evil ? 1 : 0};
    final privateBeliefs = <int, double>{...opening};
    final seesEvil = !asServant &&
        (o.role == Role.merlin ||
            (o.role.isEvil &&
                o.role != Role.oberon &&
                o.role != Role.lancelotEvil));
    if (seesEvil) {
      for (final seat in o.visible) {
        // Evil players know which ally is Lancelot: after a switch he is
        // good and everyone else is still evil. Merlin cannot tell them
        // apart, so a switch leaves each of them in doubt.
        opening[seat] = o.lancelotSeat != null
            ? (seat == o.lancelotSeat && o.switched ? 0 : 1)
            : (o.switched && o.expansions.lancelot > 0 ? .65 : 1);
        privateBeliefs[seat] = opening[seat]!;
      }
    }
    if (o.role == Role.percival && !asServant) {
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
    _voteEvidence(o, p);
    // Establish card/deal constraints first. Applying this afterwards used to
    // erase 90% of an expert's response to discussion, making expert listeners
    // less responsive than novices. Public claims remain soft and cannot
    // override deductions that hold in every legal deal.
    _deduce(o, p, privateBeliefs);
    final certain = <int, double>{
      for (var s = 0; s < p.length; s++)
        if (p[s] == 0 || p[s] == 1) s: p[s],
    };
    // A claim is not a private fact. It is remembered for the whole game
    // (a novice only minds the latest) and trusted according to the
    // observer's own current view of its author; claims from before a
    // Lancelot switch are dropped.
    final credibility = List<double>.of(p);
    final claims = <String, DiscussionStatement>{};
    for (final claim in o.statements) {
      if (claim.claimedEvil != null && claim.quotedFrom == null) {
        claims['${claim.speaker}/${claim.target}/${claim.switched}'] = claim;
      }
    }
    for (final claim in claims.values) {
      if (claim.claimedEvil == null ||
          claim.target == null ||
          claim.speaker == o.seat ||
          (!difficulty.remembersClaims && claim.quest != o.quest) ||
          (claim.switched != null && claim.switched != o.switched)) {
        continue;
      }
      final trust =
          max(0.0, .5 - credibility[claim.speaker]) * difficulty.claimTrust;
      p[claim.target!] += claim.claimedEvil! ? trust : -trust;
    }
    // Who doubts or vouches for whom: weak, weighted by how far this seat
    // trusts the speaker. Framing a good player works on the gullible.
    final latestPositions = <String, DiscussionStatement>{};
    for (final statement in o.statements) {
      if (statement.position != null &&
          statement.quotedFrom == null &&
          statement.generation == o.generation &&
          (statement.switched == null || statement.switched == o.switched)) {
        latestPositions['${statement.speaker}/${statement.target}'] = statement;
      }
    }
    for (final statement in latestPositions.values) {
      final target = statement.target;
      if (statement.position == null ||
          target == null ||
          statement.speaker == o.seat ||
          target == statement.speaker ||
          statement.generation != o.generation) {
        continue;
      }
      final trust = max(0.0, .55 - credibility[statement.speaker]) * .2;
      p[target] +=
          statement.position == DiscussionPosition.suspect ? trust : -trust;
    }
    final publicVotes = <String, DiscussionStatement>{};
    for (final statement in o.statements) {
      if (statement.supportsTeam != null &&
          statement.quotedFrom == null &&
          (statement.switched == null || statement.switched == o.switched)) {
        publicVotes[
                '${statement.quest}/${statement.attempt}/${statement.speaker}'] =
            statement;
      }
    }
    for (final statement in publicVotes.values) {
      if (statement.supportsTeam == null || statement.speaker == o.seat) {
        continue;
      }
      // Public positions are weak behavioural evidence, never proof of a role.
      if (statement.supportsTeam! && statement.team.any((s) => p[s] >= .95)) {
        p[statement.speaker] += .025;
      }
    }
    final knows = o.role == Role.percival && !asServant && !o.evil;
    // An evil player knows who is who; a claim tells him nothing about
    // the others, only (as the Assassin) about Merlin.
    if (!knows && (!o.evil || asServant)) {
      _weighClaims(o, p, credibility, pretending: asServant);
    }
    for (final entry in {...certain, ...privateBeliefs}.entries) {
      p[entry.key] = entry.value;
    }
    if (knows) _checkClaims(o, p);
    p[o.seat] = o.evil ? 1 : 0;
    return [for (final value in p) value.clamp(0.0, 1.0)];
  }

  /// The latest "I am Percival" of every other player this game.
  Map<int, DiscussionStatement> _percivalClaims(BotObservation o) => {
        for (final s in o.statements)
          if (s.generation == o.generation &&
              s.claimsPercival &&
              s.quotedFrom == null &&
              s.speaker != o.seat &&
              (s.switched == null || s.switched == o.switched))
            s.speaker: s
      };

  /// What a player who is not Percival makes of such claims. One claimant
  /// is believed as far as his record allows, and the player he calls
  /// Morgana is doubted that much more. Two claimants cannot both be
  /// telling the truth: the one with the worse record is taken for the
  /// liar. And whoever is called Morgana knows the claimant is lying.
  void _weighClaims(BotObservation o, List<double> p, List<double> credibility,
      {required bool pretending}) {
    final claims = _percivalClaims(o);
    if (claims.isEmpty) return;
    final claimants = claims.keys.toList()
      ..sort((a, b) => credibility[a].compareTo(credibility[b]));
    final trust = difficulty.claimTrust * 2;
    for (final (rank, c) in claimants.indexed) {
      final named = claims[c]!.target;
      if (named == o.seat) {
        // Percival's two are Merlin and Morgana. A loyal servant named as
        // one of them has caught a liar; Merlin may have met a Percival
        // who mixed his two up, and he sees which it is anyway.
        if (o.role != Role.merlin) p[c] = max(p[c], pretending ? .7 : .95);
        continue;
      }
      if (rank > 0) {
        // the less credible of several claimants
        p[c] += .25 * trust;
        continue;
      }
      final belief = max(0.0, .65 - credibility[c]) *
          trust *
          (claimants.length > 1 ? .7 : 1);
      if (named != null) p[named] += belief;
      if (claimants.length > 1) p[c] += .05;
    }
  }

  /// The real Percival knows every other claimant is lying, and who his
  /// two candidates are. A claimant outside the pair is plainly evil. One
  /// of the pair who calls Percival himself Morgana is Morgana, which makes
  /// the other one Merlin. One of the pair naming the other is most likely
  /// Merlin helping out; one naming a third player could be either.
  void _checkClaims(BotObservation o, List<double> p) {
    if (o.visible.length != 2) return;
    final [a, b] = o.visible;
    for (final claim in _percivalClaims(o).values) {
      final c = claim.speaker, named = claim.target;
      if (!o.visible.contains(c)) {
        p[c] = max(p[c], .9);
        continue;
      }
      final other = c == a ? b : a;
      if (named == o.seat) {
        p[c] = 1;
        p[other] = 0;
      } else if (named == other) {
        p[c] = max(0, p[c] - .3);
        p[other] = min(1, p[other] + .3);
      }
      // Naming someone else: Morgana lying, or Merlin bluffing. Whichever
      // of the two already looked worse stays the likelier Morgana.
    }
  }

  /// Fail cards on quest number [index] + 1 that this player cannot explain
  /// with a sword flip or their own card; null when the quest proves nothing
  /// now (the Lancelots have changed sides since).
  int? _unexplained(BotObservation o, int index) {
    final result = o.history[index];
    final switchedThen =
        o.loyalty.take(index + 1).where((v) => v == true).length.isOdd;
    if (o.expansions.lancelot > 0 && switchedThen != o.switched) return null;
    var fails = result.fails - (result.excaliburTarget == null ? 0 : 1);
    if (o.ownCards[index + 1] == false && result.excaliburTarget != o.seat) {
      fails--;
    }
    return max(0, fails);
  }

  /// Who voted for the team that then failed is the table's main public clue:
  /// approving it from outside is suspicious, rejecting it reassuring; turning
  /// down a team that came back clean is a lesser hint. The forced fifth
  /// proposal says nothing.
  void _voteEvidence(BotObservation o, List<double> p) {
    for (var q = 0; q < o.history.length; q++) {
      final approved =
          o.proposals.where((r) => r.quest == q + 1 && r.approved).toList();
      if (approved.isEmpty || approved.last.attempt >= 5) continue;
      final proposal = approved.last;
      if (o.history[q].excaliburTarget != null) continue;
      final fails = _unexplained(o, q);
      if (fails == null) continue;
      for (var s = 0; s < o.count; s++) {
        if (s == o.seat || proposal.team.contains(s)) continue;
        final approve = proposal.votes[s];
        // Backing a team that then failed weighs most; turning down one
        // that came back clean is a smaller hint the other way.
        p[s] += (fails > 0 ? (approve ? .4 : -.25) : (approve ? 0 : .08)) *
            difficulty.voteEvidence;
      }
    }
  }

  /// The logic every player does at the table: go through every way the evil
  /// seats could be dealt that fits what this player knows for certain and the
  /// Fail cards seen. A seat that is evil in all of them is evil; a seat that
  /// is evil in none is good; the others move towards how often they are.
  void _deduce(
      BotObservation o, List<double> p, Map<int, double> privateBeliefs) {
    final n = o.count, evils = Room.evilCount(n);
    final mustBe = <int, bool>{
      for (final e in privateBeliefs.entries)
        if (e.value == 0 || e.value == 1) e.key: e.value == 1,
      o.seat: o.evil,
    };
    // (other team members, Fail cards they played, how readily evil fails)
    final quests = <(List<int>, int, double)>[];
    for (var q = 0; q < o.history.length; q++) {
      final fails = _unexplained(o, q);
      if (fails == null || o.history[q].excaliburTarget != null) continue;
      quests.add((
        [
          for (final s in o.history[q].team)
            if (s != o.seat) s
        ],
        fails,
        // evil players hide more often on the first quest
        q == 0 ? .6 : .8
      ));
    }
    // Percival: exactly one of his two candidates is Morgana.
    final pair =
        o.role == Role.percival && o.visible.length == 2 ? o.visible : null;
    if (quests.isEmpty && mustBe.length == 1) return;
    final inEvil = List.filled(n, 0), weightEvil = List.filled(n, 0.0);
    var fits = 0, weight = 0.0;
    final set = <int>[];
    void walk(int from) {
      if (set.length == evils) {
        for (final e in mustBe.entries) {
          if (set.contains(e.key) != e.value) return;
        }
        if (pair != null && set.contains(pair[0]) == set.contains(pair[1])) {
          return;
        }
        // How well this deal explains the cards seen. Evil players on one
        // team agree to show only as many Fails as needed, so a Fail says
        // "at least that many" and no more; a clean quest speaks against
        // every evil player who would have had to hold back.
        var likelihood = 1.0;
        for (final (team, fails, f) in quests) {
          final k = team.where(set.contains).length;
          if (k < fails) return;
          if (fails == 0) likelihood *= pow(1 - f, k);
        }
        fits++;
        weight += likelihood;
        for (final s in set) {
          inEvil[s]++;
          weightEvil[s] += likelihood;
        }
        return;
      }
      for (var s = from; s <= n - (evils - set.length); s++) {
        set.add(s);
        walk(s + 1);
        set.removeLast();
      }
    }

    walk(0);
    if (fits == 0) return; // contradictory clues: keep the soft estimate
    for (var s = 0; s < n; s++) {
      if (s == o.seat) continue;
      if (inEvil[s] == 0 || inEvil[s] == fits) {
        p[s] = inEvil[s] == 0 ? 0 : 1;
      } else if (!privateBeliefs.containsKey(s)) {
        // mostly the reasoned estimate, nudged by votes and claims
        final r = difficulty.reasoning;
        p[s] = (1 - r) * p[s].clamp(0.0, 1.0) + r * weightEvil[s] / weight;
      }
    }
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
    // Early on, Merlin sometimes sends the team an ordinary servant would,
    // so that his proposals are not always spotless.
    final early = o.failures == 0 && o.successes < 2;
    final hide = o.role == Role.merlin &&
        early &&
        random.nextDouble() < style.disguise * difficulty.rolePlay;
    final allies = o.evil ? _knownAllies(o) : const <int>{};
    // Morgana poses as Merlin: early on she may lead a team that looks
    // spotless, herself and players nobody doubts, and keep her allies off.
    final pose = o.role == Role.morgana &&
        o.evil &&
        early &&
        o.quest <= 2 &&
        random.nextDouble() < .6 * difficulty.rolePlay;
    final p = suspicion(o, asServant: hide || pose);
    if (pose) {
      for (final s in allies) {
        p[s] = s == o.seat ? 0 : 1;
      }
    }
    // Mordred is the one evil player Merlin cannot warn against, so he
    // pushes himself forward.
    final selfBias = style.selfBias + (o.role == Role.mordred ? .1 : 0);
    final scored = [
      for (final team in candidates)
        (
          team,
          (o.evil && !pose ? 1 : -1) * _risk(o, p, team) +
              (team.contains(o.seat) ? selfBias : 0) +
              // An evil leader brings just enough saboteurs: every extra
              // ally on a failed quest is one more player exposed.
              -difficulty.stacking *
                  max(0, team.where(allies.contains).length - o.failsRequired) +
              random.nextDouble() * style.noise * difficulty.noise
        )
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.first.$1;
  }

  BotVoteDecision? lastVoteDecision;

  bool vote(BotObservation o, {Random? decisionRandom}) {
    final rng = decisionRandom ?? random;
    final p = suspicion(o);
    final risk = _risk(o, p, o.team);
    bool decide(bool approve, String reason) {
      lastVoteDecision = BotVoteDecision(approve, reason, risk, p);
      return approve;
    }

    // The fifth proposal passes whatever a minority does (a tie or less is
    // needed to reject), and votes are public: rejecting only exposes evil.
    if (o.rejections == 4) return decide(true, 'fifthProposal');
    if (o.evil) {
      if (risk > .45) {
        // Backing every team an ally is on gives the whole side away. When
        // an ally on it is already under suspicion, sometimes vote against
        // it like a careful good player would, unless this quest matters.
        final view = suspicion(o, asServant: true);
        final exposed = o.team.any((s) =>
            s != o.seat && _knownAllies(o).contains(s) && view[s] >= .55);
        final critical = o.failures == 2 || o.successes == 2;
        if (exposed &&
            !critical &&
            rng.nextDouble() < .35 * difficulty.rolePlay * style.blend) {
          return decide(false, 'concealAlly');
        }
        return decide(true, 'sabotageOpportunity');
      }
      // A team that will not fail: go along with it early to blend in, fight
      // it when it would be good's winning quest.
      // Nobody has a reason to object to the very first team yet; an evil
      // player who does stands out.
      var blend = o.history.isEmpty
          ? .85
          : o.successes == 2
              ? .1
              : o.quest <= 2
                  ? .55
                  : .3;
      // Morgana wants Percival to take her for Merlin: she backs clean teams.
      if (o.role == Role.morgana && o.successes < 2) {
        blend += .2 * difficulty.rolePlay;
      }
      // Mordred can afford to look agreeable: Merlin does not see him.
      if (o.role == Role.mordred && o.successes < 2) blend += .1;
      final approveChance = o.history.isEmpty
          ? .9 // whatever the style: objecting to the first team stands out
          : min(.9, blend * style.blend * difficulty.blend);
      return decide(rng.nextDouble() < approveChance, 'evilBlend');
    }
    var real = _goodVote(o, p);
    // a beginner sometimes simply votes the other way
    if (difficulty.slip > 0 && rng.nextDouble() < difficulty.slip) {
      return decide(!real, 'noviceSlip');
    }
    // Merlin who always votes by what he sees is found by the Assassin, so
    // now and then he votes like a servant who knows nothing. Not when one
    // more failed quest would lose the game.
    // The less is at stake, the more he can afford to play the servant.
    final disguise = style.disguise *
        difficulty.rolePlay *
        (o.failures == 0 ? merlinCover : merlinCover / 2);
    if (o.role == Role.merlin &&
        (disguise > 0 || o.history.isEmpty) &&
        o.failures < 2) {
      final cover = _goodVote(o, suspicion(o, asServant: true));
      // letting a doubtful team through is the costlier act: do it less
      var chance = min(.85, cover ? disguise * .8 : disguise * 1.3);
      // Turning down the very first team, when nobody else has a reason
      // to, tells the Assassin who knows something.
      if (o.history.isEmpty) chance = max(chance, .6);
      if (cover != real && rng.nextDouble() < chance) {
        return decide(cover, 'merlinDisguise');
      }
    }
    // Turning down a clean team costs only a proposal, while every vote
    // that matches where evil sits is counted by the Assassin. Now and
    // then Merlin turns down a team he knows is clean, while there are
    // proposals to spare.
    if (o.role == Role.merlin &&
        real &&
        o.history.isNotEmpty &&
        o.rejections <= merlinSpareRejections &&
        o.team.every((s) => p[s] < .5) &&
        rng.nextDouble() < merlinFalseAlarm * difficulty.rolePlay) {
      return decide(false, 'merlinDisguise');
    }
    return decide(real, real ? 'acceptableRisk' : 'unsafeTeam');
  }

  bool _goodVote(BotObservation o, List<double> p) {
    final risk = _risk(o, p, o.team);
    // Do not wave through a player this seat clearly doubts.
    if (o.failsRequired == 1 &&
        o.team.any((s) => s != o.seat && p[s] >= difficulty.doubt)) {
      return false;
    }
    // "Is this about as safe as the team I would send?" rather than a fixed
    // bar, so large teams are not rejected just for being large.
    final safest = [for (var s = 0; s < o.count; s++) s]
      ..sort((a, b) => p[a].compareTo(p[b]));
    final best = _risk(o, p, safest.take(o.team.length).toList());
    var margin = o.failures == 2
        ? .05 + .03 * o.rejections
        : (o.history.isEmpty ? .3 : .1) + .04 * o.rejections;
    // People go along with a leader they have come to trust, and look
    // harder at the team of one they doubt.
    final prior = Room.evilCount(o.count) / o.count;
    if (o.leader != o.seat) {
      var sway = .3 * style.follow;
      // Percival backs the candidate he takes for Merlin, and doubts the
      // other one; it also makes him look as informed as Merlin.
      if (o.role == Role.percival && o.visible.contains(o.leader)) {
        sway += .5 * difficulty.rolePlay;
      }
      margin += (prior - p[o.leader]) * sway;
    }
    return risk <= best + margin + style.trusting;
  }

  /// Seats this (evil) player knows are on their side right now: the opening
  /// view while it still holds, plus their own Lady and sword findings.
  Set<int> _knownAllies(BotObservation o) {
    final known = <int>{o.seat};
    if (o.role != Role.oberon && o.role != Role.lancelotEvil) {
      if (o.lancelotSeat != null) {
        // only the Lancelot leaves when the sides switch
        known.addAll(
            o.visible.where((s) => !(o.switched && s == o.lancelotSeat)));
      } else if (!o.switched || o.expansions.lancelot == 0) {
        known.addAll(o.visible);
      }
    }
    for (final fact in o.facts) {
      if (fact.switched != o.switched && o.expansions.lancelot > 0) continue;
      if (fact.evil == true || fact.originalCard == false) {
        known.add(fact.target);
      } else if (fact.evil == false) {
        known.remove(fact.target);
      }
    }
    return known;
  }

  bool questCard(BotObservation o) {
    if (!o.evil) return true;
    if (o.mustFail) return false;
    final p = suspicion(o);
    final knownAllies = _knownAllies(o);
    final allies = o.team.where(knownAllies.contains).toList()..sort();
    if (allies.length >= max(2, o.failsRequired)) {
      // A shared seat-order convention needs no secret communication. Every
      // designated saboteur commits; surplus allies conceal themselves.
      return !allies.take(o.failsRequired).contains(o.seat);
    }
    if (o.failsRequired == 2) {
      // One Fail alone changes nothing and gives this seat away. Only play
      // it when someone else on the team may well add the second one.
      return !o.team.any((s) => !knownAllies.contains(s) && p[s] >= .5);
    }
    if (o.failures == 2 || o.successes == 2) return false;
    var conceal = (o.quest == 1 ? .38 : .16) + style.conceal;
    if (o.role == Role.morgana && o.quest <= 2) {
      conceal += .15 * difficulty.rolePlay;
    }
    // On a pair, a Fail tells the partner exactly who played it.
    if (o.team.length == 2) conceal += .1 * difficulty.rolePlay;
    // Oberon and evil Lancelot have no ally who knows to cover for them or
    // to fail in their place, so they hold back less.
    if (o.role == Role.oberon || o.role == Role.lancelotEvil) conceal -= .08;
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
    if (!o.evil) return _goodSwordTarget(o);
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

  /// A good holder flips blind: the card turns over whatever it was. Evil
  /// players often play Success when a trusted holder has the sword, and
  /// only one of two evil members needs to fail, so a flip usually turns a
  /// Success into a Fail. Flip only a card that very likely is a Fail, never
  /// on the first quest, and Merlin judges by the record alone, so the
  /// flip does not show what he knows.
  int? _goodSwordTarget(BotObservation o) {
    if (o.quest == 1) return null;
    final p = suspicion(o, asServant: o.role == Role.merlin);
    final others = o.team.where((s) => s != o.seat).toList();
    final likely = others.where((s) => p[s] >= .5).length;
    final baseline = _risk(o, p, o.team);
    int? target;
    var best = .55;
    for (final seat in others) {
      // a flip that cannot save the quest is not worth the risk
      if (_risk(o, p, o.team, flipped: seat) >= baseline) continue;
      // an evil player under a trusted sword fails a bit over half the time
      var fail = p[seat] * .62;
      if (likely >= 2) fail *= .6;
      if (fail > best) {
        best = fail;
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
    if (o.evil) {
      // An evil holder learns little. Half the time the Lady goes to an
      // ally, who is then "cleared" and keeps her in evil hands; otherwise
      // to a good player, who can be framed.
      final allies = _knownAllies(o)..remove(o.seat);
      if (allies.isNotEmpty) {
        final wanted = random.nextBool();
        final group =
            choices.where((s) => allies.contains(s) == wanted).toList();
        if (group.isNotEmpty) return group[random.nextInt(group.length)];
      }
    }
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
    final evil = {o.seat, ...o.visible};
    // Merlin gives himself away by acting on what only he can know. A
    // beginner only notices who leads clean teams; most players also count
    // votes that match where evil sat; an expert weighs them: turning down
    // a team with evil on it early, before the table had a reason to, says
    // most, agreeing with a clean team says little, and leading or waving
    // through evil speaks against.
    double merlinScore(int seat) {
      var score = 1 - p[seat];
      for (final proposal in o.proposals) {
        if (proposal.attempt >= 5) continue; // everyone approves the fifth
        final dirty = proposal.team.any(evil.contains);
        final approved = proposal.votes[seat];
        switch (difficulty) {
          case BotDifficulty.novice:
            if (proposal.leader == seat && !dirty) score += .25;
          case BotDifficulty.normal:
            if (proposal.leader == seat && !dirty) score += .25;
            if (approved != dirty) score += .12;
          case BotDifficulty.expert:
            final early = proposal.quest <= 2 ? 1.3 : 1.0;
            if (proposal.leader == seat) score += dirty ? -.3 : .2;
            if (approved) {
              score +=
                  dirty ? (proposal.team.contains(seat) ? -.04 : -.12) : .05;
            } else {
              score += dirty ? .16 * early : -.08;
            }
        }
      }
      return score + random.nextDouble() * difficulty.assassinNoise;
    }

    // What a Percival claim gives away. A claimant who names another of
    // us knows something; that is usually Percival, since Merlin seldom
    // dares to pose as him. One who calls the Assassin himself Morgana
    // knows he is evil but has the role wrong, which is Merlin's mistake.
    // And a good claimant who names a good player has mixed his two
    // candidates up: that player is Merlin.
    final leaked = List.filled(o.count, 0.0);
    if (difficulty != BotDifficulty.novice) {
      for (final claim in _percivalClaims(o).values) {
        final c = claim.speaker, named = claim.target;
        if (evil.contains(c) || named == null) continue;
        if (named == o.seat) {
          leaked[c] += 1.2;
        } else if (evil.contains(named)) {
          leaked[c] -= .25;
        } else {
          leaked[named] += 1.5;
        }
      }
    }
    final scored = [
      for (var s = 0; s < o.count; s++)
        if (s != o.seat && !o.visible.contains(s))
          (s, merlinScore(s) + leaked[s])
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.first.$1;
  }

  late final voice = BotVoice(dialogue.random, style, difficulty);

  DiscussionStatement speech(BotObservation o, bool approve) {
    // A question put to this seat in this round is answered first (the
    // template catalogue knows how). Otherwise name names when the public
    // record gives a reason to, or fall back on a catalogue line.
    final asked = o.statements.any((s) =>
        s.questionTo == o.seat &&
        s.speaker != o.seat &&
        s.quest == o.quest &&
        s.attempt == o.proposalId.attempt &&
        s.generation == o.generation &&
        !o.statements.any((r) =>
            r.speaker == o.seat && r.replyTo == o.statements.indexOf(s)));
    if (asked) {
      final question = o.statements.indexed.lastWhere((e) =>
          e.$2.questionTo == o.seat &&
          e.$2.speaker != o.seat &&
          e.$2.quest == o.quest &&
          e.$2.attempt == o.proposalId.attempt &&
          !o.statements.any((r) => r.speaker == o.seat && r.replyTo == e.$1));
      lastSpeechSource = const SpeechSource.reply();
      return voice.reply(
          o, approve, question.$1, o.evil ? _knownAllies(o) : const <int>{});
    }
    final view = suspicion(o, asServant: true), real = suspicion(o);
    final allies = o.evil ? _knownAllies(o) : const <int>{};
    if (voice.claim(o, approve, view, real, allies) case final claimed?) {
      lastSpeechSource = claimed.claimsPercival
          ? const SpeechSource.claim()
          : SpeechSource.voice('defendSelf');
      return claimed;
    }
    final direct = voice.speak(o, approve, view, real, allies);
    if (direct != null) {
      lastSpeechSource = SpeechSource.voice(direct.intent ?? '');
      return direct;
    }
    // Before the first quest there is nothing to go on: people say a word
    // and let it go, rather than talk about records that do not exist.
    if (o.history.isEmpty) {
      if (voice.recall(o, approve) case final recalled?) {
        lastSpeechSource = const SpeechSource.memory();
        return recalled;
      }
      lastSpeechSource = const SpeechSource.firstQuest();
      return voice.firstQuest(o, approve);
    }
    // Most of the time say something about what actually happened: who was
    // on which quest, who voted how. The catalogue keeps its share for the
    // role-flavoured lines, the fifth proposal and the expansion events.
    final special = o.rejections >= 4 ||
        o.history.last.excaliburTarget != null ||
        o.ladyChecks.any((c) => c.quest == o.history.length);
    if (dialogue.random.nextDouble() <
        (special
            ? .35
            : o.seat == o.leader
                ? .9
                : .75)) {
      final cited = voice.evidence(o, approve, allies, o.evil ? view : real);
      if (cited != null) {
        lastSpeechSource = SpeechSource.evidence(cited.topic ?? '');
        return cited;
      }
    }
    final s = dialogue.speak(o, approve, (team) => teamRisk(o, team));
    lastSpeechSource = SpeechSource.catalog(dialogue.lastTrace?.ruleId);
    final text = voice.flavor(s.text);
    return text == s.text ? s : s.copyWithText(text);
  }

  /// Where the last [speech] came from, for the game review (never public).
  SpeechSource? lastSpeechSource;

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

/// Where a bot's line came from, so a review can say how to change it.
class SpeechSource {
  const SpeechSource(this.label, this.where);
  const SpeechSource.claim()
      : label = '跳身分',
        where = 'lib/features/solo/bot_voice_claims.dart 的 claim()';
  const SpeechSource.reply()
      : label = '回答提問',
        where = 'lib/features/solo/bot_voice.dart 的 reply()';
  const SpeechSource.firstQuest()
      : label = '第一輪短句',
        where = 'lib/features/solo/bot_voice.dart 的 firstQuest()';
  SpeechSource.voice(String intent)
      : label = switch (intent) {
          'accuse' => '點名',
          'defendOther' => '辯護',
          _ => '主動發言',
        },
        where = 'lib/features/solo/bot_voice.dart 的 speak()';
  const SpeechSource.memory()
      : label = '提起舊局',
        where = 'lib/features/solo/memory/social_memory.dart 的 memoryLines()';
  SpeechSource.evidence(String topic)
      : label = '引用紀錄',
        where = 'lib/features/solo/bot_voice_points.dart'
            '（主題 ${topic.split('/').first}）';
  SpeechSource.catalog(String? rule)
      : label = rule == null ? '台詞庫' : '台詞 $rule',
        where = rule == null
            ? 'docs/bot_dialogue_natural.txt'
            : 'docs/bot_dialogue_natural.txt 開頭為「$rule |」的那一行';

  /// Short tag shown next to the line.
  final String label;

  /// Where to edit it.
  final String where;
}
