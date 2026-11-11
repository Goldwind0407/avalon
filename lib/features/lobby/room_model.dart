import '../game/discussion_model.dart';
import '../game/expansion_model.dart';

class Player {
  Player(
      {required this.id,
      required this.name,
      this.isReady = false,
      this.isHost = false});
  final String id;
  final String name;
  bool isReady;
  final bool isHost;
}

class Room {
  Room({required this.code, required this.players});
  final String code;
  final List<Player> players;
  DiscussionSettings discussion = const DiscussionSettings();
  ExpansionSettings expansions = const ExpansionSettings();
  final Set<String> specialRoles = {'梅林', '刺客'};
  static int evilCount(int count) => switch (count) {
        5 || 6 => 2,
        7 || 8 || 9 => 3,
        10 => 4,
        _ => 0,
      };
  String? get roleIssue {
    if (players.length < 5 || players.length > 10) return '需要 5～10 位玩家';
    if (expansions.lancelot > 0 && players.length < lancelotMinPlayers) {
      return lancelotPlayersIssue;
    }
    // the two Lancelots take one good and one evil place
    final lancelot = expansions.lancelot > 0 ? 1 : 0;
    final evil = specialRoles
            .where((r) => ['刺客', '莫甘娜', '莫德雷德', '奧伯倫'].contains(r))
            .length +
        lancelot;
    final good =
        specialRoles.where((r) => ['梅林', '派西維爾'].contains(r)).length + lancelot;
    if (evil > evilCount(players.length)) return '邪惡角色超過本局邪惡陣營名額';
    if (good > players.length - evilCount(players.length)) {
      return '正義角色超過本局正義陣營名額';
    }
    if (!specialRoles.containsAll(['梅林', '刺客'])) return '必須包含梅林與刺客';
    if (specialRoles
        .any((r) => !['梅林', '派西維爾', '刺客', '莫甘娜', '莫德雷德', '奧伯倫'].contains(r))) {
      return '包含未知角色';
    }
    return null;
  }

  bool get canStart => roleIssue == null && players.every((p) => p.isReady);
}
