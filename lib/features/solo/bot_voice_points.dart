part of 'bot_voice.dart';

/// One thing a bot can say about this proposal or the public record.
class _Point {
  _Point(this.key, this.text,
      {this.intent = 'opinion',
      this.target,
      this.position,
      this.questionTo,
      this.stance = false,
      this.once = false,
      this.brief,
      this.weight = 1,
      this.ownCardQuest,
      this.quests = const []});

  /// What it is about; two speakers with the same key make the same point.
  final String key;
  final String text, intent;
  final int? target, questionTo, ownCardQuest;
  final DiscussionPosition? position;

  /// The text already says which way this bot votes.
  final bool stance;

  /// Worth saying only once in a game.
  final bool once;

  /// A later speaker can say "same as N" and repeat it.
  final String? brief;
  bool get agreeable => brief != null;
  final double weight;
  final List<int> quests;
}

/// Lines that cite what actually happened: who was on which quest, who voted
/// how, who was dropped or left out. Every fact comes from the public record;
/// private knowledge only decides whom a bot leaves out of its remarks.
extension BotVoicePoints on BotVoice {
  String _n(int seat) => '${seat + 1}號';
  String _ns(Iterable<int> seats) => seats.map(_n).join('、');

  bool _hasRecord(BotObservation o, int s) =>
      o.history.any((q) => q.team.contains(s));
  bool _clean(BotObservation o, int s) =>
      _failedWith(o, s).isEmpty && _cleanWith(o, s).isNotEmpty;

  /// Failed quests whose team [s] voted against from outside it.
  List<int> _opposedFailures(BotObservation o, int s) => [
        for (var q = 0; q < o.history.length; q++)
          if (o.history[q].fails > 0 &&
              o.history[q].excaliburTarget == null &&
              !o.history[q].team.contains(s))
            for (final p in o.proposals)
              if (p.quest == q + 1 &&
                  p.approved &&
                  p.attempt < 5 &&
                  !p.votes[s])
                q + 1
      ];

  /// The team this proposal is naturally compared with: the one just voted
  /// down, or the last quest's.
  List<int> _previousTeam(BotObservation o) {
    final earlier = [
      for (final p in o.proposals)
        if (p.quest == o.quest && p.attempt < o.proposalId.attempt) p
    ];
    if (earlier.isNotEmpty) return earlier.last.team;
    return o.history.isEmpty ? const [] : o.history.last.team;
  }

  String _stance(bool approve) => approve
      ? _pick(['這隊我先贊成。', '這次組隊我支持。', '這隊我願意試。', '這票我會投贊成。'])
      : _pick(['這隊我投反對。', '這次我想換個組合。', '目前這份名單我不支持。', '這票我會反對。']);

  /// Why the leader picked these people.
  _Point? _leaderPoint(BotObservation o, Set<int> allies) {
    final me = o.seat;
    final others = [
      for (final s in o.team)
        if (s != me) s
    ];
    if (others.isEmpty || o.history.isEmpty) return null;
    final parts = <String>[];
    final cited = <int>{};
    final cleanBy = <String, List<int>>{};
    for (final s in others) {
      if (_clean(o, s)) {
        cleanBy.putIfAbsent(_quests(_cleanWith(o, s)), () => []).add(s);
        cited.addAll(_cleanWith(o, s));
      }
    }
    cleanBy
        .forEach((quests, seats) => parts.add('${_ns(seats)}$quests出任務沒有失敗牌'));
    for (final s in others) {
      final opposed = _opposedFailures(o, s);
      if (opposed.isNotEmpty && !_clean(o, s) && _failedWith(o, s).isEmpty) {
        parts.add('${_n(s)}當時反對了${_quests(opposed)}那支出失敗牌的隊');
        cited.addAll(opposed);
      }
    }
    final fresh = [
      for (final s in others)
        if (!_hasRecord(o, s) && _opposedFailures(o, s).isEmpty) s
    ];
    if (fresh.isNotEmpty) parts.add('${_ns(fresh)}還沒出過任務，我想看看結果');
    final tainted = [
      for (final s in others)
        if (_failedWith(o, s).isNotEmpty) s
    ];
    if (tainted.length == 1) {
      parts.add('${_ns(tainted)}雖然待過出失敗牌的隊，那隊不只他一個，我想再確認一次');
    } else if (tainted.isNotEmpty) {
      parts.add('${_ns(tainted)}都待過出失敗牌的隊，但不會每個人都有問題，我想再分一次');
    }
    final dropped = [
      for (final s in _previousTeam(o))
        if (!o.team.contains(s) &&
            s != me &&
            !allies.contains(s) &&
            _failedWith(o, s).isNotEmpty)
          s
    ];
    if (dropped.isNotEmpty) {
      final quests = {for (final s in dropped) ..._failedWith(o, s)}.toList()
        ..sort();
      parts.add('${_ns(dropped)}在${_quests(quests)}出失敗牌的隊上，這次先不帶');
      cited.addAll(quests);
    }
    if (parts.isEmpty) return null;
    final head = o.team.contains(me)
        ? _pick(['我帶自己和${_ns(others)}', '這次我和${_ns(others)}去'])
        : _pick(['我選${_ns(others)}', '這次我派${_ns(others)}']);
    return _Point('leader', '$head：${parts.take(3).join('；')}。',
        intent: 'explainTeam', stance: true, weight: 4, quests: cited.toList());
  }

