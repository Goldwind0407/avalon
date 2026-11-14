import 'dart:math';
import '../game/discussion_model.dart';
import '../game/game_model.dart';
import 'bot_difficulty.dart';
import 'bot_observation.dart';
import 'bot_style.dart';
import 'bot_strategy_plan.dart';
import 'dialogue/bot_contract.dart';
import 'memory/match_archive.dart';
import 'memory/social_memory.dart';

part 'bot_voice_claims.dart';
part 'bot_voice_memory.dart';
part 'bot_voice_points.dart';

/// Plain-spoken lines built from the public record, so bots name names and
/// give reasons the way people at a table do. Everything said is grounded in
/// what every player saw (quests, votes, statements); private knowledge only
/// decides whom a bot would rather point at, never what it says it saw.
class BotVoice {
  BotVoice(this.random, this.style, this.difficulty);
  final Random random;
  final BotStyle style;
  final BotDifficulty difficulty;
  BotStrategyPlan? plan;
  final _arguments = <String>{};
  final _recentLines = <String>[];
  final _topics = <String, int>{};
  int? _topicsGeneration;

  /// What this bot remembers of earlier games with the human, if anything.
  BotMemory? memory;
  int? _recalledGeneration;
  bool _asideUsed = false;

  /// A role is claimed once a game, and a claim against oneself answered
  /// once.
  int? _claimGeneration;

  /// How readily a role is claimed when the moment for it has come: by the
  /// real Percival, by Morgana under pressure, by Merlin as a last resort.
  /// Merlin's must stay the rarest: the bluff only works while the Assassin
  /// takes a claimant for Percival. Zero switches that kind of claim off.
  static double percivalClaimChance = .55;
  static double morganaClaimChance = .3;
  static double merlinClaimChance = .1;
  final _answeredClaims = <String>{};

  /// People at a table say the seat number, not the full name plate.
  String _who(BotObservation o, int seat) => '${seat + 1}號';
  String _pick(List<String> options) {
    final fresh = options.where((s) => !_recentLines.contains(s)).toList();
    final choices = fresh.isEmpty ? options : fresh;
    final line = choices[random.nextInt(choices.length)];
    _recentLines.add(line);
    if (_recentLines.length > 16) _recentLines.removeAt(0);
    return line;
  }

  /// Quests (1-based) that failed with [seat] on the team.
  List<int> _failedWith(BotObservation o, int seat) => [
        for (var q = 0; q < o.history.length; q++)
          if (o.history[q].team.contains(seat) &&
              o.history[q].fails > 0 &&
              o.history[q].excaliburTarget == null &&
              (o.expansions.lancelot == 0 ||
                  o.loyalty.take(q + 1).where((v) => v == true).length.isOdd ==
                      o.switched))
            q + 1
      ];

  /// Quests that failed after [seat] approved the team from outside it,
  /// when the vote was contested (agreeing with everyone says nothing).
  List<int> _backedFailures(BotObservation o, int seat) => [
        for (var q = 0; q < o.history.length; q++)
          if (o.history[q].fails > 0 &&
              o.history[q].excaliburTarget == null &&
              o.expansions.lancelot == 0 &&
              !o.history[q].team.contains(seat))
            for (final p in o.proposals)
              if (p.quest == q + 1 &&
                  p.approved &&
                  p.attempt < 5 &&
                  p.votes[seat] &&
                  p.votes.contains(false))
                q + 1
      ];

  /// Quests that came back clean with [seat] on the team.
  List<int> _cleanWith(BotObservation o, int seat) => [
        for (var q = 0; q < o.history.length; q++)
          if (o.history[q].team.contains(seat) && o.history[q].fails == 0) q + 1
      ];

  String _quests(List<int> qs) => '第${qs.toSet().join('、')}次';

