/// A private conversational objective, not knowledge about anyone's real role.
enum BotGoal { exposeSuspect, framePlayer, defendAlly, defendSelf, buildTrust }

class BotStrategyPlan {
  const BotStrategyPlan(this.goal, this.target, this.generation, this.switched);
  final BotGoal goal;
  final int target, generation;
  final bool switched;
}
