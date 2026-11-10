import 'dart:math';

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
  final Set<String> specialRoles = {'梅林', '刺客'};
  static int evilCount(int count) => switch (count) {
        5 || 6 => 2,
        7 || 8 || 9 => 3,
        10 => 4,
        _ => 0,
      };
  String? get roleIssue {
    if (players.length < 5 || players.length > 10) return '需要 5～10 位玩家';
    final evil = specialRoles
        .where((r) => ['刺客', '莫甘娜', '莫德雷德', '奧伯倫'].contains(r))
        .length;
    final good = specialRoles.where((r) => ['梅林', '派西維爾'].contains(r)).length;
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

/// Local prototype only. Different devices do NOT share this state.
class LocalRoomRepository {
  final Map<String, Room> _rooms = {};
  final Random _rng = Random.secure();
  String _newCode() {
    for (var tries = 0; tries < 1000; tries++) {
      final code = (100000 + _rng.nextInt(900000)).toString();
      if (!_rooms.containsKey(code)) return code;
    }
    throw StateError('無法產生房號');
  }

  Room create(String name) {
    final room = Room(
        code: _newCode(),
        players: [Player(id: 'local', name: name, isHost: true)]);
    _rooms[room.code] = room;
    return room;
  }

  Room? join(String code, String name) {
    final room = _rooms[code];
    if (room == null) return null;
    // Reopen the local host's room without adding the same device twice.
    if (room.players.any((p) => p.id == 'local')) return room;
    if (room.players.length >= 10) return null;
    room.players.add(Player(id: 'local', name: name));
    return room;
  }

  void addDemoPlayer(Room room, {String? name}) {
    if (room.players.length >= 10) return;
    final next = room.players.length + 1;
    room.players
        .add(Player(id: 'demo$next', name: name ?? '騎士 $next', isReady: true));
  }

  void removeDemoPlayer(Room room) {
    final index = room.players.lastIndexWhere((p) => p.id != 'local');
    if (index >= 0) room.players.removeAt(index);
  }
}
