import '../../game/discussion_model.dart';
import '../../game/game_model.dart';
import '../game_review.dart';

/// A referee for the computer players: it goes through a finished game and
/// finds the moves a player made against what it could prove at the time.
///
/// It reasons only from hard facts — what a role sees at the start, the Fail
/// cards, a player's own cards and its own Lady checks — over every way the
/// evil seats could have been dealt. Nothing from the bots' own estimates
/// is used, so a finding is a contradiction, not a matter of style:
///  * H1 a good player backs a team with enough players it can prove evil
///    to sink the quest;
///  * H2 a good leader puts such a team together;
///  * H3 a good player turns down the fifth proposal (evil wins outright);
///  * H4 an evil player whose one Fail would win the game plays Success;
///  * H5 a good player speaks up for someone it can prove evil, or
///    accuses someone it can prove good;
///  * H6 a good player reports its Lady check the wrong way round;
///  * H7 the Assassin strikes an ally;
///  * H8 Percival backs a team with both of the two he saw (one of them is
///    Morgana) for a quest one Fail sinks, with proposals to spare;
/// and, on likelihood rather than proof:
///  * S1 a good player backs a team with enough evil on it to sink it in
///    most deals that fit what it knows, where a team of that size with
///    itself on it would be clean in most;
///  * S2 an evil player lets through the good side's third success;
///  * S3 one of two Fails needed to win the game, held back.
///
/// Merlin plays a servant on purpose: he is judged on what a servant in his
/// seat could prove (his own Lady checks included). Novices' deliberate
/// slips are left alone. With the Lancelots, every side is the one played
/// at that point of the game, and the deals include who the two Lancelots
/// are (only games whose switch timeline was kept are judged).
class BotAudit {
  BotAudit(this.review)
      : n = review.players.length,
        evils = review.roles.where((r) => r.isEvil).length;
  final GameReview review;
  final int n, evils;

  bool get supported => review.sidesKnown;

  List<AuditFinding> findings() {
    if (!supported) return const [];
    final out = <AuditFinding>[];
    final roles = review.roles;
    var failures = 0, successes = 0;
    for (final quest in review.quests) {
      final q = quest.number;
      final needed = n >= 7 && q == 4 ? 2 : 1;
      for (final round in quest.proposals) {
        final p = round.record;
        for (var s = 0; s < n; s++) {
          if (review.evilIn(s, q)) continue;
          final reason = round.decisions[s]?.reason;
          if (reason == 'noviceSlip') continue;
          final view = DealView.of(review, s, q,
              publicOnly: roles[s] == Role.merlin);
          if (view == null) continue;
          final yes = p.votes[s];
          final where = AuditPlace(q, p.attempt);
          if (p.attempt == 5 && !yes) {
            out.add(AuditFinding('H3', s, where, '第五次提案投反對', reason));
            continue;
          }
          if (p.attempt >= 5) continue;
          final proven = [
            for (final m in p.team)
              if (m != s && view.provenEvil(m)) m
          ];
          // enough proven evil to sink the quest (one evil player cannot
          // fail a quest that needs two Fails)
          if (s == p.leader && proven.length >= needed) {
            out.add(AuditFinding('H2', s, where,
                '當隊長卻帶了可證明是壞人的 ${_seats(proven)}', reason));
          } else if (yes && proven.length >= needed) {
            out.add(AuditFinding('H1', s, where,
                '贊成的隊伍裡有可證明是壞人的 ${_seats(proven)}', reason));
          } else if (yes &&
              needed == 1 &&
              p.attempt <= 3 &&
              roles[s] == Role.percival &&
              _bothCandidates(s, p.team)) {
            out.add(AuditFinding('H8', s, where,
                '贊成的隊伍同時帶了自己看到的兩位（必有一位是莫甘娜）', reason));
          } else if (yes && s != p.leader) {
            // only where a far cleaner team of that size was there to have
            final dirty = view.chanceAtLeast(p.team, needed, without: s);
            if (dirty >= .85) {
              final best = view.bestChance(p.team.length, needed, s);
              if (best <= .35) {
                out.add(AuditFinding(
                    'S1',
                    s,
                    where,
                    '贊成的隊伍按邏輯有 ${(dirty * 100).round()}% 帶到足以破壞任務的壞人，'
                        '最乾淨的組合只有 ${(best * 100).round()}%',
                    reason));
              }
            }
          }
        }
        for (final line in round.lines) {
          final f = _speech(line.statement, q, where: AuditPlace(q, p.attempt));
          if (f != null) out.add(f);
        }
      }
      final result = quest.result;
      if (result == null) continue;
      // evil holding back where a Fail would have won or saved the game
      if (result.excaliburTarget == null && result.fails < needed) {
        final lifeline = result.fails + 1 >= needed;
        for (final s in result.team) {
          if (!review.evilIn(s, q) || quest.cards[s] != true || !lifeline) {
            continue;
          }
          if (failures == 2) {
            // provable only where his one Fail was enough: on a two-Fail
            // quest he cannot be sure another ally plays the second
            out.add(needed == 1
                ? AuditFinding('H4', s, AuditPlace(q, null),
                    '再一次失敗邪惡就贏，卻出了成功', null)
                : AuditFinding('S3', s, AuditPlace(q, null),
                    '要兩張失敗的任務，他一張失敗就能湊齊（邪惡就贏）卻出了成功', null));
          } else if (successes == 2) {
            out.add(AuditFinding('S2', s, AuditPlace(q, null),
                '出成功讓正義拿下第三次成功', null));
          }
        }
      }
      if (result.succeeded) {
        successes++;
      } else {
        failures++;
      }
    }
    final target = review.assassinTarget;
    if (target != null) {
      final assassin = roles.indexOf(Role.assassin);
      if (assassin >= 0 && visibleSeats(roles, assassin).contains(target)) {
        out.add(AuditFinding('H7', assassin, const AuditPlace(null, null),
            '刺殺了自己看得到的邪惡隊友 ${target + 1}號', null));
      }
    }
    return out;
  }