  /// Everything this bot could say right now, best first is decided later.
  List<_Point> _points(BotObservation o, bool approve, Set<int> allies) {
    final me = o.seat, team = o.team;
    bool mine(int s) => s == me || allies.contains(s);
    final others = [
      for (final s in team)
        if (s != me) s
    ];
    final points = <_Point>[];
    if (o.history.isEmpty) return points;
    if (me == o.leader) {
      if (approve) {
        if (_leaderPoint(o, allies) case final point?) points.add(point);
      }
    } else if (approve) {
      final tainted = [
        for (final s in others)
          if (_failedWith(o, s).isNotEmpty) s
      ];
      final dropped = [
        for (final s in _previousTeam(o))
          if (!team.contains(s) && !mine(s) && _failedWith(o, s).isNotEmpty) s
      ];
      if (dropped.isNotEmpty && tainted.isEmpty) {
        final quests = {for (final s in dropped) ..._failedWith(o, s)}.toList()
          ..sort();
        points.add(_Point(
            'dropped/${dropped.join(',')}',
            _pick([
              '這次把${_ns(dropped)}換掉了，${_quests(quests)}出失敗牌時他在隊上；現在這幾位我沒有具體的反對理由，可以過。',
              '${_ns(dropped)}待過${_quests(quests)}出失敗牌的隊，這次沒帶他，我比較放心，這隊我贊成。',
              '少了${_ns(dropped)}我就能接受，${_quests(quests)}那張失敗牌還沒算清楚。這隊我支持。',
            ]),
            intent: 'supportTeam',
            stance: true,
            brief: '換掉${_ns(dropped)}之後我也能接受，贊成。',
            weight: 3,
            quests: quests));
      }
      final recorded = [
        for (final s in others)
          if (_hasRecord(o, s)) s
      ];
      final fresh = [
        for (final s in others)
          if (!_hasRecord(o, s)) s
      ];
      if (tainted.isEmpty && recorded.isNotEmpty) {
        final lists = {for (final s in recorded) _quests(_cleanWith(o, s))};
        final when = lists.length == 1 ? lists.single : '之前';
        final tail = fresh.isEmpty
            ? _pick(['這隊我可以接受。', '我沒有理由擋，贊成。', '這組我願意再給一次。'])
            : _pick([
                '${_ns(fresh)}還沒出過任務，剛好看看，這隊我贊成。',
                '加上還沒出過任務的${_ns(fresh)}也好，回來比較好對，我支持。',
              ]);
        points.add(_Point('clean', '${_ns(recorded)}$when出任務沒有失敗牌，$tail',
            intent: 'supportTeam',
            stance: true,
            brief: _pick(['這幾位的紀錄我也對過，沒有反對的理由，贊成。', '名單上的紀錄都乾淨，我也支持。']),
            weight: 2.2,
            quests: {for (final s in recorded) ..._cleanWith(o, s)}.toList()));
      }
      if (tainted.isNotEmpty && o.rejections < 4) {
        final t = tainted.first;
        points.add(_Point(
            'risk/$t',
            _pick([
              '${_n(t)}待過${_quests(_failedWith(o, t))}出失敗牌的隊，這點我沒忘；但那隊不只他一個，這次我願意再看一次。',
              '我知道${_n(t)}在${_quests(_failedWith(o, t))}出失敗牌的隊上，不過光憑那一次還定不了他，這隊我先過。',
            ]),
            intent: 'supportTeam',
            target: t,
            stance: true,
            weight: 2,
            quests: _failedWith(o, t)));
      }
    } else {
      final tainted = [
        for (final s in others)
          if (!mine(s) && _failedWith(o, s).isNotEmpty) s
      ];
      if (tainted.isNotEmpty) {
        final t = tainted.first;
        final quests = _failedWith(o, t);
        final shared = quests.where((q) => o.history[q - 1].team.contains(me));
        points.add(_Point(
            'member/$t',
            shared.isNotEmpty
                ? _pick([
                    '這隊有${_n(t)}。${_quests(shared.toList())}我跟他一起出任務就出了失敗牌，我不想再跟他一隊。',
                    '${_quests(shared.toList())}我和${_n(t)}同隊，結果有失敗牌，這次名單上又有他，我反對。',
                  ])
                : _pick([
                    '這隊有${_n(t)}，${_quests(quests)}出失敗牌時他在隊上，弄清楚之前我不想再帶他。',
                    '${_n(t)}待過${_quests(quests)}出失敗牌的隊，現在又上隊，我過不去，這票反對。',
                    '我卡在${_n(t)}：${_quests(quests)}那張失敗牌還沒人交代，這隊我不跟。',
                  ]),
            intent: 'opposeTeam',
            target: t,
            position: DiscussionPosition.suspect,
            stance: true,
            brief: _pick(['我也卡在${_n(t)}，這票反對。', '有${_n(t)}在，我一樣不跟。']),
            weight: 3.2,
            quests: quests));
      }
      for (var q = o.history.length - 1; q >= 0; q--) {
        final past = o.history[q];
        if (past.fails == 0 || past.excaliburTarget != null) continue;
        final overlap = [
          for (final s in team)
            if (past.team.contains(s)) s
        ];
        if (overlap.length >= 2 && !overlap.every(mine)) {
          points.add(_Point(
              'overlap/${q + 1}',
              _pick([
                '這隊跟第${q + 1}次出失敗牌的那隊重複了${_ns(overlap)}，我不想原班人馬再試一次。',
                '${_ns(overlap)}第${q + 1}次就一起出過任務，結果有失敗牌，這次又放在一起，我反對。',
              ]),
              intent: 'opposeTeam',
              stance: true,
              brief: '原班人馬再試一次，我也不贊成。',
              weight: 3,
              quests: [q + 1]));
          break;
        }
      }
      final leftOut = [
        for (var s = 0; s < o.count; s++)
          if (!team.contains(s) && _clean(o, s)) s
      ];
      final unproven = [
        for (final s in others)
          if (!_hasRecord(o, s)) s
      ];
      if (leftOut.isNotEmpty && unproven.isNotEmpty) {
        final self = leftOut.contains(me);
        final who = self ? '我' : _ns(leftOut.take(2));
        final quests =
            _quests(_cleanWith(o, self ? me : leftOut.first).toList());
        points.add(_Point(
            self ? 'leftOut/$me' : 'leftOut',
            _pick([
              '$who$quests出任務沒有失敗牌，這次卻沒被帶上，反而帶了還沒出過任務的${_ns(unproven)}，我想不通。',
              '有成功紀錄的$who不帶，改帶沒出過任務的${_ns(unproven)}？這個換法我不接受。',
            ]),
            intent: 'opposeTeam',
            questionTo: o.leader == me ? null : o.leader,
            stance: true,
            brief: self ? null : '這個換法我也看不懂，反對。',
            weight: 2.6,
            quests: _cleanWith(o, self ? me : leftOut.first)));
      }
      if (!team.contains(me) && tainted.isEmpty) {
        points.add(_Point(
            'outside',
            _pick([
              '我不在這隊上，裡面的人我一個都沒辦法保證，想換一組。',
              '這隊沒有我，我只能確定自己，所以這票我投反對。',
              '名單上沒有我能確定的人，我寧可再組一次。',
            ]),
            intent: 'opposeTeam',
            stance: true,
            weight: 1));
      }
    }

    // Past votes that turned out right or wrong, the speaker's own first.
    for (var q = 0; q < o.history.length; q++) {
      final past = o.history[q];
      final proposal =
          o.proposals.where((p) => p.quest == q + 1 && p.approved).lastOrNull;
      if (proposal == null ||
          proposal.attempt >= 5 ||
          past.fails == 0 ||
          past.excaliburTarget != null ||
          past.team.contains(me)) {
        continue;
      }
      if (!proposal.votes[me]) {
        points.add(_Point(
            'vindicated/${q + 1}',
            _pick([
              '第${q + 1}次那隊我投了反對，結果真的出了失敗牌。',
              '我當時就不贊成第${q + 1}次那隊，後來果然有失敗牌。',
            ]),
            intent: 'explainVote',
            once: true,
            weight: 2.4,
            quests: [q + 1]));
      } else if (proposal.votes.contains(false)) {
        points.add(_Point(
            'mistaken/${q + 1}',
            _pick([
              '第${q + 1}次那隊我投了贊成，結果有失敗牌，那一票我看走眼了。',
              '先認個錯：第${q + 1}次我讓那隊過了，後來出了失敗牌，我得重新看那幾個人。',
            ]),
            intent: 'explainVote',
            once: true,
            weight: 2.4,
            quests: [q + 1]));
      }
    }
    // The last quest came back clean although a few voted against it.
    final last = o.history.length;
    final lastProposal =
        o.proposals.where((p) => p.quest == last && p.approved).lastOrNull;
    if (lastProposal != null &&
        lastProposal.attempt < 5 &&
        o.history.last.fails == 0 &&
        lastProposal.votes[me]) {
      final against = [
        for (var s = 0; s < o.count; s++)
          if (!lastProposal.votes[s]) s
      ];
      if (against.isNotEmpty && against.length <= 2 && !against.any(mine)) {
        points.add(_Point(
            'doubted/$last',
            _pick([
              '第$last次那隊成功了，當時只有${_ns(against)}投反對。${_n(against.first)}，你那時在擔心什麼？',
              '回頭看第$last次：隊伍沒問題，${_ns(against)}卻投了反對。${_n(against.first)}，可以說說當時的想法嗎？',
            ]),
            intent: 'challengeVote',
            target: against.first,
            questionTo: against.first,
            once: true,
            weight: 2,
            quests: [last]));
      }
    }
    // Two players who have never split on a contested vote.
    final contested = [
      for (final p in o.proposals)
        if (p.attempt < 5 && p.votes.contains(true) && p.votes.contains(false))
          p
    ];
    if (contested.length >= 3) {
      pairs:
      for (var a = 0; a < o.count; a++) {
        for (var b = a + 1; b < o.count; b++) {
          if (mine(a) || mine(b)) continue;
          final together = contested.every((p) => p.votes[a] == p.votes[b]);
          final minority = contested.any((p) => p.votes[a] != p.approved);
          if (together && minority) {
            points.add(_Point(
                'pair/$a/$b',
                _pick([
                  '${_n(a)}和${_n(b)}到現在${contested.length}次有分歧的投票全都投得一樣，我會把這兩位放在一起看。',
                  '我對了一下票：${contested.length}次有人投反對的提案，${_n(a)}跟${_n(b)}沒有一次分開過。',
                ]),
                intent: 'challengeVote',
                target: a,
                once: true,
                weight: 2.1));
            break pairs;
          }
        }
      }
    }
    // A failed two-person quest leaves little room.
    if (o.expansions.lancelot == 0) {
      for (var q = 0; q < o.history.length; q++) {
        final past = o.history[q];
        if (past.team.length != 2 ||
            past.fails != 1 ||
            past.excaliburTarget != null) {
          continue;
        }
        if (past.team.contains(me)) {
          final partner = past.team.firstWhere((s) => s != me);
          if (allies.contains(partner)) continue;
          points.add(_Point(
              'duo/${q + 1}',
              _pick([
                '第${q + 1}次只有我和${_n(partner)}出任務，失敗牌不是我出的，那就只能是他。',
                '第${q + 1}次就我跟${_n(partner)}兩個人，我出的是成功，剩下那張是誰的很清楚。',
              ]),
              intent: 'accuse',
              target: partner,
              position: DiscussionPosition.suspect,
              once: true,
              weight: 4,
              ownCardQuest: q + 1,
              quests: [q + 1]));
        } else if (!past.team.any(mine)) {
          points.add(_Point(
              'duoSeen/${q + 1}',
              _pick([
                '第${q + 1}次只有${_ns(past.team)}兩個人出任務就有失敗牌，壞人至少有一個在裡面。',
                '${_ns(past.team)}兩個人的第${q + 1}次出了失敗牌，這兩位我不會同時放進隊裡。',
              ]),
              intent: 'quoteQuest',
              once: true,
              weight: 2.2,
              quests: [q + 1]));
        }
      }
    }
    return points;
  }

