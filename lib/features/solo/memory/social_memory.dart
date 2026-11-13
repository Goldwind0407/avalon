import 'match_archive.dart';

/// One past game as a computer player remembers it.
class MemoryEntry {
  const MemoryEntry(this.ago, this.kinds);

  /// How many finished games back: 0 is the game just before this one.
  final int ago;
  final List<EpisodeKind> kinds;
}

/// What one computer player remembers about the human player. Built only
/// from finished games, whose roles were revealed to everyone at the end, so
/// nothing here says anything about the game being played now. It shapes
/// what a bot says, never how it votes or whom it suspects.
class BotMemory {
  BotMemory(this.humanSeat, List<MemoryEntry> entries)
      : entries = List.unmodifiable(entries);

  /// Where the human sits in the current game.
  final int humanSeat;

  /// Newest first; only games this bot played with the human.
  final List<MemoryEntry> entries;
  int get gamesTogether => entries.length;

  /// Null when [personaId] has never played with the human.
  static BotMemory? of(
      String personaId, List<MatchSummary> summaries, int humanSeat) {
    final entries = [
      for (final (ago, s) in summaries.indexed)
        if (s.episodes[personaId] case final kinds?) MemoryEntry(ago, kinds)
    ];
    return entries.isEmpty ? null : BotMemory(humanSeat, entries);
  }

  /// The most recent game in which [kind] happened, within [within] games.
  MemoryEntry? latest(EpisodeKind kind, {int within = 5}) {
    for (final e in entries) {
      if (e.ago < within && e.kinds.contains(kind)) return e;
    }
    return null;
  }
}

String memoryWhen(int ago) => ago == 0 ? '上一局' : '前幾局';

/// What a bot says when it brings a past game up. [who] is how the human is
/// called at the table. Each kind has a few ways of being said.
List<String> memoryLines(EpisodeKind kind, String when, String who) =>
    switch (kind) {
      EpisodeKind.fooled => [
          '$who，$when你是壞人，我還讓你出了任務。這局我會多看你兩眼。',
          '$when被$who騙得很慘，這局我不會那麼好說話。',
          '$when我太相信$who了，結果任務就壞在他手上。這次我先看紀錄。',
        ],
      EpisodeKind.sawThrough => [
          '$when我就說$who有問題，後來證明沒看錯。這局我一樣盯著紀錄。',
          '$who，$when你的壞人牌被我看穿了，這局別想用同一套。',
        ],
      EpisodeKind.wronged => [
          '$who，$when我一直懷疑你，結果你是好人，是我看錯了。這局我會先聽你說。',
          '$when我錯怪了$who，這次我不會那麼快下結論。',
        ],
      EpisodeKind.framed => [
          '$when我把大家的懷疑都引到$who身上，不好意思啦。這局各憑本事。',
          '$who，$when讓你背了黑鍋。這局我是不是壞人，你自己判斷。',
        ],
      EpisodeKind.accusedByYou => [
          '$who，$when你一直說我是壞人，結果我是好人。這局先別急著點我。',
          '$when被$who冤枉了一整局，這次請你拿紀錄說話。',
        ],
      EpisodeKind.caughtByYou => [
          '$when被$who抓到了，算你厲害。這局換我盯著你。',
          '$who，$when你一眼就看出我有問題，這局我可沒那麼好抓。',
        ],
      EpisodeKind.trustedByYou => [
          '$when$who還替我說話，結果我是壞人。這局你可以再信我一次，哈。',
          '$who，$when謝謝你幫我擔保，雖然我那時候是壞人。',
        ],
      EpisodeKind.usedYou => [
          '$when$who讓我出了任務，結果我是壞人，謝謝你的信任。',
          '$who，$when你讓我出了任務，結果任務失敗了，因為我是壞人。這局別太快相信人。',
        ],
      EpisodeKind.stabbedYou => [
          '$when我一刀就找到$who這個梅林。這局我也會留意誰知道得太多。',
          '$who，$when你當梅林藏得不夠深，被我刺中了。',
        ],
      EpisodeKind.mistookYou => [
          '$when我把$who當成梅林，結果刺錯了，你演得不錯。',
          '$who，$when你騙走了我那一刀，這局我會更小心。',
        ],
      EpisodeKind.stabbedByYou => [
          '$when$who一刀刺中我，我到現在還在想是哪句話露了餡。',
          '$who，$when你認出我是梅林，這局我會少說兩句。',
        ],
      EpisodeKind.dodgedYou => [
          '$when$who以為我是梅林，結果刺錯人了。',
          '$who，$when你那一刀刺到我身上，可惜我不是梅林。',
        ],
      EpisodeKind.wonTogether => [
          '$when跟$who同一邊贏了，希望這局還能合作。',
          '$who，$when我們配合得不錯。',
        ],
      EpisodeKind.lostTogether => [
          '$when我跟$who同一邊卻輸了，這局想討回來。',
          '$who，$when我們那邊沒贏，這次再來。',
        ],
      EpisodeKind.beatYou => [
          '$who，$when是我們那邊贏，這局你要小心。',
          '$who，$when是我這邊贏，這局再比一次。',
        ],
      EpisodeKind.lostToYou => [
          '$when輸給$who那邊，我可沒忘。',
          '$who，$when讓你贏了，這局沒那麼容易。',
        ],
    };

/// For the list of computer players: one line about the shared history.
String memorySummary(BotMemory? memory) {
  if (memory == null) return '還沒跟你玩過';
  var allies = 0, won = 0;
  for (final e in memory.entries) {
    final together = e.kinds.contains(EpisodeKind.wonTogether) ||
        e.kinds.contains(EpisodeKind.lostTogether);
    if (together) allies++;
    // from the player's side: won with this bot, or beat it
    if (e.kinds.contains(EpisodeKind.wonTogether) ||
        e.kinds.contains(EpisodeKind.lostToYou)) {
      won++;
    }
  }
  return '一起玩過 ${memory.gamesTogether} 局・同陣營 $allies 局・你贏 $won 局';
}
