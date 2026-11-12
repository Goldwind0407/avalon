/// What a human can say during their turn to speak against computer
/// players. Each kind maps onto a public statement the bots understand.
enum PlayerSpeechKind {
  support,
  oppose,
  suspect,
  trust,
  ask,
  claimGood,

  /// Free text the bots could not read anything definite from.
  remark,
}

class PlayerSpeech {
  const PlayerSpeech(this.kind, {this.target, this.text});
  final PlayerSpeechKind kind;
  final int? target;

  /// What the player typed, if they typed it.
  final String? text;

  bool get needsTarget => const [
        PlayerSpeechKind.suspect,
        PlayerSpeechKind.trust,
        PlayerSpeechKind.ask
      ].contains(kind);

  /// Reads typed text the way a table would: a seat number or nickname, and
  /// whether it sounds like doubt, trust, a question, or a view on the team.
  /// Without a seat, doubt or trust cannot be pinned on anyone.
  static PlayerSpeech parse(String text, List<String> names, int mySeat) {
    final t = text.trim();
    int? seat;
    final number = RegExp(r'(\d{1,2})\s*號').firstMatch(t) ??
        RegExp(r'^\s*(\d{1,2})(?!\d)').firstMatch(t);
    if (number != null) {
      final n = int.parse(number[1]!) - 1;
      if (n >= 0 && n < names.length) seat = n;
    }
    if (seat == null) {
      // the longest nickname that appears (so 電腦1 does not match 電腦10)
      var best = -1;
      for (var i = 0; i < names.length; i++) {
        if (names[i].isNotEmpty &&
            t.contains(names[i]) &&
            (best < 0 || names[i].length > names[best].length)) {
          best = i;
        }
      }
      if (best >= 0) seat = best;
    }
    if (seat == mySeat) seat = null;
    bool has(String pattern) => RegExp(pattern).hasMatch(t);
    final distrusts = has(r'不信|不相信|不是好人|不可信');
    final clears = !distrusts && has(r'不是(壞人|邪惡|爪牙)|沒問題|清白|可以信|相信|信任');
    final doubts =
        distrusts || (!clears && has(r'懷疑|壞人|邪惡|可疑|有問題|爪牙|刺客|莫甘娜|莫德雷德'));
    final trusts = !doubts && (clears || has(r'好人|正義'));
    final asks = has(r'[?？]|為什麼|為何|怎麼|說說|解釋');
    if (seat != null) {
      if (doubts) {
        return PlayerSpeech(PlayerSpeechKind.suspect, target: seat, text: t);
      }
      if (asks) {
        return PlayerSpeech(PlayerSpeechKind.ask, target: seat, text: t);
      }
      if (trusts) {
        return PlayerSpeech(PlayerSpeechKind.trust, target: seat, text: t);
      }
    } else if (has(r'我是好人|我是正義|相信我')) {
      return PlayerSpeech(PlayerSpeechKind.claimGood, text: t);
    }
    if (has(r'反對|換人|不同意|不支持|不要這隊')) {
      return PlayerSpeech(PlayerSpeechKind.oppose, text: t);
    }
    if (has(r'支持|同意|贊成|可以')) {
      return PlayerSpeech(PlayerSpeechKind.support, text: t);
    }
    return PlayerSpeech(PlayerSpeechKind.remark, text: t);
  }
}