  AuditFinding? _speech(DiscussionStatement s, int quest,
      {required AuditPlace where}) {
    final speaker = s.speaker, target = s.target;
    if (target == null || target == speaker || s.quotedFrom != null) {
      return null;
    }
    // A Lady check reported the wrong way round. What it showed is the side
    // then (the latest check counts); only a player who was good when he
    // made it must tell it as it was: a Lancelot who checked on the evil
    // side may go on lying about it after switching.
    final checks = review.ladyChecks.where(
        (c) => c.holder == speaker && c.target == target && c.quest < quest);
    if (s.claimedEvil != null &&
        checks.isNotEmpty &&
        !review.evilIn(speaker, checks.last.quest) &&
        s.claimedEvil != review.evilIn(target, checks.last.quest)) {
      return AuditFinding('H6', speaker, where,
          '把湖中女神的結果說反了（${target + 1}號）：${s.text}', null);
    }
    final position = s.position;
    if (position == null || review.evilIn(speaker, quest)) return null;
    final view = DealView.of(review, speaker, quest,
        publicOnly: review.roles[speaker] == Role.merlin);
    if (view == null) return null;
    if (position == DiscussionPosition.defend && view.provenEvil(target)) {
      return AuditFinding('H5', speaker, where,
          '替可證明是壞人的 ${target + 1}號說話：${s.text}', null);
    }
    if (position == DiscussionPosition.suspect && view.provenGood(target)) {
      return AuditFinding('H5', speaker, where,
          '懷疑可證明是好人的 ${target + 1}號：${s.text}', null);
    }
    return null;
  }

  /// Percival's two (Merlin and Morgana) both on [team].
  bool _bothCandidates(int seat, List<int> team) {
    final seen = visibleSeats(review.roles, seat);
    return seen.length == 2 && seen.every(team.contains);
  }

  static String _seats(List<int> seats) =>
      seats.map((s) => '${s + 1}號').join('、');
}

/// Where in a game: quest and proposal (null: the quest's cards, or the end).
class AuditPlace {
  const AuditPlace(this.quest, this.attempt);
  final int? quest, attempt;
  @override
  String toString() => quest == null
      ? '結局'
      : attempt == null
          ? '第$quest次任務'
          : '第$quest次遠征 提案$attempt';
}

class AuditFinding {
  const AuditFinding(this.rule, this.seat, this.where, this.what, this.reason);

  /// H1…H7 (provable) or S1, S2 (likely).
  final String rule;
  final int seat;
  final AuditPlace where;
  final String what;

  /// The bot's own reason for the vote, where it gave one.
  final String? reason;
  bool get proven => rule.startsWith('H');
}

/// Every way the evil seats could have been dealt that fits what one player
/// knows for certain before a quest's proposals, as the sides stand then.
/// With the Lancelots, a deal also says which evil seat is the evil
/// Lancelot and which good seat the good one: sides switch between them.
class DealView {
  DealView._(this.deals, this.n);
  final List<int> deals; // bit masks of the seats evil now
  final int n;

