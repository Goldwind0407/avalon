part of 'bot_voice.dart';

/// Bringing up earlier games with the human player. Only ever words: a
/// memory never changes a vote or a suspicion, and never says anything about
/// the roles dealt this time.
extension BotVoiceMemory on BotVoice {
  /// Before the first quest there is nothing in this game to talk about, so
  /// this is when a bot may mention the last one. At most once a game, and
  /// not everyone at the table at once.
  DiscussionStatement? recall(BotObservation o, bool approve) {
    final m = memory;
    if (m == null ||
        o.phase != GamePhase.discussion ||
        o.history.isNotEmpty ||
        o.seat == m.humanSeat ||
        _recalledGeneration == o.generation) {
      return null;
    }
    if (_thisRound(o).where((s) => s.intent == 'recall').length >= 2) {
      return null;
    }
    _recalledGeneration = o.generation;
    final entry = m.entries.first;
    if (entry.ago >= 5 || entry.kinds.isEmpty) return null;
    final personal = entry.kinds.where((k) => k.personal).toList();
    // the game just played is worth a word; an older one, or a plain
    // "we won", only now and then
    final chance = (entry.ago == 0 ? .7 : .3) * (personal.isEmpty ? .5 : 1);
    if (random.nextDouble() > chance) return null;
    final kind = personal.isEmpty
        ? entry.kinds.first
        : personal[random.nextInt(personal.length)];
    final line =
        _pick(memoryLines(kind, memoryWhen(entry.ago), _n(m.humanSeat)));
    return DiscussionStatement(
        speaker: o.seat,
        quest: o.quest,
        generation: o.generation,
        attempt: o.proposalId.attempt,
        text: '$line${firstQuest(o, approve).text}',
        team: o.team,
        supportsTeam: approve,
        switched: o.switched,
        intent: 'recall',
        topic: 'recall/${kind.name}',
        target: m.humanSeat);
  }

  /// A word about last time when the human accuses this bot ([accusedBy]) or
  /// this bot accuses the human ([accusing]). Once a game.
  String _aside({int? accusedBy, int? accusing}) {
    final m = memory;
    if (m == null || _asideUsed) return '';
    String? said;
    if (accusedBy == m.humanSeat) {
      if (m.latest(EpisodeKind.accusedByYou, within: 3) case final e?) {
        said = _pick([
          '${memoryWhen(e.ago)}你也說我有問題，結果我是好人。',
          '${memoryWhen(e.ago)}你也是這樣點我，後來證明你錯了。',
        ]);
      } else if (m.latest(EpisodeKind.caughtByYou, within: 3) case final e?) {
        said = _pick([
          '${memoryWhen(e.ago)}被你說中，不代表這次也是。',
          '你${memoryWhen(e.ago)}抓到我一次，不能每次都算在我頭上。',
        ]);
      }
    } else if (accusing == m.humanSeat) {
      if (m.latest(EpisodeKind.fooled, within: 3) case final e?) {
        said = _pick([
          '${memoryWhen(e.ago)}我就是太相信他。',
          '${memoryWhen(e.ago)}被他騙過一次，這次我不會再放過。',
        ]);
      } else if (m.latest(EpisodeKind.wronged, within: 3) case final e?) {
        said = '${memoryWhen(e.ago)}我錯怪過他，所以這次我是對過紀錄才說的。';
      }
    }
    if (said == null) return '';
    _asideUsed = true;
    return said;
  }
}
