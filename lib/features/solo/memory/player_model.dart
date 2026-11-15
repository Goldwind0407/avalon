import 'dart:math';
import '../../game/discussion_model.dart';
import '../../game/game_model.dart';
import '../game_review.dart';
import 'match_archive.dart';

/// Counts of what one finished game showed about how the player plays,
/// read off the revealed record. Every count is judged by the side the
/// player (and anyone they talked about) played for at the time. Keys are
/// stable short names, so a version that does not know a key ignores it.
abstract final class Trait {
  /// Games played on each side (by the side at the end).
  static const gamesGood = 'gG', gamesEvil = 'gE', gamesMerlin = 'gM';

  /// As a good player: suspect/vouch calls, and how many were right.
  static const goodCalls = 'gc', goodCallsRight = 'gcR';

  /// As an evil player: calls, and how many pointed the table the wrong way
  /// (suspecting a good player, vouching for an evil one).
  static const evilCalls = 'ec', evilCallsMisleading = 'ecM';

  /// Lady results the player announced, and how many were true.
  static const ladyClaims = 'lc', ladyClaimsTrue = 'lcT';

  /// Games in which the player claimed Percival, and how many were true.
  static const percivalClaims = 'pc', percivalClaimsTrue = 'pcT';

  /// Off-team votes (not leading, not the fifth proposal): how many teams
  /// with an evil player on them / clean teams the player saw and backed,
  /// as good and as evil.
  static const goodSawDirty = 'gD', goodBackedDirty = 'gDy';
  static const goodSawClean = 'gC', goodBackedClean = 'gCy';
  static const evilSawDirty = 'eD', evilBackedDirty = 'eDy';
  static const evilSawClean = 'eC', evilBackedClean = 'eCy';

  /// Teams led, and how many were clean: as Merlin, and as another good
  /// player.
  static const merlinLeads = 'mL', merlinLeadsClean = 'mLc';
  static const goodLeads = 'oL', goodLeadsClean = 'oLc';
}

/// What [r] shows about the player in seat [r.mySeat].
Map<String, int> playerTraits(GameReview r) {
  final me = r.mySeat;
  final t = <String, int>{};
  // nothing is learned from a game whose sides cannot all be told
  if (!r.sidesKnown) return t;
  void add(String key, [bool counts = true]) {
    if (counts) t[key] = (t[key] ?? 0) + 1;
  }

  add(r.evil(me) ? Trait.gamesEvil : Trait.gamesGood);
  final merlin = r.roles[me] == Role.merlin;
  if (merlin) add(Trait.gamesMerlin);
  var claimedPercival = false;
  // Said again is not seen again: each player the player called counts
  // once per quest (the last call stands), each Lady check once.
  final calls = <String, (bool right, bool asEvil)>{};
  final ladyResults = <String, bool>{};
  for (final q in r.quests) {
    final iEvil = r.evilIn(me, q.number);
    bool evil(int s) => r.evilIn(s, q.number);
    for (final round in q.proposals) {
      final p = round.record;
      if (p.attempt < 5 && p.leader != me && !p.team.contains(me)) {
        final dirty = p.team.any(evil);
        final yes = p.votes[me];
        if (iEvil) {
          add(dirty ? Trait.evilSawDirty : Trait.evilSawClean);
          add(dirty ? Trait.evilBackedDirty : Trait.evilBackedClean, yes);
        } else {
          add(dirty ? Trait.goodSawDirty : Trait.goodSawClean);
          add(dirty ? Trait.goodBackedDirty : Trait.goodBackedClean, yes);
        }
      }
      if (p.leader == me && !iEvil) {
        final clean = !p.team.any(evil);
        add(merlin ? Trait.merlinLeads : Trait.goodLeads);
        add(merlin ? Trait.merlinLeadsClean : Trait.goodLeadsClean, clean);
      }
      for (final line in round.lines) {
        final s = line.statement;
        if (s.speaker != me) continue;
        if (s.claimsPercival) claimedPercival = true;
        final target = s.target;
        if (target == null || target == me) continue;
        if (s.claimedEvil != null) {
          // the side the target had when the player checked them
          final check = r.ladyChecks
              .where((c) => c.holder == me && c.target == target)
              .lastOrNull;
          if (check != null) {
            ladyResults['${check.quest}/$target'] =
                s.claimedEvil == r.evilIn(target, check.quest);
          }
          continue;
        }
        if (s.position == null) continue;
        calls['${s.quest}/$target'] = (
          (s.position == DiscussionPosition.suspect) ==
              r.evilIn(target, s.quest),
          r.evilIn(me, s.quest)
        );
      }
    }
  }
  for (final (right, asEvil) in calls.values) {
    if (asEvil) {
      add(Trait.evilCalls);
      add(Trait.evilCallsMisleading, !right);
    } else {
      add(Trait.goodCalls);
      add(Trait.goodCallsRight, right);
    }
  }
  for (final right in ladyResults.values) {
    add(Trait.ladyClaims);
    add(Trait.ladyClaimsTrue, right);
  }
  if (claimedPercival) {
    add(Trait.percivalClaims);
    add(Trait.percivalClaimsTrue, r.roles[me] == Role.percival);
  }
  return t;
}

