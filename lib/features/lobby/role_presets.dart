import '../game/game_model.dart';
import 'room_model.dart';

/// Recommended special roles for a player count, on top of Merlin and the
/// Assassin, as most published setups have them: Percival always comes
/// with Morgana (without her he would know Merlin from the start), and the
/// evil places fill up with Mordred and then Oberon as the table grows.
/// Applied whenever the number of players changes; players can still
/// change any of it afterwards. Expansions are never switched on here.
///
/// With the Lancelot expansion one evil place goes to the evil Lancelot,
/// so the preset gives up as many evil roles as it must ([fitForLancelot]).
Set<Role>? rolePreset(int players, {bool lancelot = false}) {
  final preset = switch (players) {
    5 || 6 => const {Role.percival, Role.morgana},
    7 || 8 || 9 => const {Role.percival, Role.morgana, Role.mordred},
    10 => const {Role.percival, Role.morgana, Role.mordred, Role.oberon},
    _ => null,
  };
  if (preset == null || !lancelot) return preset;
  return fitForLancelot(players, preset);
}

/// Evil roles a setup gives up first when there are more than places:
/// Oberon (who mostly hampers his own side), then Mordred, then Morgana.
const _dropFirst = [Role.oberon, Role.mordred, Role.morgana];

/// [roles] (the extras on top of Merlin and the Assassin) with as many
/// evil roles taken out as the evil Lancelot needs room for.
Set<Role> fitForLancelot(int players, Set<Role> roles) {
  final fitted = {...roles};
  // the Assassin and the evil Lancelot take one evil place each
  final room = Room.evilCount(players) - 2;
  for (final role in _dropFirst) {
    if (fitted.where((r) => r.isEvil).length <= room) break;
    fitted.remove(role);
  }
  return fitted;
}
