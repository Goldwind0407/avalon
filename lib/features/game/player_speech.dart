/// What a human can say during their turn to speak against computer
/// players. Each kind maps onto a public statement the bots understand.
enum PlayerSpeechKind {
  support,
  oppose,
  suspect,
  trust,
  ask,
  challengeVote,
  claimGood,

  /// "I am Percival", with [PlayerSpeech.target] the player called Morgana,
  /// if one was named.
  claimPercival,

  /// "The Lady showed me 2 is good": [PlayerSpeech.target] is the player
  /// checked and [PlayerSpeech.claimsEvil] what the speaker says was seen.
  ladyClaim,

  /// Free text the bots could not read anything definite from.
  remark,
}

class PlayerSpeech {
  const PlayerSpeech(this.kind,
      {this.target,
      this.text,
      this.claimsEvil,
      this.supportsTeam,
      this.more = const []});
  final PlayerSpeechKind kind;
  final int? target;

  /// What the player typed, if they typed it.
  final String? text;

  /// For [PlayerSpeechKind.ladyClaim]: the side the speaker says they saw.
  final bool? claimsEvil;

  /// Where the same line also takes a side on the proposed team.
  final bool? supportsTeam;

  /// Further points made in the same line, each about another player:
  /// "2號是好人，所以5號是壞人" is a word for 2 and an accusation of 5.
  final List<PlayerSpeech> more;

  /// This point and the ones after it, in the order they were made.
  List<PlayerSpeech> get points => [this, ...more];

  bool get needsTarget => const [
        PlayerSpeechKind.suspect,
        PlayerSpeechKind.trust,
        PlayerSpeechKind.ask,
        PlayerSpeechKind.challengeVote,
        PlayerSpeechKind.ladyClaim,
      ].contains(kind);

  static final _number = RegExp(r'(\d{1,2})\s*號');
  static final _leadingNumber = RegExp(r'^\s*(\d{1,2})(?!\d)');

  /// Where in [t] other players are named: seat numbers ("3號", or a bare
  /// number opening the line) and nicknames, longest first so 電腦1 does
  /// not match inside 電腦10. The speaker's own seat names nobody.
  static List<(int seat, int start, int end)> _mentions(
      String t, List<String> names, int mySeat) {
    final found = <(int, int, int)>[];
    bool free(int start, int end) =>
        found.every((m) => end <= m.$2 || start >= m.$3);
    for (final m in [
      ..._number.allMatches(t),
      ..._leadingNumber.allMatches(t)
    ]) {
      final n = int.parse(m[1]!) - 1;
      if (n >= 0 && n < names.length && free(m.start, m.end)) {
        found.add((n, m.start, m.end));
      }
    }
    final order = [for (var i = 0; i < names.length; i++) i]
      ..sort((a, b) => names[b].length.compareTo(names[a].length));
    for (final i in order) {
      if (names[i].isEmpty) continue;
      var from = 0;
      while (true) {
        final at = t.indexOf(names[i], from);
        if (at < 0) break;
        final end = at + names[i].length;
        if (free(at, end)) found.add((i, at, end));
        from = end;
      }
    }
    found.sort((a, b) => a.$2.compareTo(b.$2));
    return [
      for (final m in found)
        if (m.$1 != mySeat) m
    ];
  }

  static final _boundary = RegExp(r'[，,。.！!；;]|所以|但是|但|不過|而且|然後|因此|可是|只是');

  /// What one stretch of words says about a player: doubt, trust, a
  /// question, or nothing.
  static PlayerSpeechKind? _stance(String piece) {
    bool has(String pattern) => RegExp(pattern).hasMatch(piece);
    // a question about someone asks; it does not accuse
    if (has(r'[?？]|嗎|為什麼|為何|怎麼|說說|解釋')) return PlayerSpeechKind.ask;
    // "not sure he is evil" is no stance at all, not trust
    if (_unsure.hasMatch(piece)) return null;
    // "not good" accuses, "not evil" vouches
    if (has(r'不信|不相信|不是好人|不是正義|不可信')) return PlayerSpeechKind.suspect;
    if (has(r'不是(壞人|邪惡|爪牙)')) return PlayerSpeechKind.trust;
    // "is not the Assassin" rules one role out, not a side
    if (has(r'不是(刺客|莫甘娜|莫德雷德|奧伯倫|梅林|派西)')) return null;
    // a doubt denied: "我不懷疑", "我不覺得他可疑"
    if (has(r'(不|沒有?|並不)(太)?(懷疑|覺得|認為).*?(可疑|壞|有問題)?') && has(r'懷疑|可疑|壞|有問題')) {
      return PlayerSpeechKind.trust;
    }
    if (has(r'懷疑|壞人|邪惡|可疑|有問題|爪牙|刺客|莫甘娜|莫德雷德|奧伯倫')) {
      return PlayerSpeechKind.suspect;
    }
    if (has(r'沒問題|清白|可以信|相信|信任|好人|正義')) {
      return PlayerSpeechKind.trust;
    }
    return null;
  }

  /// Words before a name that hand what follows to someone else
  /// ("4號說…", "有人認為…"): not the speaker's own view.
  static final _quoting = RegExp(r'^\s*(說|講|認為|覺得|懷疑|說過|點名)\s*$');
  static final _reporting = RegExp(r'(有人|別人|大家|他們|他|她)(說|講|認為|覺得|懷疑)');

  /// Words before a name that deny what follows ("我不同意3號是壞人").
  static final _denying = RegExp(r'(不|並不|沒有?)(同意|覺得|認為|相信|贊同)');