/// One learned rate: [value] starts at the population [prior] and moves
/// toward what this player did, as the (forgetting-weighted) [events] grow.
/// [games] is the weighted number of games that contributed.
class LearnedRate {
  const LearnedRate(this.value, this.events, this.games, this.prior);
  final double value, events, games, prior;

  /// How far [value] stands on this player's own record rather than on the
  /// prior: 0 with no record, toward 1 with many games.
  double get confidence => games / (games + PlayerModel.trustAfterGames);
  bool get known => games >= .5;
}

/// What one computer player has learned about how the human plays, from
/// the finished games it sat in. Only ever built from revealed records.
/// Says nothing about which side the human is on in the game being
/// played; it is about habits.
class PlayerModel {
  PlayerModel._(this.rates, this.gamesTogether);

  /// A game this many games back counts half.
  static const halfLife = 10.0;

  /// Pseudo-observations the population prior is worth.
  static const priorWeight = 4.0;

  /// Games of record at which a rate is half the player's, half the prior.
  static const trustAfterGames = 5.0;

  /// The computer players' own rates over 3000 simulated games.
  static const priors = <String, double>{
    Trait.goodCallsRight: .72,
    Trait.evilCallsMisleading: .89,
    Trait.ladyClaimsTrue: .8,
    Trait.percivalClaimsTrue: .5,
    Trait.goodBackedDirty: .3,
    Trait.goodBackedClean: .5,
    Trait.evilBackedDirty: .56,
    Trait.evilBackedClean: .38,
    Trait.merlinLeadsClean: .64,
    Trait.goodLeadsClean: .42,
  };

  /// Each rate: the count of hits, out of the count of chances.
  static const _rates = <String, String>{
    Trait.goodCallsRight: Trait.goodCalls,
    Trait.evilCallsMisleading: Trait.evilCalls,
    Trait.ladyClaimsTrue: Trait.ladyClaims,
    Trait.percivalClaimsTrue: Trait.percivalClaims,
    Trait.goodBackedDirty: Trait.goodSawDirty,
    Trait.goodBackedClean: Trait.goodSawClean,
    Trait.evilBackedDirty: Trait.evilSawDirty,
    Trait.evilBackedClean: Trait.evilSawClean,
    Trait.merlinLeadsClean: Trait.merlinLeads,
    Trait.goodLeadsClean: Trait.goodLeads,
  };

  final Map<String, LearnedRate> rates;
  final double gamesTogether;

  LearnedRate rate(String hits) => rates[hits]!;

  /// Null when [personaId] has no game with the player whose record was
  /// counted. [summaries] newest first.
  static PlayerModel? of(String personaId, List<MatchSummary> summaries) {
    final hits = <String, double>{}, chances = <String, double>{};
    final games = <String, double>{};
    var together = 0.0;
    for (final (ago, s) in summaries.indexed) {
      final traits = s.traits;
      if (traits == null || !s.episodes.containsKey(personaId)) continue;
      final w = pow(.5, ago / halfLife).toDouble();
      together += w;
      for (final e in _rates.entries) {
        final n = traits[e.value] ?? 0;
        if (n == 0) continue;
        chances[e.key] = (chances[e.key] ?? 0) + w * n;
        hits[e.key] = (hits[e.key] ?? 0) + w * (traits[e.key] ?? 0);
        games[e.key] = (games[e.key] ?? 0) + w;
      }
    }
    if (together == 0) return null;
    return PlayerModel._({
      for (final key in _rates.keys)
        key: LearnedRate(
            ((hits[key] ?? 0) + priorWeight * priors[key]!) /
                ((chances[key] ?? 0) + priorWeight),
            chances[key] ?? 0,
            games[key] ?? 0,
            priors[key]!)
    }, together);
  }
}

/// For the computer player's page: what it has learned about the player,
/// one line per habit it has enough record of.
List<String> playerModelLines(PlayerModel? model) {
  if (model == null) return const [];
  String pct(double v) => '${(100 * v).round()}%';
  String n(LearnedRate r) =>
      '約 ${r.games.toStringAsFixed(r.games < 10 ? 1 : 0)} 局';
  final lines = <String>[];
  void line(String hits, String text) {
    final r = model.rate(hits);
    if (r.known) lines.add('$text ${pct(r.value)}（${n(r)}）');
  }

  line(Trait.goodCallsRight, '你當好人時，點名說中');
  line(Trait.evilCallsMisleading, '你當壞人時，點名帶錯方向');
  line(Trait.ladyClaimsTrue, '你報的湖中女神結果屬實');
  line(Trait.percivalClaimsTrue, '你跳派西維爾是真的');
  line(Trait.goodBackedDirty, '你當好人、不在隊上時，贊成有壞人的隊');
  line(Trait.evilBackedDirty, '你當壞人、不在隊上時，贊成有壞人的隊');
  line(Trait.evilBackedClean, '你當壞人、不在隊上時，贊成乾淨的隊');
  line(Trait.merlinLeadsClean, '你當梅林時，帶的隊完全乾淨');
  line(Trait.goodLeadsClean, '你當其他好人時，帶的隊完全乾淨');
  return lines;
}