  /// Why [seat] looks suspicious, naming them in the first reason.
  String? _reasons(BotObservation o, int seat) {
    final failed = _failedWith(o, seat), backed = _backedFailures(o, seat);
    final who = _who(o, seat);
    final parts = <String>[];
    final shared = [
      for (final q in failed)
        if (o.history[q - 1].team.contains(o.seat)) q
    ];
    if (failed.isNotEmpty && shared.length == failed.length) {
      // the speaker sat on the same team: say so instead of pointing from afar
      parts.add(_pick([
        '${_quests(failed)}我和$who同隊就出了失敗牌，我出的是成功',
        '${_quests(failed)}出失敗牌時隊上有我也有$who，我知道自己那張是成功',
        '$who跟我一起出的${_quests(failed)}遠征有失敗牌，那張不是我的',
      ]));
    } else if (failed.isNotEmpty) {
      parts.add(_pick([
        if (failed.toSet().length > 1) ...[
          '${_quests(failed)}有失敗牌的隊伍上都有$who',
          '$who參與的${_quests(failed)}遠征都有失敗牌',
        ] else ...[
          '${_quests(failed)}那支有失敗牌的隊伍裡有$who',
          '$who參與的${_quests(failed)}遠征出了失敗牌',
        ],
        '${_quests(failed)}遠征出現失敗牌時$who就在隊上',
        '我想追${_quests(failed)}的失敗牌，$who那時也在隊上',
      ]));
    }
    if (backed.isNotEmpty) {
      final subject = parts.isEmpty ? who : '他';
      parts.add(_pick([
        '${_quests(backed)}那支出過失敗牌的隊伍$subject不在隊上卻投了贊成',
        '$subject不在隊上還支持了${_quests(backed)}出過失敗牌的那隊',
        '$subject當時沒在隊上，但${_quests(backed)}出過失敗牌的隊伍他投了贊成',
        '回頭看${_quests(backed)}，$subject在隊外支持的組合後來有失敗牌',
      ]));
    }
    return parts.isEmpty ? null : parts.join('，而且');
  }

  /// What an accused bot answers from the record: who else was there.
  String? _defence(BotObservation o, Set<int> allies) {
    final me = o.seat;
    final failed = _failedWith(o, me), backed = _backedFailures(o, me);
    if (failed.isNotEmpty) {
      final q = failed.last;
      final mates = [
        for (final s in o.history[q - 1].team)
          if (s != me) s
      ];
      final others = mates.where((s) => !allies.contains(s)).toList();
      final named = (others.isEmpty ? mates : others).map((s) => _who(o, s));
      if (mates.length == 1) {
        return _pick([
          '第$q次就我和${named.first}兩個人，我出的是成功，所以問題在他，不在我。',
          '那次只有兩個人，我知道自己出的是成功。該解釋的是${named.first}。',
        ]);
      }
      return _pick([
        '第$q次隊上還有${named.join('、')}，我出的是成功，失敗牌不能只算在我頭上。',
        '我在第$q次的隊上沒錯，但${named.join('、')}也在。我那張是成功，請把他們一起看。',
        '第$q次不是我一個人出任務，${named.join('、')}${named.length > 1 ? '都' : '也'}在。只盯著我，剛好放過真正出失敗牌的人。',
      ]);
    }
    if (backed.isNotEmpty) {
      final q = backed.last;
      final proposal =
          o.proposals.where((p) => p.quest == q && p.approved).lastOrNull;
      final also = [
        if (proposal != null)
          for (var s = 0; s < o.count; s++)
            if (s != me &&
                proposal.votes[s] &&
                !proposal.team.contains(s) &&
                !allies.contains(s))
              s
      ];
      return also.isEmpty
          ? '第$q次我是投了贊成，那時候沒有人知道會出失敗牌。一張票不能說明我是誰。'
          : _pick([
              '第$q次投贊成的不只我，${also.take(3).map((s) => _who(o, s)).join('、')}也贊成了，那時候沒有人知道會出失敗牌。',
              '那一票我認，但${also.take(3).map((s) => _who(o, s)).join('、')}當時也在隊外投了贊成，要算就一起算。',
            ]);
    }
    return null;
  }

  String get _opener => switch (style) {
        BotStyle.impulsive => _pick(['我直說，', '說真的，', '我不繞圈子，']),
        BotStyle.aggressive => _pick(['我把話說清楚，', '別再拖了，', '我直說，']),
        BotStyle.cautious => _pick(['我想提醒一下，', '先說我的疑慮，', '保守一點來看，']),
        BotStyle.logical => _pick(['照紀錄來看，', '把紀錄攤開來看，', '從數字上看，']),
        BotStyle.follower => _pick(['我想確認一下，', '我補一句，', '']),
        _ => _pick(['老實說，', '我想了一下，', '']),
      };

