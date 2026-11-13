import 'dart:math';
import 'bot_brain.dart';
import 'bot_observation.dart';

/// Private decision data. Never serialize into public room/speech data.
class BotVoteDecision {
  BotVoteDecision(this.approve, this.reason, this.risk, List<double> suspicion)
      : suspicion = List.unmodifiable(suspicion);
  final bool approve;
  final String reason;
  final double risk;
  final List<double> suspicion;
}

/// Replaying one decision seed preserves acting preferences: hearing a new
/// argument can change a vote, opening a panel or re-evaluating cannot reroll it.
class BotVotePlan {
  BotVotePlan(this.seed);
  final int seed;
  BotVoteDecision? initial, current;
  bool locked = false;

  BotVoteDecision evaluate(BotBrain brain, BotObservation observation,
      {bool lock = false}) {
    if (locked) return current!;
    brain.vote(observation, decisionRandom: Random(seed));
    current = brain.lastVoteDecision!;
    initial ??= current;
    locked = lock;
    return current!;
  }
}
