import 'dart:math';
import '../lobby/room_model.dart';

enum GamePhase {
  identity,
  team,
  vote,
  voteResult,
  quest,
  questResult,
  assassination,
  finished
}

enum Role {
  merlin('梅林', false),
  percival('派西維爾', false),
  loyal('亞瑟的忠臣', false),
  assassin('刺客', true),
  morgana('莫甘娜', true),
  mordred('莫德雷德', true),
  oberon('奧伯倫', true),
  minion('莫德雷德的爪牙', true);

  const Role(this.label, this.isEvil);
  final String label;
  final bool isEvil;
}

/// Team size for quest number [questIndex] (0-based) with [players] players.
int questTeamSize(int players, int questIndex) => switch (players) {
      5 => [2, 3, 2, 3, 3],
      6 => [2, 3, 4, 3, 4],
      7 => [2, 3, 3, 4, 4],
      _ => [3, 4, 4, 5, 5],
    }[min(questIndex, 4)];

/// Seats the player at [index] gets to see at the start of the game.
/// The server has the same rule in functions/src/rules.ts.
List<int> visibleSeats(List<Role> roles, int index) {
  final role = roles[index];
  return [
    for (var i = 0; i < roles.length; i++)
      if (i != index &&
          ((role == Role.merlin &&
                  roles[i].isEvil &&
                  roles[i] != Role.mordred) ||
              (role == Role.percival &&
                  [Role.merlin, Role.morgana].contains(roles[i])) ||
              (role.isEvil &&
                  role != Role.oberon &&
                  roles[i].isEvil &&
                  roles[i] != Role.oberon)))
        i
  ];
}

/// Display a seat and nickname consistently in game prompts.
String playerLabel(int seat, String name) => '${seat + 1} 號 【$name】';

/// Keep the visible players and role-specific reminder on separate lines.
String knowledgeText(Role role, List<int> visible, List<String> players) {
  final names = visible.map((i) => playerLabel(i, players[i])).join('、');
  if (role == Role.merlin) return '你看見的邪惡玩家：$names。\n莫德雷德不會被你看見。';
  if (role == Role.percival) return '梅林候選人：$names。\n若有莫甘娜，你無法分辨兩者。';
  if (role == Role.oberon) return '你屬於邪惡陣營。\n你與其他邪惡玩家互不相認。';
  if (role.isEvil) return '你的邪惡同伴：${names.isEmpty ? '無' : names}。\n奧伯倫不會出現在此。';
  return '你沒有額外情報。\n透過討論與投票，找出值得信任的隊友。';
}

class QuestResult {
  QuestResult(List<int> team, this.fails, this.succeeded)
      : team = List.unmodifiable(team);
  final List<int> team;
  final int fails;
  final bool succeeded;
}

/// All secrets live on this device. Intended for trusted, pass-and-play games.
class AvalonGame {
  AvalonGame(Room room, {Random? random}) {
    if (!room.canStart) throw StateError('玩家或角色尚未準備完成');
    players = List.unmodifiable(room.players.map((p) => p.name));
    final rng = random ?? Random.secure();
    final deck = room.specialRoles
        .map((name) => Role.values.firstWhere((r) => r.label == name))
        .toList();
    while (
        deck.where((r) => r.isEvil).length < Room.evilCount(players.length)) {
      deck.add(Role.minion);
    }
    while (deck.length < players.length) {
      deck.add(Role.loyal);
    }
    deck.shuffle(rng);
    roles = List.unmodifiable(deck);
    leader = rng.nextInt(players.length);
  }

  late final List<String> players;
  late final List<Role> roles;
  late int leader;
  GamePhase phase = GamePhase.identity;
  int actor = 0;
  int rejections = 0;
  final List<QuestResult> _history = [];
  final List<int> _team = [];
  final List<bool> _votes = [];
  final List<bool> _cards = [];
  List<QuestResult> get history => List.unmodifiable(_history);
  List<int> get team => List.unmodifiable(_team);
  List<bool> get votes =>
      phase == GamePhase.voteResult ? List.unmodifiable(_votes) : const [];
  int get successes => _history.where((q) => q.succeeded).length;
  int get failures => _history.length - successes;
  int get questNumber => _history.length + 1;
  int get requiredTeam => questTeamSize(players.length, _history.length);
  int get failsRequired => players.length >= 7 && questNumber == 4 ? 2 : 1;
  bool get teamApproved => _votes.where((v) => v).length > players.length / 2;
  int get questActor => _team[actor];
  String? winner;
  String result = '';

  void _require(GamePhase expected) {
    if (phase != expected) throw StateError('目前階段無法執行此操作');
  }

  String knowledge(int index) =>
      knowledgeText(roles[index], visibleSeats(roles, index), players);

  void confirmIdentity() {
    _require(GamePhase.identity);
    actor++;
    if (actor == players.length) {
      actor = 0;
      phase = GamePhase.team;
    }
  }

  void proposeTeam(Iterable<int> selected) {
    _require(GamePhase.team);
    final members = selected.toSet().toList()..sort();
    if (members.length != requiredTeam ||
        members.any((i) => i < 0 || i >= players.length)) {
      throw ArgumentError('隊伍人數不正確');
    }
    _team
      ..clear()
      ..addAll(members);
    _votes.clear();
    actor = 0;
    phase = GamePhase.vote;
  }

  void vote(bool approve) {
    _require(GamePhase.vote);
    _votes.add(approve);
    actor++;
    if (actor == players.length) {
      actor = 0;
      phase = GamePhase.voteResult;
    }
  }

  void continueVote() {
    _require(GamePhase.voteResult);
    if (teamApproved) {
      rejections = 0;
      _cards.clear();
      phase = GamePhase.quest;
    } else {
      rejections++;
      if (rejections == 5) {
        _finish('邪惡', '連續五次組隊遭否決，邪惡陣營獲勝。');
      } else {
        _nextLeader();
        phase = GamePhase.team;
      }
    }
  }

  void playQuest(bool success) {
    _require(GamePhase.quest);
    if (!success && !roles[questActor].isEvil) throw ArgumentError('正義玩家只能出成功');
    _cards.add(success);
    actor++;
    if (actor == _team.length) {
      final fails = _cards.where((v) => !v).length;
      final succeeded = fails < failsRequired;
      _history.add(QuestResult(_team, fails, succeeded));
      actor = 0;
      phase = GamePhase.questResult;
    }
  }

  void continueQuest() {
    _require(GamePhase.questResult);
    if (failures == 3) {
      _finish('邪惡', '三次任務失敗，邪惡陣營獲勝。');
    } else if (successes == 3) {
      phase = GamePhase.assassination;
    } else {
      _nextLeader();
      phase = GamePhase.team;
    }
  }

  void assassinate(int target) {
    _require(GamePhase.assassination);
    // Reject only invalid seats and the Assassin's own seat. Checking a
    // target's alignment here would let the UI verify hidden identities.
    if (target < 0 ||
        target >= players.length ||
        roles[target] == Role.assassin) {
      throw ArgumentError('請選擇其他玩家');
    }
    final hit = roles[target] == Role.merlin;
    _finish(hit ? '邪惡' : '正義',
        '刺客選擇 ${target + 1} 號 ${players[target]}，${hit ? '成功刺殺梅林。' : '未能找到梅林，正義陣營獲勝！'}');
  }

  void _nextLeader() {
    leader = (leader + 1) % players.length;
    _team.clear();
  }

  void _finish(String side, String reason) {
    winner = side;
    result = reason;
    phase = GamePhase.finished;
  }
}
