/// Public speech. A claimed alignment is an assertion, not verified knowledge.
enum DiscussionPosition { suspect, defend }

enum DiscussionCertainty { tentative, certain, permanent }

class DiscussionStatement {
  DiscussionStatement(
      {required this.speaker,
      required this.quest,
      required this.text,
      this.target,
      this.claimedEvil,
      this.switched,
      this.supportsTeam,
      this.generation,
      this.attempt,
      this.intent,
      this.topic,
      this.questionTo,
      this.replyTo,
      this.position,
      this.certainty = DiscussionCertainty.tentative,
      this.claimedOriginalSuccess,
      this.originalCardQuest,
      this.quotedFrom,
      this.claimsOpeningKnowledge = false,
      List<String> evidenceIds = const [],
      List<int> team = const []})
      : team = List.unmodifiable(team),
        evidenceIds = List.unmodifiable(evidenceIds);
  final int speaker, quest;
  final String text;
  final int? target;
  final bool? claimedEvil;
  final bool? switched, supportsTeam;
  final List<int> team;
  final int? generation, attempt, questionTo, replyTo;

  /// Public semantic intent, never the private strategy/role-specific rule ID.
  final String? intent;

  /// What the line is about (a member, a past vote…), so the next speaker
  /// can agree with it instead of saying the same thing again.
  final String? topic;
  final List<String> evidenceIds;
  final DiscussionPosition? position;
  final DiscussionCertainty certainty;

  /// Public assertions, never another player's verified private card.
  final bool? claimedOriginalSuccess;
  final int? originalCardQuest, quotedFrom;
  final bool claimsOpeningKnowledge;

  /// "I am Percival", true or not. [target], if any, is the player the
  /// speaker says is Morgana. Like every claim, it proves nothing.
  static const percivalClaim = 'claimPercival';
  bool get claimsPercival => intent == percivalClaim;

  /// The same statement worded differently.
  DiscussionStatement copyWithText(String text) => DiscussionStatement(
      speaker: speaker,
      quest: quest,
      text: text,
      target: target,
      claimedEvil: claimedEvil,
      switched: switched,
      supportsTeam: supportsTeam,
      generation: generation,
      attempt: attempt,
      intent: intent,
      topic: topic,
      questionTo: questionTo,
      replyTo: replyTo,
      position: position,
      certainty: certainty,
      claimedOriginalSuccess: claimedOriginalSuccess,
      originalCardQuest: originalCardQuest,
      quotedFrom: quotedFrom,
      claimsOpeningKnowledge: claimsOpeningKnowledge,
      evidenceIds: evidenceIds,
      team: team);
}

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
