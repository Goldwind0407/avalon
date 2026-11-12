import '../../game/game_model.dart';

/// Stable IDs used by assets and dialogue. Lancelot IDs describe allegiance
/// NOW; the referee's Role enum continues to describe the initial role.
enum BotDialogueRole {
  all,
  loyal,
  merlin,
  percival,
  minion,
  assassin,
  morgana,
  mordred,
  oberon,
  lancelotGood,
  lancelotEvil;

  static BotDialogueRole forPlayer(Role role, bool evilNow) {
    if (role.isLancelot) return evilNow ? lancelotEvil : lancelotGood;
    return switch (role) {
      Role.loyal => loyal,
      Role.merlin => merlin,
      Role.percival => percival,
      Role.minion => minion,
      Role.assassin => assassin,
      Role.morgana => morgana,
      Role.mordred => mordred,
      Role.oberon => oberon,
      _ => throw StateError('Unexpected role'),
    };
  }
}

enum BotSpeechIntent {
  hedge,
  supportTeam,
  opposeTeam,
  warnFifthVote,
  explainTeam,
  questionTeam,
  defendSelf,
  defendOther,
  quoteQuest,
  challengeVote,
  replyQuestion,
  reassess,
  avoidRepeat,
  endgame,
  accuse,
  misdirect,
  challengeClaim,
  explainVote,
  bluff,
  interpretLady,
  challengeLady,
  discussSword,
  discussLancelot,
  assassinate;
}

enum BotClaimPolicy {
  publicGrounded,
  privateTruthClaim,
  privateStrategyPublicClaim,
  strategicOpinionBluff,
  explicitPrivateClaimLie;
}

enum BotEvidenceKind {
  proposal,
  ballot,
  quest,
  ladyUse,
  swordUse,
  loyalty,
  statement
}

class BotProposalId {
  const BotProposalId(this.generation, this.quest, this.attempt);
  final int generation, quest, attempt;
  String get id => 'g$generation/q$quest/a$attempt';
  @override
  bool operator ==(Object other) => other is BotProposalId && id == other.id;
  @override
  int get hashCode => id.hashCode;
}

/// An opaque reference: resolving it requires the observer's public ledger.
class BotEvidenceId {
  const BotEvidenceId(this.generation, this.kind, this.key);
  final int generation;
  final BotEvidenceKind kind;
  final String key;
  String get id => 'g$generation/${kind.name}/$key';
  @override
  bool operator ==(Object other) => other is BotEvidenceId && id == other.id;
  @override
  int get hashCode => id.hashCode;
}

/// No role labels, private actual cards or private planned votes belong here.
class BotPublicEvidence {
  BotPublicEvidence(
      {required this.id,
      required this.quest,
      this.attempt,
      this.actor,
      this.target,
      List<int> team = const [],
      List<bool> ballots = const [],
      this.fails,
      this.succeeded,
      this.switchOccurred,
      this.statementIndex})
      : team = List.unmodifiable(team),
        ballots = List.unmodifiable(ballots);
  final BotEvidenceId id;
  final int quest;
  final int? attempt, actor, target, fails, statementIndex;
  final List<int> team;
  final List<bool> ballots;
  final bool? succeeded, switchOccurred;
}

/// Explicitly private. Never put this trace or the rule ID in a public
/// DiscussionStatement: role-specific rule IDs themselves reveal identities.
class BotDialogueTrace {
  BotDialogueTrace(
      {required this.ruleId,
      required this.proposal,
      required this.intent,
      required this.policy,
      required this.plannedApprove,
      required List<BotEvidenceId> publicEvidence,
      required this.semanticKey})
      : publicEvidence = List.unmodifiable(publicEvidence);
  final String ruleId, semanticKey;
  final BotProposalId proposal;
  final BotSpeechIntent intent;
  final BotClaimPolicy policy;
  final bool plannedApprove;
  final List<BotEvidenceId> publicEvidence;
}