  /// How readily this bot speaks its mind about a person.
  double get _boldness =>
      switch (style) {
        BotStyle.impulsive || BotStyle.aggressive => .8,
        BotStyle.cautious => .4,
        BotStyle.follower => .5,
        _ => .6,
      } *
      (difficulty == BotDifficulty.novice ? .8 : 1);

  /// Statements already made about the current proposal.
  List<DiscussionStatement> _thisRound(BotObservation o) => [
        for (final s in o.statements)
          if (s.quest == o.quest &&
              s.attempt == o.proposalId.attempt &&
              s.generation == o.generation)
            s
      ];

  DiscussionStatement reply(BotObservation o, bool approve, int questionIndex,
      [Set<int> allies = const {}]) {
    final question = o.statements[questionIndex];
    final specific = answer(o, approve, allies, question);
    final name = _who(o, question.speaker);
    final ballot = o.publicLedger.events
        .where((e) =>
            e.id.kind == BotEvidenceKind.ballot &&
            question.evidenceIds.contains(e.id.id))
        .lastOrNull;
    final opening = ballot == null && specific != null
        ? '$name，'
        : ballot == null
            ? _pick([
                '$name，你問我這隊怎麼看，我直接說我的票。',
                '$name，我現在的立場是這樣：',
                '回答$name剛才的問題，我先講這次的選擇。',
                '$name，我還沒有誰百分之百可信的結論，但這隊我有傾向。'
              ])
            : '$name，你問的第${ballot.quest}次遠征、第${ballot.attempt}次提案，'
                '我投的是${ballot.ballots[o.seat] ? '贊成' : '反對'}。'
                '${ballot.attempt == 5 ? '那已經是第五次，不能再否決。' : '那是當時的選擇，不代表我之後每隊都會照投。'}';
    final stance = ballot == null && specific != null
        ? '${specific.$1}${specific.$2 ? '' : _stance(approve)}'
        : approve
            ? _pick([
                '現在這隊我願意試一次，但不替整隊保證。',
                '這次我會贊成，結果出來再看要不要調整。',
                '目前我接受這份名單，這票支持。',
                '這隊我先過，這是組隊票，不是誰的身分證明。'
              ])
            : _pick([
                '現在這隊我不支持，我想換個組合比較。',
                '這份名單我還不放心，這票反對。',
                '這次我想再組一隊，不會投贊成。',
                '目前我不接受這個搭配，先反對。'
              ]);
    return DiscussionStatement(
        speaker: o.seat,
        quest: o.quest,
        generation: o.generation,
        attempt: o.proposalId.attempt,
        text: '$opening$stance',
        target: question.speaker,
        replyTo: questionIndex,
        supportsTeam: approve,
        team: o.team,
        switched: o.switched,
        intent: 'replyQuestion',
        evidenceIds: [
          BotEvidenceId(
                  o.generation, BotEvidenceKind.statement, 's$questionIndex')
              .id,
          if (ballot != null) ballot.id.id,
        ]);
  }

