import '../game/discussion_model.dart';
import '../game/expansion_model.dart';
import '../game/game_model.dart';
import 'dialogue/bot_contract.dart';
import 'dialogue/bot_public_ledger.dart';

/// A private fact belongs to one player and to the alignment at that time.
class BotFact {
  const BotFact(
      {required this.quest,
      required this.target,
      required this.switched,
      required this.owner,
      required this.generation,
      this.evil,
      this.originalCard});
  final int quest, target;
  final int owner, generation;
  final bool switched;
  final bool? evil, originalCard;
}

/// The decision engine receives values, never a rules object or another seat's
/// private view. Visible seats have the meaning of this role's opening hint;
/// Percival sees candidates, not a mapping from seats to roles.
class BotObservation {
  BotObservation({
    required this.seat,
    required this.role,
    required this.evil,
    required this.count,
    required this.leader,
    required this.quest,
    required this.rejections,
    required this.failsRequired,
    required this.expansions,
    required this.switched,
    required List<int> visible,
    required List<int> team,
    required List<QuestResult> history,
    required List<ProposalRecord> proposals,
    required List<int> ladyPast,
    required List<BotFact> facts,
    required List<DiscussionStatement> statements,
    required Map<int, bool> ownCards,
    List<bool?> loyalty = const [],
    this.generation = 0,
    this.phase = GamePhase.discussion,
    Set<Role>? configuredRoles,
    List<String>? names,
    List<LadyCheck> ladyChecks = const [],
    this.excaliburHolder,
    this.plannedQuestSuccess,
  })  : visible = List.unmodifiable(visible),
        team = List.unmodifiable(team),
        history = List.unmodifiable(history),
        proposals = List.unmodifiable(proposals),
        ladyPast = List.unmodifiable(ladyPast),
        facts = List.unmodifiable(facts),
        statements = List.unmodifiable(statements),
        ownCards = Map.unmodifiable(ownCards),
        loyalty = List.unmodifiable(loyalty),
        configuredRoles =
            configuredRoles == null ? null : Set.unmodifiable(configuredRoles),
        names = List.unmodifiable(
            names ?? List.generate(count, (i) => '玩家${i + 1}')),
        ladyChecks = List.unmodifiable(ladyChecks) {
    bool validSeat(int value) => value >= 0 && value < count;
    bool validTeam(List<int> values) =>
        values.every(validSeat) && values.toSet().length == values.length;
    if (count < 5 ||
        count > 10 ||
        !validSeat(seat) ||
        !validSeat(leader) ||
        this.names.length != count ||
        quest < 1 ||
        quest > 6 ||
        !validTeam(this.team) ||
        !validTeam(this.visible) ||
        this.visible.contains(seat) ||
        this.history.any((q) => !validTeam(q.team))) {
      throw ArgumentError('Invalid observer seat or public player list');
    }
    for (final proposal in this.proposals) {
      if (!validSeat(proposal.leader) ||
          !validTeam(proposal.team) ||
          proposal.votes.length != count ||
          proposal.quest < 1 ||
          proposal.quest > quest ||
          proposal.attempt < 1 ||
          proposal.attempt > 5) {
        throw ArgumentError('Incomplete or invalid public proposal');
      }
    }
    for (final fact in this.facts) {
      if (fact.owner != seat ||
          fact.generation != generation ||
          fact.target < 0 ||
          fact.target >= count ||
          fact.target == seat ||
          fact.quest < 1 ||
          fact.quest > activeQuest ||
          (fact.evil == null) == (fact.originalCard == null)) {
        throw ArgumentError('Foreign, stale or malformed private evidence');
      }
    }
    if (this.ownCards.keys.any((q) =>
        q < 1 ||
        q > activeQuest ||
        !(q <= this.history.length ? this.history[q - 1].team : this.team)
            .contains(seat))) {
      throw ArgumentError('Own card is not from an observed participation');
    }
    for (final (index, statement) in this.statements.indexed) {
      if (!validSeat(statement.speaker) ||
          !validTeam(statement.team) ||
          (statement.target != null && !validSeat(statement.target!)) ||
          (statement.questionTo != null && !validSeat(statement.questionTo!)) ||
          (statement.generation != null &&
              statement.generation != generation) ||
          (statement.replyTo != null &&
              (statement.replyTo! < 0 || statement.replyTo! >= index)) ||
          (statement.quotedFrom != null &&
              (statement.quotedFrom! < 0 || statement.quotedFrom! >= index)) ||
          ((statement.claimedOriginalSuccess == null) !=
              (statement.originalCardQuest == null)) ||
          (statement.originalCardQuest != null &&
              (statement.originalCardQuest! < 1 ||
                  statement.originalCardQuest! > activeQuest))) {
        throw ArgumentError('Invalid public statement provenance');
      }
    }
  }

  final int seat, count, leader, quest, rejections, failsRequired;
  final Role role;
  final bool evil, switched;
  final ExpansionSettings expansions;
  final List<int> visible, team, ladyPast;
  final List<QuestResult> history;
  final List<ProposalRecord> proposals;
  final List<BotFact> facts;
  final List<DiscussionStatement> statements;
  final Map<int, bool> ownCards;
  final List<bool?> loyalty;
  final int generation;
  final GamePhase phase;
  final Set<Role>? configuredRoles;
  final List<String> names;
  final List<LadyCheck> ladyChecks;
  final int? excaliburHolder;

  /// Only this seat's committed card policy; no other seat's plan is projected.
  final bool? plannedQuestSuccess;
  int get activeQuest => switch (phase) {
        GamePhase.questResult ||
        GamePhase.lady ||
        GamePhase.ladyResult ||
        GamePhase.assassination ||
        GamePhase.finished =>
          history.length,
        _ => quest,
      };
  BotProposalId get proposalId {
    if ([GamePhase.quest, GamePhase.excalibur, GamePhase.excaliburResult]
        .contains(phase)) {
      final approved = proposals.where((p) => p.quest == quest && p.approved);
      if (approved.isNotEmpty) {
        return BotProposalId(generation, quest, approved.last.attempt);
      }
    }
    return BotProposalId(generation, quest, rejections + 1);
  }

  late final BotPublicLedger publicLedger = BotPublicLedger(
      generation: generation,
      count: count,
      proposals: proposals,
      history: history,
      ladyChecks: ladyChecks,
      loyalty: loyalty,
      activeQuest: activeQuest,
      statements: statements,
      currentProposal: proposalId,
      currentTeam: [
        GamePhase.discussion,
        GamePhase.freeDiscussion,
        GamePhase.vote,
        GamePhase.voteResult,
        GamePhase.quest,
        GamePhase.excalibur,
        GamePhase.excaliburResult
      ].contains(phase)
          ? team
          : const [],
      leader: leader);
  int get failures => history.where((q) => !q.succeeded).length;
  int get successes => history.length - failures;
  bool get mustFail => expansions.lancelot == 2 && role.isLancelot && evil;
}