  /// Words that leave it open ("我不確定3號是壞人", "3號不一定是壞人").
  static final _unsure = RegExp(r'不確定|不一定|未必|不見得|說不定|不好說|難說|不敢說');

  /// The stance of the first clause in [piece] that has one.
  static PlayerSpeechKind? _firstStance(String piece) {
    for (final clause in piece.split(_boundary)) {
      if (_stance(clause) case final kind?) return kind;
    }
    return null;
  }

  /// The stance of the clause that ends [piece], right before a name.
  static PlayerSpeechKind? _lastStance(String piece) =>
      _stance(piece.split(_boundary).last);

  /// Reads typed text the way a table would. Each player named gets what
  /// is said around their name: the words right after it ("2號是好人"),
  /// or else the words leading up to it ("我懷疑5號"). Names joined by
  /// 和/跟/、 share what follows the last of them. A Lady word before a
  /// name makes what is said about that player a Lady result.
  static PlayerSpeech parse(String text, List<String> names, int mySeat) {
    final t = text.trim();
    bool has(String pattern) => RegExp(pattern).hasMatch(t);
    final mentions = _mentions(t, names, mySeat);
    // "我是派西維爾，3號是莫甘娜": a role claim, and whom it points at.
    // Naming someone as Merlin says nothing about who Morgana is.
    if (has(r'我(是|跳|才是|就是)派西')) {
      final morgana = mentions
          .where((m) => RegExp(r'^\s*(是|就是|才是)?\s*(莫甘娜|假梅林|壞人|邪惡)')
              .hasMatch(t.substring(m.$3)))
          .firstOrNull;
      final named = morgana ??
          (mentions.isNotEmpty && (has(r'莫甘娜|假梅林|壞人|邪惡') || !has(r'梅林'))
              ? mentions.first
              : null);
      return PlayerSpeech(PlayerSpeechKind.claimPercival,
          target: named?.$1, text: t);
    }
    final teamOppose = has(r'反對|換人|不同意|不支持|不要這隊|擋下|擋掉');
    final teamSupport = !teamOppose && has(r'支持|同意|贊成|沒理由不|再來一次|讓它過|可以過|給它過');
    final stances = <int, PlayerSpeechKind>{};
    final order = <int>[];
    final lady =
        RegExp(r'湖中女神|女神|查驗|驗出|驗到|驗了|查到|查出|查了|(?:剛|我)查(?=\s*\d)|驗(?=\s*\d)')
            .firstMatch(t);
    int? ladyTarget;
    for (var i = mentions.length - 1; i >= 0; i--) {
      final (seat, start, end) = mentions[i];
      final next = i + 1 < mentions.length ? mentions[i + 1].$2 : t.length;
      final after = t.substring(end, next);
      final before = t.substring(i > 0 ? mentions[i - 1].$3 : 0, start);
      final lead = before.split(_boundary).last;
      // someone else's view, passed on: not the speaker's own word, about
      // the one it is about ("…說3號…") nor about the one who holds it
      // ("2號懷疑3號")
      if ((i > 0 && _quoting.hasMatch(before)) ||
          _reporting.hasMatch(lead) ||
          (i + 1 < mentions.length && _quoting.hasMatch(after))) {
        continue;
      }
      // the lead-in leaves it open: no stance
      if (_unsure.hasMatch(lead)) continue;
      PlayerSpeechKind? kind;
      if (RegExp(r'^\s*(和|跟|與|、|還有|以及|及|或|或是)\s*$').hasMatch(after) &&
          i + 1 < mentions.length) {
        kind = stances[mentions[i + 1].$1];
      } else if (_firstStance(after) case final said?) {
        // "我不同意3號是壞人": the lead-in turns it around
        kind = !_denying.hasMatch(lead)
            ? said
            : switch (said) {
                PlayerSpeechKind.suspect => PlayerSpeechKind.trust,
                PlayerSpeechKind.trust => PlayerSpeechKind.suspect,
                _ => said,
              };
      } else {
        kind = _lastStance(before);
      }
      if (kind == null || stances.containsKey(seat)) continue;
      stances[seat] = kind;
      order.insert(0, seat);
      if (lady != null &&
          lady.end <= start &&
          kind != PlayerSpeechKind.ask &&
          (i == 0 || mentions[i - 1].$2 < lady.start)) {
        ladyTarget = seat;
      }
    }
    if (order.isNotEmpty) {
      final points = [
        for (final seat in order)
          seat == ladyTarget
              ? PlayerSpeech(PlayerSpeechKind.ladyClaim,
                  target: seat,
                  claimsEvil: stances[seat] == PlayerSpeechKind.suspect,
                  text: t)
              : PlayerSpeech(stances[seat]!, target: seat, text: t)
      ];
      // with players named, only a word about "this team" is a team vote
      final aboutTeam = has(r'這隊|這組|名單|隊伍|這次');
      final first = points.first;
      return PlayerSpeech(first.kind,
          target: first.target,
          claimsEvil: first.claimsEvil,
          text: t,
          supportsTeam: !aboutTeam
              ? null
              : teamOppose
                  ? false
                  : teamSupport
                      ? true
                      : null,
          more: points.skip(1).toList());
    }
    if (has(r'我是好人|我是正義|相信我')) {
      return PlayerSpeech(PlayerSpeechKind.claimGood, text: t);
    }
    if (teamOppose) return PlayerSpeech(PlayerSpeechKind.oppose, text: t);
    if (teamSupport || has(r'可以')) {
      return PlayerSpeech(PlayerSpeechKind.support, text: t);
    }
    return PlayerSpeech(PlayerSpeechKind.remark, text: t);
  }
}
