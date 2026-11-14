part of 'bot_voice.dart';

/// Coming out as Percival, truthfully or not.
///
/// The real Percival does it as a last resort, when one more failed quest
/// loses the game and the record has told his two candidates apart: he
/// names the one he takes for Morgana and keeps the other to himself. It
/// still tells the Assassin that Merlin is someone else.
/// Morgana answers such a claim with her own, or makes one first when the
/// table closes in on her. Merlin, with the game nearly lost, may pose as
/// Percival to point at an evil player he sees. Everyone else can only
/// weigh the claimants by their records.
extension BotVoiceClaims on BotVoice {
  /// The latest Percival claim of every other player this game.
  Map<int, DiscussionStatement> _claims(BotObservation o) => {
        for (final s in o.statements)
          if (s.generation == o.generation &&
              s.claimsPercival &&
              s.quotedFrom == null &&
              s.speaker != o.seat)
            s.speaker: s
      };

  /// [view] is what an uninformed player would think, [real] what this
  /// seat actually thinks.
  DiscussionStatement? claim(BotObservation o, bool approve, List<double> view,
      List<double> real, Set<int> allies) {
    final roles = o.configuredRoles;
    if (o.phase != GamePhase.discussion ||
        o.history.isEmpty ||
        roles == null ||
        !roles.contains(Role.percival) ||
        !roles.contains(Role.morgana)) {
      return null;
    }
    final me = o.seat, claims = _claims(o);
    DiscussionStatement say(String text,
            {int? morgana, bool isClaim = true, int? replyTo}) =>
        DiscussionStatement(
            speaker: me,
            quest: o.quest,
            generation: o.generation,
            attempt: o.proposalId.attempt,
            text: '$text${_stance(approve)}',
            team: o.team,
            supportsTeam: approve,
            switched: o.switched,
            intent: isClaim ? DiscussionStatement.percivalClaim : 'defendSelf',
            topic: isClaim ? 'claim/percival' : 'claim/denied',
            target: morgana,
            position: morgana == null ? null : DiscussionPosition.suspect,
            certainty: DiscussionCertainty.certain,
            replyTo: replyTo);
    int? indexOf(DiscussionStatement s) {
      final i = o.statements.indexOf(s);
      return i < 0 ? null : i;
    }

    // Nobody waves a team through while calling one of its members Morgana.
    bool sayable(int? morgana) =>
        morgana == null || !(approve && o.team.contains(morgana));
    String why(int seat) {
      final failed = _failedWith(o, seat);
      return failed.isNotEmpty
          ? '${_quests(failed)}出失敗牌時他在隊上'
          : '他的投票跟出失敗牌的隊對得上';
    }

    final accusers = [
      for (final c in claims.values)
        if (c.target == me) c
    ];
    final mine = _claimGeneration == o.generation;
    final acting = difficulty.rolePlay.clamp(0.0, 1.2);
    final isPercival =
        o.role == Role.percival && !o.evil && o.visible.length == 2;

    if (isPercival && !mine) {
      final [a, b] = o.visible;
      final morgana = real[a] >= real[b] ? a : b;
      final gap = (real[a] - real[b]).abs();
      for (final rival in claims.values) {
        final r = rival.speaker;
        final inPair = o.visible.contains(r);
        // One of my two, naming the other one: that is how Merlin would
        // help. Leave it standing.
        if (inPair && rival.target == (r == a ? b : a)) return null;
        // One of my two, naming a third player: Morgana lying, or Merlin
        // bluffing. Only speak against the one the record already makes
        // the likelier Morgana.
        if (inPair &&
            rival.target != me &&
            real[r] <= real[r == a ? b : a] + .1) {
          return null;
        }
        final named = inPair ? r : (gap >= .25 ? morgana : null);
        if (!sayable(named)) return null;
        _claimGeneration = o.generation;
        final rest = inPair
            ? '他就是我看到的兩個人之一，搶著跳出來的那個才是莫甘娜。'
            : named != null
                ? '我看到的兩個人裡沒有他說的那位，${_n(named)}才是莫甘娜。'
                : '我看到的兩個人，跟他說的對不上。';
        return say('我才是派西維爾，${_n(r)}在說謊。$rest',
            morgana: named, replyTo: indexOf(rival));
      }
      // Coming out tells the Assassin that Merlin is someone else, so it
      // waits until one more failed quest would lose the game anyway, and
      // until the record leaves little doubt which of the two is Morgana:
      // naming Merlin by mistake hands him to the Assassin.
      final matters = o.team.contains(morgana) || o.leader == morgana;
      if (gap >= .45 &&
          real[morgana] >= .65 &&
          o.failures == 2 &&
          matters &&
          sayable(morgana) &&
          random.nextDouble() <
              BotVoice.percivalClaimChance * max(.5, acting)) {
        _claimGeneration = o.generation;
        return say(
            _pick([
              '我是派西維爾。我看到的兩個人裡，${_n(morgana)}是莫甘娜：${why(morgana)}。另一位是誰我不會說。',
              '我跳身分：我是派西維爾。${_n(morgana)}是我看到的兩人之一，${why(morgana)}，所以他是莫甘娜。另一位我不點名。',
            ]),
            morgana: morgana);
      }
    }

    if (o.role == Role.morgana && o.evil && !mine) {
      // Named as Morgana: say the same of the one who said it.
      for (final c in accusers) {
        // having denied it without claiming, she does not claim later
        if (_answeredClaims
            .contains('${o.generation}/${c.speaker}/${c.quest}')) {
          continue;
        }
        if (!sayable(c.speaker) || random.nextDouble() > .8) continue;
        _claimGeneration = o.generation;
        return say(
            _pick([
              '我才是派西維爾，${_n(c.speaker)}才是莫甘娜。他搶先跳出來，就是怕我先說。',
              '${_n(c.speaker)}說反了。派西維爾是我，我看到的兩個人裡就有他，他才是莫甘娜。',
            ]),
            morgana: c.speaker,
            replyTo: indexOf(c));
      }
      // The table is closing in: claim first, and pin it on someone the
      // record already speaks against.
      final pressure = o.statements
          .where((s) =>
              s.generation == o.generation &&
              s.quest == o.quest &&
              s.speaker != me &&
              s.target == me &&
              s.position == DiscussionPosition.suspect)
          .map((s) => s.speaker)
          .toSet()
          .length;
      if (claims.isEmpty && pressure >= 2 && o.failures >= 1) {
        final marks = [
          for (var s = 0; s < o.count; s++)
            if (s != me && !allies.contains(s) && view[s] >= .35) s
        ]..sort((x, y) => view[y].compareTo(view[x]));
        if (marks.isNotEmpty &&
            sayable(marks.first) &&
            random.nextDouble() < BotVoice.morganaClaimChance * acting) {
          final t = marks.first;
          _claimGeneration = o.generation;
          return say(
              '大家都在看我，那我直說：我是派西維爾。我看到的兩個人裡，${_n(t)}是莫甘娜，${why(t)}。另一位我不說。',
              morgana: t);
        }
      }
    }

    // Merlin, one failed quest from losing, poses as Percival to point at
    // an evil player the table is about to send out. He cannot know that
    // player is Morgana, so it is a gamble.
    if (o.role == Role.merlin && !mine && claims.isEmpty && o.failures == 2) {
      final seen = [
        for (final s in o.team)
          if (s != me && real[s] >= .95 && view[s] >= .4) s
      ]..sort((x, y) => view[y].compareTo(view[x]));
      if (seen.isNotEmpty &&
          sayable(seen.first) &&
          random.nextDouble() < BotVoice.merlinClaimChance * acting) {
        final t = seen.first;
        _claimGeneration = o.generation;
        return say('我是派西維爾。我看到的兩個人裡，${_n(t)}是莫甘娜：${why(t)}。另一位是誰我不會說。',
            morgana: t);
      }
    }

    // Called Morgana by someone: say so plainly, once. A claimant has
    // already said who is lying.
    for (final c in mine ? const <DiscussionStatement>[] : accusers) {
      final key = '${o.generation}/${c.speaker}/${c.quest}';
      if (!_answeredClaims.add(key)) continue;
      // Merlin knows a good claimant has only mixed his two up.
      if (o.role == Role.merlin && real[c.speaker] < .5) {
        return say('${_n(c.speaker)}，你認錯人了，我不是莫甘娜。請把我的出牌和投票再對一次。',
            isClaim: false, replyTo: indexOf(c));
      }
      return say(
          _pick([
            '${_n(c.speaker)}說我是莫甘娜？我不是。派西維爾看到的兩個人裡不會有我，所以說謊的是他。',
            '我不是莫甘娜。${_n(c.speaker)}這樣指我，只代表他不是真的派西維爾。',
          ]),
          isClaim: false,
          replyTo: indexOf(c));
    }
    return null;
  }
}
