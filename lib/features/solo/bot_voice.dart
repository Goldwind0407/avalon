import 'dart:math';
import '../game/discussion_model.dart';
import '../game/game_model.dart';
import 'bot_difficulty.dart';
import 'bot_observation.dart';
import 'bot_style.dart';

/// Plain-spoken lines built from the public record, so bots name names and
/// give reasons the way people at a table do. Everything said is grounded in
/// what every player saw (quests, votes, statements); private knowledge only
/// decides whom a bot would rather point at, never what it says it saw.
class BotVoice {
  BotVoice(this.random, this.style, this.difficulty);
  final Random random;
  final BotStyle style;
  final BotDifficulty difficulty;

  String _who(BotObservation o, int seat) => playerLabel(seat, o.names[seat]);
  T _pick<T>(List<T> options) => options[random.nextInt(options.length)];

  /// Quests (1-based) that failed with [seat] on the team.
  List<int> _failedWith(BotObservation o, int seat) => [
        for (var q = 0; q < o.history.length; q++)
          if (o.history[q].team.contains(seat) &&
              o.history[q].fails > 0 &&
              o.history[q].excaliburTarget == null)
            q + 1
      ];

  /// Quests that failed after [seat] approved the team from outside it,
  /// when the vote was contested (agreeing with everyone says nothing).
  List<int> _backedFailures(BotObservation o, int seat) => [
        for (var q = 0; q < o.history.length; q++)
          if (o.history[q].fails > 0 && !o.history[q].team.contains(seat))
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
    if (failed.isNotEmpty) {
      parts.add(_pick([
        '${_quests(failed)}失敗的隊伍上都有$who',
        '${_quests(failed)}任務失敗時$who就在隊上',
      ]));
    }
    if (backed.isNotEmpty) {
      final subject = parts.isEmpty ? who : '他';
      parts.add(_pick([
        '${_quests(backed)}那支失敗的隊伍$subject不在隊上卻投了贊成',
        '$subject不在隊上還支持了${_quests(backed)}失敗的那隊',
      ]));
    }
    return parts.isEmpty ? null : parts.join('，而且');
  }

  String _tail(BotObservation o, int seat, bool approve) {
    if (o.team.contains(seat)) {
      return _pick(['這隊有他，我反對。', '所以這隊我不會投贊成。', '這隊我投反對。']);
    }
    return approve ? _pick(['這隊沒有他，我可以接受。', '這次隊伍沒有他，我先支持。']) : '';
  }

  String get _opener => switch (style) {
        BotStyle.impulsive => _pick(['我直說，', '說真的，', '我不繞圈子，']),
        BotStyle.aggressive => _pick(['我把話說清楚，', '別再拖了，', '我直說，']),
        BotStyle.cautious => _pick(['我想提醒一下，', '先說我的疑慮，', '保守一點來看，']),
        BotStyle.logical => _pick(['照紀錄來看，', '把紀錄攤開來看，', '從數字上看，']),
        BotStyle.follower => _pick(['我跟大家的感覺差不多，', '我同意剛才的方向，', '']),
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

  /// A line that names someone, or null when this bot has nothing to say
  /// about anyone. [view] is how suspicious each seat looks from the public
  /// record alone; [allies] are the seats an evil bot protects.
  DiscussionStatement? speak(BotObservation o, bool approve, List<double> view,
      List<double> real, Set<int> allies) {
    if (o.phase != GamePhase.discussion) return null;
    final round = _thisRound(o);
    DiscussionStatement line(String text, int target, DiscussionPosition pos,
            {int? replyTo}) =>
        DiscussionStatement(
            speaker: o.seat,
            quest: o.quest,
            generation: o.generation,
            attempt: o.proposalId.attempt,
            text: text,
            team: o.team,
            supportsTeam: approve,
            switched: o.switched,
            intent:
                pos == DiscussionPosition.suspect ? 'accuse' : 'defendOther',
            target: target,
            position: pos,
            replyTo: replyTo);
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
          said.target == o.seat) {
        continue;
      }
      final t = said.target!;
      final speaker = _who(o, said.speaker);
      final defend = allies.contains(t) ||
          (!o.evil && real[t] <= .2 && _cleanWith(o, t).isNotEmpty);
      if (defend && random.nextDouble() < _boldness) {
        final clean = _cleanWith(o, t);
        final why =
            clean.isNotEmpty ? '${_quests(clean)}他在的隊伍都是乾淨的' : '那幾次隊伍不只他一個人';
        return line(
            _pick([
              '我不太同意$speaker，$why，不能只盯著${_who(o, t)}。',
              '${_who(o, t)}不見得有問題，$why。',
            ]),
            t,
            DiscussionPosition.defend,
            replyTo: index);
      }
      if (canDoubt(t) &&
          (o.evil ? view[t] >= .3 : real[t] >= .45) &&
          random.nextDouble() < _boldness) {
        return line(
            '${_pick(['我同意$speaker，', '$speaker說的有道理，', '我也這麼覺得，'])}'
            '${_reasons(o, t)}。${_tail(o, t, approve)}',
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
    final t = candidates.first;
    final who = _who(o, t);
    final reasons = _reasons(o, t)!;
    return line(
        _pick([
          '$_opener$who很可疑：${_reasons(o, t)!.replaceFirst(who, '他')}。${_tail(o, t, approve)}',
          '$_opener$reasons，我目前最懷疑他。${_tail(o, t, approve)}',
          '$_opener我想請大家注意$who，${_reasons(o, t)!.replaceFirst(who, '他')}。${_tail(o, t, approve)}',
        ]),
        t,
        DiscussionPosition.suspect);
  }

  /// Gives a template line the bot's way of talking now and then: a short
  /// interjection that fits any sentence.
  String flavor(String text) {
    if (text.isEmpty || random.nextDouble() > .35) return text;
    final opener = switch (style) {
      BotStyle.impulsive => _pick(['說真的，', '老實講，']),
      BotStyle.aggressive => _pick(['聽好，', '我說一下，']),
      BotStyle.cautious => _pick(['嗯……', '這個嘛，']),
      BotStyle.logical => _pick(['整理一下，', '先講結論，']),
      BotStyle.follower => _pick(['嗯，', '好，']),
      _ => _pick(['老實說，', '']),
    };
    if (opener.isEmpty || text.startsWith(opener)) return text;
    return '$opener$text';
  }
}
