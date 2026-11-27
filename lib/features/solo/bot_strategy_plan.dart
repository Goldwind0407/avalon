/// A private conversational objective, not knowledge about anyone's real role.
enum BotGoal { exposeSuspect, framePlayer, defendAlly, defendSelf, buildTrust }

class BotStrategyPlan {
  const BotStrategyPlan(this.goal, this.target, this.generation, this.switched);
  final BotGoal goal;
  final int target, generation;
  final bool switched;
}

/// How a computer means to play this game, chosen once at its first move
/// from its style (a beginner always plays [steady]). It only shifts how
/// readily it does what it would do anyway; it never gives it information.
enum BotTactic {
  /// The usual mix.
  steady(null),

  /// Evil: plays Success on the first quests to buy trust, and strikes later.
  lieLow('潛伏'),

  /// Evil: fails a quest as soon as there is a chance.
  early('早攻'),

  /// Merlin: votes and leads like a servant far more, says little.
  hidden('低調'),

  /// Merlin: steers the table more openly, accepting the risk of being
  /// found.
  guide('帶路');

  const BotTactic(this.label);

  /// Shown at the end of the game; null for [steady].
  final String? label;
}
