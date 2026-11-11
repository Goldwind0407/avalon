import '../game/game_model.dart';

/// Recommended special roles for a player count, on top of Merlin and the
/// Assassin. Applied whenever the number of players changes; players can
/// still change any of it afterwards. Expansions are never switched on here;
/// with the Lancelot expansion (7+ players) the Lancelots still fit.
Set<Role>? rolePreset(int players) => switch (players) {
      5 || 6 || 7 || 8 => const {Role.percival, Role.morgana},
      9 => const {Role.percival, Role.mordred},
      10 => const {Role.percival, Role.morgana, Role.mordred},
      _ => null,
    };
