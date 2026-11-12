/// The Lancelot expansion needs at least this many players.
const lancelotMinPlayers = 7;
const lancelotPlayersIssue = '蘭斯洛特擴充需要 7 人以上';

/// Optional expansions chosen before the game (same as `Expansions` in
/// functions/src/rules.ts).
class ExpansionSettings {
  const ExpansionSettings(
      {this.lady = false, this.lancelot = 0, this.excalibur = false});

  /// Lady of the Lake: after quests 2, 3 and 4 the holder examines one
  /// player's loyalty, then hands the Lady to them.
  final bool lady;

  /// Lancelot: 0 off; 1 loyalty cards turned over from quest 3 on;
  /// 2 five loyalty cards dealt face up at the start.
  final int lancelot;

  /// Excalibur: the leader hands it to a team member, who may flip one other
  /// member's quest card.
  final bool excalibur;

  bool get any => lady || lancelot > 0 || excalibur;

  factory ExpansionSettings.fromMap(Map<String, dynamic>? data) => data == null
      ? const ExpansionSettings()
      : ExpansionSettings(
          lady: data['lady'] == true,
          lancelot: ((data['lancelot'] as num?)?.toInt() ?? 0).clamp(0, 2),
          excalibur: data['excalibur'] == true);

  Map<String, dynamic> toMap() =>
      {'lady': lady, 'lancelot': lancelot, 'excalibur': excalibur};

  ExpansionSettings copyWith({bool? lady, int? lancelot, bool? excalibur}) =>
      ExpansionSettings(
          lady: lady ?? this.lady,
          lancelot: lancelot ?? this.lancelot,
          excalibur: excalibur ?? this.excalibur);

  /// Short description for setup screens, e.g. "湖中女神・蘭斯洛特（變體一）".
  String get summary => [
        if (lady) '湖中女神',
        if (lancelot == 1) '蘭斯洛特（變體一）',
        if (lancelot == 2) '蘭斯洛特（變體二）',
        if (excalibur) '王者之劍',
      ].join('・');

  @override
  bool operator ==(Object other) =>
      other is ExpansionSettings &&
      other.lady == lady &&
      other.lancelot == lancelot &&
      other.excalibur == excalibur;
  @override
  int get hashCode => Object.hash(lady, lancelot, excalibur);
}

/// What the Lady of the Lake or Excalibur showed one player.
class PrivateReveal {
  const PrivateReveal(
      {required this.kind,
      required this.quest,
      required this.target,
      this.evil,
      this.card});
  factory PrivateReveal.fromMap(Map<String, dynamic> m) => PrivateReveal(
      kind: m['kind'] as String,
      quest: (m['quest'] as num).toInt(),
      target: (m['target'] as num).toInt(),
      evil: m['evil'] as bool?,
      card: m['card'] as bool?);

  /// 'lady' or 'excalibur'.
  final String kind;
  final int quest, target;

  /// Lady: the target's loyalty at that moment.
  final bool? evil;

  /// Excalibur: the card the target had played before it was flipped.
  final bool? card;
}
