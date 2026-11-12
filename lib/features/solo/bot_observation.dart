import '../game/discussion_model.dart';
import '../game/expansion_model.dart';
import '../game/game_model.dart';

/// A private fact belongs to one player and to the alignment at that time.
class BotFact {
  const BotFact(
      {required this.quest,
      required this.target,
      required this.switched,
      this.evil,
      this.originalCard});
  final int quest, target;
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
  })  : visible = List.unmodifiable(visible),
        team = List.unmodifiable(team),
        history = List.unmodifiable(history),
        proposals = List.unmodifiable(proposals),
        ladyPast = List.unmodifiable(ladyPast),
        facts = List.unmodifiable(facts),
        statements = List.unmodifiable(statements),
        ownCards = Map.unmodifiable(ownCards),
        loyalty = List.unmodifiable(loyalty);

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
  int get failures => history.where((q) => !q.succeeded).length;
  int get successes => history.length - failures;
  bool get mustFail => expansions.lancelot == 2 && role.isLancelot && evil;
}
