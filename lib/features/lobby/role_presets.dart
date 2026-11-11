import '../game/game_model.dart';

/// Recommended special roles for a player count, on top of Merlin and the
/// Assassin. Applied whenever the number of players changes; players can
/// still change any of it afterwards. Expansions are never switched on here:
/// the Lancelots only join when the Lancelot expansion was chosen, and then
/// take an evil place (so 5–6 players leave Morgana out).
Set<Role>? rolePreset(int players, {bool lancelot = false}) => switch (players) {
      5 || 6 when lancelot => const {Role.percival},
      5 || 6 || 7 || 8 => const {Role.percival, Role.morgana},
      9 => const {Role.percival, Role.mordred},
      10 => const {Role.percival, Role.morgana, Role.mordred},
      _ => null,
    };