  /// A line that names someone, or null when this bot has nothing to say
  /// about anyone. [view] is how suspicious each seat looks from the public
  /// record alone; [allies] are the seats an evil bot protects.
  DiscussionStatement? speak(BotObservation o, bool approve, List<double> view,
      List<double> real, Set<int> allies) {
    if (o.phase != GamePhase.discussion) return null;
    if (plan?.generation != o.generation || plan?.switched != o.switched) {
      plan =
          BotStrategyPlan(BotGoal.buildTrust, o.seat, o.generation, o.switched);
      _arguments.clear();
    }
    final round = _thisRound(o);
    DiscussionStatement line(String text, int target, DiscussionPosition? pos,
            {int? replyTo}) =>
        DiscussionStatement(
            speaker: o.seat,
            quest: o.quest,
            generation: o.generation,
            attempt: o.proposalId.attempt,
            text: '$text${approve ? _pick([
                    '這隊我先贊成。',
                    '這次組隊我支持。',
                    '這隊我願意試。',
                    '這票我會投贊成。'
                  ]) : _pick([
                    '這隊我投反對。',
                    '這次我想換個組合。',
                    '目前這份名單我不支持。',
                    '這票我會反對。'
                  ])}',
            team: o.team,
            supportsTeam: approve,
            switched: o.switched,
            intent: pos == null
                ? 'defendSelf'
                : pos == DiscussionPosition.suspect
                    ? 'accuse'
                    : 'defendOther',
            target: target,
            position: pos,
            replyTo: replyTo,
            evidenceIds: [
              for (final q in {
                ..._failedWith(o, target),
                ..._backedFailures(o, target)
              })
                BotEvidenceId(o.generation, BotEvidenceKind.quest, 'q$q').id,
              if (replyTo != null)
                BotEvidenceId(
                        o.generation, BotEvidenceKind.statement, 's$replyTo')
                    .id,
            ]);
    bool canDoubt(int s) =>
        s != o.seat &&
        !allies.contains(s) &&
        (!o.team.contains(s) || !approve) &&
        _reasons(o, s) != null;

    // Someone was just accused: back them up or push back.
    for (final (index, said) in o.statements.indexed.toList().reversed) {
      if (!round.contains(said) ||
          said.speaker == o.seat ||
          said.position != DiscussionPosition.suspect ||
          said.target == null ||
          o.statements.any((s) => s.speaker == o.seat && s.replyTo == index)) {
        continue;
      }
      final t = said.target!;
      final speaker = _who(o, said.speaker);
      if (t == o.seat) {
        plan = BotStrategyPlan(BotGoal.defendSelf, t, o.generation, o.switched);
        return line(
            '${_aside(o, accusedBy: said.speaker)}${_defence(o, allies) ?? _pick([
                      '$speaker，我有聽到你的懷疑。你卡在哪一票，還是哪次遠征？',
                      '$speaker，先別急著排掉我。把你覺得矛盾的地方指出來，我們對一下。',
                      '你可以懷疑我，但我想先知道理由。$speaker，你最在意哪件事？',
                      '$speaker，我不會只回一句我是好人。你指出哪裡不對，我們就談那件事。',
                    ])}',
            t,
            null,
            replyTo: index);
      }
      final defend = allies.contains(t) ||
          (!o.evil && real[t] <= .2 && _cleanWith(o, t).isNotEmpty);
      // someone already spoke up for this player this round
      final defenders = round
          .where((s) =>
              s.speaker != o.seat &&
              s.position == DiscussionPosition.defend &&
              s.target == t)
          .length;
      if (defend && defenders < 2 && random.nextDouble() < _boldness) {
        if (defenders == 1) {
          return line(
              _pick([
                '我也覺得${_who(o, t)}還不到要排掉的程度。',
                '${_who(o, t)}這邊我跟前面一樣，先別急著定。',
              ]),
              t,
              DiscussionPosition.defend,
              replyTo: index);
        }
        final clean = _cleanWith(o, t);
        final why = clean.isNotEmpty
            ? '${_who(o, t)}在的${_quests(clean)}遠征沒有失敗牌，雖然不能當成身分保證'
            : _pick([
                '單靠一個懷疑還不能定案',
                '光憑同隊一次說明不了什麼',
                '現在的紀錄還不夠指認誰',
              ]);
        return line(
            _pick([
              '我不太同意$speaker，$why，不能只盯著${_who(o, t)}。',
              '${_who(o, t)}不見得有問題，$why。',
              '對${_who(o, t)}先留點空間吧，$why。',
              '我還不想直接排掉${_who(o, t)}，$why。',
            ]),
            t,
            DiscussionPosition.defend,
            replyTo: index);
      }
      if (canDoubt(t) &&
          (o.evil ? view[t] >= .3 : real[t] >= .45) &&
          random.nextDouble() < _boldness) {
        // the reason has been given; from the second voice on, just join in
        final voices = round
            .where((s) =>
                s.position == DiscussionPosition.suspect && s.target == t)
            .length;
        if (voices >= 4) break;
        return line(
            voices >= 2
                ? _pick([
                    '${_who(o, t)}我也不放心。',
                    '加我一個，我也看${_who(o, t)}。',
                    '同樣的紀錄我也看到了，${_who(o, t)}得解釋。',
                    '我一樣卡在${_who(o, t)}。',
                  ])
                : '${_pick(['我同意$speaker，', '$speaker說的有道理，', '我也這麼覺得，'])}'
                    '${_reasons(o, t)}。',
            t,
            DiscussionPosition.suspect,
            replyTo: index);
      }
      break;
    }

    // Otherwise name the person this bot doubts most, if the record backs it.
    // Good bots go by what they really think; evil bots pick a good player
    // the table already looks at.
    final scores = o.evil ? view : real;
    final candidates = [
      for (var s = 0; s < o.count; s++)
        if (canDoubt(s) && scores[s] >= (o.evil ? .3 : .45)) s
    ]..sort((a, b) => scores[b].compareTo(scores[a]));
    final already = {
      for (final s in round)
        if (s.speaker == o.seat && s.target != null) s.target
    };
    candidates.removeWhere(already.contains);
    if (candidates.isEmpty || random.nextDouble() > _boldness) return null;
    final t =
        candidates.contains(plan?.target) ? plan!.target : candidates.first;
    final argument = '$t/${_failedWith(o, t)}/${_backedFailures(o, t)}';
    if (!_arguments.add(argument)) return null;
    plan = BotStrategyPlan(o.evil ? BotGoal.framePlayer : BotGoal.exposeSuspect,
        t, o.generation, o.switched);
    final who = _who(o, t);
    // others already named this player this round: join in briefly
    final voices = round
        .where((s) =>
            s.speaker != o.seat &&
            s.position == DiscussionPosition.suspect &&
            s.target == t)
        .length;
    if (voices >= 4) return null;
    if (voices >= 1) {
      return line(
          _pick([
            '$who我也不放心。',
            '加我一個，我也看$who。',
            '我一樣卡在$who。',
          ]),
          t,
          DiscussionPosition.suspect);
    }
    final reasons = _reasons(o, t)!;
    return line(
        _pick([
              '$_opener$who很可疑：${_reasons(o, t)!.replaceFirst(who, '他')}。',
              '$_opener$reasons，我目前最懷疑他。',
              '$_opener我想請大家注意$who，${_reasons(o, t)!.replaceFirst(who, '他')}。',
              '$reasons。$who，你怎麼看這幾段紀錄？',
            ]) +
            _aside(o, accusing: t),
        t,
        DiscussionPosition.suspect);
  }

  /// Wording is authored as complete sentences; no random prefix disguise.
  String flavor(String text) => text;

  /// A short word before the first quest, when nobody has anything to go on.
  DiscussionStatement firstQuest(BotObservation o, bool approve) {
    final again = o.proposalId.attempt > 1;
    final lines = approve
        ? [
            if (again) ...[
              '上一隊沒過，這次我沒意見，讓它出發吧。',
              '換了組合也好，這隊我贊成。',
              '再拖下去也沒新資訊，這次就過吧。',
            ],
            '第一輪沒什麼資訊，我沒意見，讓它出發吧。',
            '第一隊我沒意見，贊成。',
            '先跑一次看看結果再說。',
            '我沒特別想法，這隊可以。',
            '資訊還太少，先過吧。',
            '第一輪就不多說了，我投贊成。',
            '沒意見，先讓任務給我們一點線索。',
            '過吧，回來再聊。',
          ]
        : [
            '第一輪沒什麼根據，不過我想再看一個組合。',
            '我沒什麼特別理由，只是想多看一次提案。',
            '這隊我先不投，換個人選看看。',
          ];
    final said = {
      for (final s in _thisRound(o))
        if (s.speaker != o.seat) s.text
    };
    final fresh = lines.where((l) => !said.contains(l)).toList();
    return DiscussionStatement(
        speaker: o.seat,
        quest: o.quest,
        generation: o.generation,
        attempt: o.proposalId.attempt,
        text: _pick(fresh.isEmpty ? lines : fresh),
        team: o.team,
        supportsTeam: approve,
        switched: o.switched,
        intent: approve ? 'supportTeam' : 'opposeTeam');
  }
}