  /// What [seat] knows before the proposals of [quest] (1-based): its own
  /// card, what its role showed it (unless [publicOnly]), the Fail cards of
  /// earlier quests (sword flips aside; its own Fail taken out) and its own
  /// Lady checks. Null when nothing fits (the facts contradict).
  static DealView? of(GameReview r, int seat, int quest,
      {bool publicOnly = false}) {
    final roles = r.roles, n = roles.length;
    final evils = roles.where((x) => x.isEvil).length;
    final lancelots = r.expansions.lancelot > 0;
    bool switchedIn(int q) =>
        lancelots && q >= 1 && q <= r.switchedDuring.length
            ? r.switchedDuring[q - 1]
            : false;
    final role = roles[seat];
    // what the deal must hold, about the sides as dealt
    final dealt = <int, bool>{seat: role.isEvil};
    int? evilOne = role == Role.lancelotEvil ? seat : null;
    int? goodOne = role == Role.lancelotGood ? seat : null;
    // seats known not to be a Lancelot
    final plain = <int>{if (!role.isLancelot) seat};
    List<int>? pair;
    if (!publicOnly) {
      final seen = visibleSeats(roles, seat);
      if (role == Role.merlin ||
          (role.isEvil && role != Role.oberon && role != Role.lancelotEvil)) {
        for (final v in seen) {
          dealt[v] = true;
        }
        evilOne ??= knownLancelot(roles, seat);
        if (role.isEvil && evilOne != null) {
          // the allies he sees are no Lancelot, but for the one he knows
          plain.addAll(seen.where((v) => v != evilOne));
        }
      } else if (role == Role.percival) {
        plain.addAll(seen);
        if (seen.length == 1) {
          dealt[seen.single] = false;
        } else if (seen.length == 2) {
          pair = seen;
        }
      }
    }
    // (seat, quest whose sides it shows, evil then)
    final sides = [
      for (final c in r.ladyChecks)
        if (c.holder == seat && c.quest < quest)
          (c.target, c.quest, r.evilIn(c.target, c.quest))
    ];
    // (other members, Fails they played, sides switched)
    final quests = <(List<int>, int, bool)>[];
    for (final done in r.quests) {
      final result = done.result;
      if (done.number >= quest || result == null) continue;
      if (result.excaliburTarget != null) continue;
      var fails = result.fails;
      if (done.cards[seat] == false) fails--;
      quests.add(([
        for (final m in result.team)
          if (m != seat) m
      ], fails, switchedIn(done.number)));
    }
    final now = switchedIn(quest);
    final deals = <int>[];
    void judge(int mask, int evilLancelot, int goodLancelot) {
      int sideMask(bool switched) => !switched || evilLancelot < 0
          ? mask
          : (mask & ~(1 << evilLancelot)) | (1 << goodLancelot);
      for (final (target, q, evil) in sides) {
        if ((sideMask(switchedIn(q)) >> target & 1 == 1) != evil) return;
      }
      for (final (team, fails, switched) in quests) {
        final evilThen = sideMask(switched);
        if (team.where((s) => evilThen >> s & 1 == 1).length < fails) return;
        // variant 2: a Lancelot on the evil side can only play Fail
        if (r.expansions.lancelot == 2 && evilLancelot >= 0) {
          final forced = switched ? goodLancelot : evilLancelot;
          if (team.contains(forced) && fails < 1) return;
        }
      }
      deals.add(sideMask(now));
    }

    void walk(int from, int mask, int count) {
      if (count == evils) {
        for (final e in dealt.entries) {
          if ((mask >> e.key & 1 == 1) != e.value) return;
        }
        if (pair != null && pair.where((s) => mask >> s & 1 == 1).length != 1) {
          return;
        }
        if (!lancelots) {
          judge(mask, -1, -1);
          return;
        }
        for (var e = 0; e < n; e++) {
          if (mask >> e & 1 == 0 || plain.contains(e)) continue;
          if (evilOne != null && e != evilOne) continue;
          for (var g = 0; g < n; g++) {
            if (mask >> g & 1 == 1 || plain.contains(g)) continue;
            if (goodOne != null && g != goodOne) continue;
            judge(mask, e, g);
          }
        }
        return;
      }
      for (var s = from; s <= n - (evils - count); s++) {
        walk(s + 1, mask | 1 << s, count + 1);
      }
    }

    walk(0, 0, 0);
    return deals.isEmpty ? null : DealView._(deals, n);
  }

  int get count => deals.length;
  bool provenEvil(int s) => deals.every((d) => d >> s & 1 == 1);
  bool provenGood(int s) => deals.every((d) => d >> s & 1 == 0);

  /// Share of the deals in which [s] is evil.
  double evilShare(int s) =>
      deals.where((d) => d >> s & 1 == 1).length / deals.length;

  /// The cleanest any team of [size] could be, by [chanceAtLeast]: teams
  /// with [seat] on them, as the ones it would put up itself.
  double bestChance(int size, int k, int seat) {
    var best = 1.0;
    final team = <int>[seat];
    void walk(int from) {
      if (team.length == size) {
        final c = chanceAtLeast(team, k, without: seat);
        if (c < best) best = c;
        return;
      }
      for (var s = from; s < n; s++) {
        if (s == seat) continue;
        team.add(s);
        walk(s + 1);
        team.removeLast();
      }
    }

    walk(0);
    return best;
  }

  /// Share of the deals with at least [k] evil players on [team] (leaving
  /// out [without], whose own card the player decides itself).
  double chanceAtLeast(List<int> team, int k, {int? without}) {
    final members = [
      for (final s in team)
        if (s != without) s
    ];
    return deals
            .where((d) => members.where((s) => d >> s & 1 == 1).length >= k)
            .length /
        deals.length;
  }
}