  /// A remark grounded in the record, or null when nothing specific is left
  /// to say (the caller then falls back on the line catalogue).
  DiscussionStatement? evidence(
      BotObservation o, bool approve, Set<int> allies) {
    if (o.phase != GamePhase.discussion || o.history.isEmpty) return null;
    if (_topicsGeneration != o.generation) {
      _topicsGeneration = o.generation;
      _topics.clear();
    }
    // a one-off remark is made once a game; anything else twice a quest
    String tally(_Point p) => p.once ? p.key : '${o.quest}/${p.key}';
    final round = [
      for (final (index, s) in o.statements.indexed)
        if (s.quest == o.quest &&
            s.attempt == o.proposalId.attempt &&
            s.speaker != o.seat &&
            s.topic != null)
          (index, s)
    ];
    final scored = <(_Point, double, int?)>[];
    for (final point in _points(o, approve, allies)) {
      if ((_topics[tally(point)] ?? 0) >= (point.once ? 1 : 2)) continue;
      final same = [
        for (final (index, s) in round)
          if (s.topic == point.key) index
      ];
      var weight = point.weight + random.nextDouble() * 1.6;
      int? agreeWith;
      if (same.isNotEmpty) {
        if (!point.agreeable || same.length > 1) continue;
        agreeWith = same.single;
        weight -= style == BotStyle.follower ? 0 : 1.2;
      }
      final record = const ['explainVote', 'challengeVote', 'quoteQuest']
          .contains(point.intent);
      if (style == BotStyle.logical && record) weight += .8;
      // never call someone out and wave the team they are on through
      if (approve &&
          point.position == DiscussionPosition.suspect &&
          o.team.contains(point.target)) {
        continue;
      }
      if (style == BotStyle.cautious && point.key.startsWith('outside')) {
        weight += .6;
      }
      if (style == BotStyle.aggressive && point.position != null) weight += .6;
      scored.add((point, weight, agreeWith));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final (point, _, agreeWith) = scored.first;
    _topics.update(tally(point), (n) => n + 1, ifAbsent: () => 1);
    final agree = agreeWith == null
        ? null
        : _pick([
            '我跟${_n(o.statements[agreeWith].speaker)}想的一樣。',
            '${_n(o.statements[agreeWith].speaker)}說的我同意。',
            '${_n(o.statements[agreeWith].speaker)}講的就是我想說的。',
          ]);
    return DiscussionStatement(
        speaker: o.seat,
        quest: o.quest,
        generation: o.generation,
        attempt: o.proposalId.attempt,
        text: agree != null
            ? '$agree${point.brief}'
            : '${point.text}${point.stance ? '' : _stance(approve)}',
        team: o.team,
        supportsTeam: approve,
        switched: o.switched,
        intent: point.intent,
        topic: point.key,
        target: point.target,
        position: point.position,
        questionTo: point.questionTo,
        replyTo: agreeWith,
        certainty: point.ownCardQuest == null
            ? DiscussionCertainty.tentative
            : DiscussionCertainty.certain,
        claimedOriginalSuccess: point.ownCardQuest == null ? null : true,
        originalCardQuest: point.ownCardQuest,
        evidenceIds: [
          for (final q in point.quests)
            BotEvidenceId(o.generation, BotEvidenceKind.quest, 'q$q').id,
          if (agreeWith != null)
            BotEvidenceId(
                    o.generation, BotEvidenceKind.statement, 's$agreeWith')
                .id,
        ]);
  }

  /// What to answer when asked directly: the most specific thing this bot
  /// can say about the question, or about the team on the table.
  /// The flag says whether the text already states the vote.
  (String, bool)? answer(BotObservation o, bool approve, Set<int> allies,
      DiscussionStatement question) {
    final me = o.seat;
    // "Why did you vote against the quest that went fine?"
    if (question.topic?.startsWith('doubted/') ?? false) {
      final q = int.parse(question.topic!.split('/')[1]);
      final team = o.history[q - 1].team;
      if (team.contains(me)) return null;
      return (
        _pick([
          '第$q次我不在隊上，${_ns(team)}我當時一個都沒辦法確定，所以沒跟。結果是好的，這幾位我會多信一點。',
          '那時候我對${_ns(team)}還沒有把握，不想第一時間就放行。現在看是我多慮了。',
        ]),
        false
      );
    }
    final points = _points(o, approve, allies)
        .where((p) => p.stance && p.questionTo == null)
        .toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));
    final best = points.firstOrNull;
    return best == null ? null : (best.text, true);
  }
}
