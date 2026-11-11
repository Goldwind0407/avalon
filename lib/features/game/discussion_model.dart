class DiscussionSettings {
  const DiscussionSettings(
      {this.enabled = false,
      this.speechSeconds = 45,
      this.freeSeconds = 0,
      this.selectionFree = true});
  static const recommended = DiscussionSettings(enabled: true);
  factory DiscussionSettings.fromMap(Map<String, dynamic>? data) => data == null
      ? const DiscussionSettings()
      : DiscussionSettings(
          enabled: data['enabled'] == true,
          speechSeconds: (data['speechSeconds'] as num?)?.toInt() ?? 45,
          freeSeconds: (data['freeSeconds'] as num?)?.toInt() ?? 0,
          selectionFree: data['selectionFree'] != false);
  final bool enabled, selectionFree;
  final int speechSeconds, freeSeconds;
  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'speechSeconds': speechSeconds,
        'freeSeconds': freeSeconds,
        'selectionFree': selectionFree
      };
}

class ProposalRecord {
  ProposalRecord(
      {required this.quest,
      required this.attempt,
      required this.leader,
      required List<int> team,
      required List<bool> votes})
      : team = List.unmodifiable(team),
        votes = List.unmodifiable(votes);
  factory ProposalRecord.fromMap(Map<String, dynamic> data) => ProposalRecord(
      quest: (data['quest'] as num).toInt(),
      attempt: (data['attempt'] as num).toInt(),
      leader: (data['leader'] as num).toInt(),
      team: [for (final v in data['team'] as List) (v as num).toInt()],
      votes: [for (final v in data['votes'] as List) v as bool]);
  final int quest, attempt, leader;
  final List<int> team;
  final List<bool> votes;
  bool get approved => votes.where((v) => v).length > votes.length / 2;
  Map<String, dynamic> toMap() => {
        'quest': quest,
        'attempt': attempt,
        'leader': leader,
        'team': team,
        'votes': votes,
        'approved': approved
      };
}
