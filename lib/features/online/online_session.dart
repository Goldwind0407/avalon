import 'dart:async';
import '../../core/assets.dart';
import '../game/game_model.dart';
import '../game/game_session.dart';
import '../lobby/room_model.dart';
import 'online_service.dart';

/// Calls a game-server function with some arguments.
typedef ServerCall = Future<Map<String, dynamic>> Function(
    String name, Map<String, Object?> data);

class OnlinePlayer {
  const OnlinePlayer(this.uid, this.name);
  final String uid;
  final String name;
}

/// The public room document (rooms/{code}), as written by the server.
class OnlineRoom {
  OnlineRoom.fromMap(Map<String, dynamic> m)
      : code = m['code'] as String,
        hostUid = m['hostUid'] as String,
        status = m['status'] as String,
        players = [
          for (final p in (m['players'] as List))
            OnlinePlayer(p['uid'] as String, p['name'] as String)
        ],
        optionalRoles = {
          for (final r in (m['optionalRoles'] as List? ?? const []))
            Role.values.byName(r as String)
        },
        gen = (m['gen'] as num?)?.toInt() ?? 0,
        game = (m['game'] as Map?)?.cast<String, dynamic>();

  final String code;
  final String hostUid;
  final String status;
  final List<OnlinePlayer> players;
  final Set<Role> optionalRoles;
  final int gen;
  final Map<String, dynamic>? game;

  bool get inGame => status == 'playing' && game != null;
  int seatOf(String uid) => players.indexWhere((p) => p.uid == uid);
}

/// Roles the host can add on top of Merlin and the Assassin.
const optionalRoles = [Role.percival, Role.morgana, Role.mordred, Role.oberon];

/// Why a game with [players] players and these extra roles cannot start
/// (same check as the server's configIssue).
String? onlineSetupIssue(int players, Set<Role> extra) {
  if (players < 5 || players > 10) return '需要 5～10 位玩家';
  final special = [Role.merlin, Role.assassin, ...extra];
  final evil = special.where((r) => r.isEvil).length;
  final good = special.length - evil;
  if (evil > Room.evilCount(players)) return '邪惡角色超過本局邪惡陣營名額';
  if (good > players - Room.evilCount(players)) return '正義角色超過本局正義陣營名額';
  return null;
}

/// One player's view of an online room. Only knows what the server lets
/// this player read; every move is sent to the server, and the table
/// updates when the new state comes back.
class OnlineGameSession extends GameSession {
  OnlineGameSession({
    required this.code,
    required this.uid,
    required Stream<Map<String, dynamic>?> room,
    required Stream<Map<String, dynamic>?> mine,
    required ServerCall call,
  }) : _call = call {
    _subs = [
      room.listen((data) {
        if (data == null) {
          closed = true;
        } else {
          this.room = OnlineRoom.fromMap(data);
        }
        notifyListeners();
      }, onError: _failed),
      mine.listen((data) {
        _mine = data;
        notifyListeners();
      }, onError: _failed),
    ];
  }

  /// Connects to a room on the Firebase project.
  factory OnlineGameSession.connect(String code, String uid) {
    final service = OnlineService.instance;
    return OnlineGameSession(
      code: code,
      uid: uid,
      room: service.room(code),
      mine: service.mine(code, uid),
      call: service.call,
    );
  }

  final String code;
  final String uid;
  final ServerCall _call;
  late final List<StreamSubscription<Object?>> _subs;

  /// Latest room document; null until it arrives.
  OnlineRoom? room;
  Map<String, dynamic>? _mine;

  /// The room no longer exists (everyone left).
  bool closed = false;

  /// Reading the room failed (e.g. this player is no longer in it).
  Object? error;

  void _failed(Object e) {
    error = e;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  bool get isHost => room?.hostUid == uid;

  Map<String, dynamic> get _game => room?.game ?? const {};

  List<int> _ints(String key) =>
      [for (final v in (_game[key] as List? ?? const [])) (v as num).toInt()];

  Future<void> _move(String move, [Map<String, Object?> extra = const {}]) =>
      _call('move', {'code': code, 'move': move, ...extra});

  // ───────────── lobby ─────────────

  Future<void> setRoles(Set<Role> roles) => _call('setRoles', {
        'code': code,
        'roles': [for (final r in roles) r.name],
      });
  Future<void> start() => _call('startGame', {'code': code});
  Future<void> backToLobby() => _call('backToLobby', {'code': code});
  Future<void> leave() => _call('leaveRoom', {'code': code});

  // ───────────── table ─────────────

  @override
  List<String> get players => [for (final p in room?.players ?? []) p.name];
  @override
  GamePhase get phase =>
      GamePhase.values.byName(_game['phase'] as String? ?? 'identity');
  @override
  int get leader => (_game['leader'] as num?)?.toInt() ?? 0;
  @override
  int get rejections => (_game['rejections'] as num?)?.toInt() ?? 0;
  @override
  List<int> get team => _ints('team');
  @override
  List<bool> get votes =>
      [for (final v in (_game['votes'] as List? ?? const [])) v as bool];
  @override
  List<QuestResult> get history => [
        for (final q in (_game['history'] as List? ?? const []))
          QuestResult([for (final i in q['team'] as List) (i as num).toInt()],
              (q['fails'] as num).toInt(), q['succeeded'] as bool)
      ];
  @override
  List<bool>? get revealOrder {
    final quests = _game['history'] as List? ?? const [];
    if (quests.isEmpty) return null;
    return [for (final c in quests.last['order'] as List) c as bool];
  }

  @override
  String? get winner => _game['winner'] as String?;
  @override
  String get result => _game['result'] as String? ?? '';
  @override
  int? get assassinTarget => (_game['assassinTarget'] as num?)?.toInt();
  @override
  Set<int> get confirmedSeats => _ints('confirmed').toSet();
  @override
  Set<int> get votedSeats => _ints('voted').toSet();
  @override
  Set<int> get playedSeats => _ints('played').toSet();
  @override
  int get generation => room?.gen ?? 0;

  // ───────────── this phone ─────────────

  @override
  int? get mySeat {
    final seat = room?.seatOf(uid) ?? -1;
    return seat < 0 ? null : seat;
  }

  /// Roles become public when the game ends.
  List<Role>? get _revealed {
    final roles = _game['revealedRoles'] as List?;
    return roles == null
        ? null
        : [for (final r in roles) Role.values.byName(r as String)];
  }

  /// This player's own role card, once it belongs to the current deal.
  Map<String, dynamic>? get _myCard =>
      _mine != null && (_mine!['gen'] as num?)?.toInt() == generation
          ? _mine
          : null;

  @override
  Role? roleOf(int seat) {
    final revealed = _revealed;
    if (revealed != null) return revealed[seat];
    final card = _myCard;
    if (card == null || seat != mySeat) return null;
    return Role.values.byName(card['role'] as String);
  }

  @override
  String? roleArt(int seat) {
    final role = roleOf(seat);
    // keyed by seat so a card keeps its picture when all are revealed
    return role == null ? null : Assets.role(role, seat);
  }

  @override
  String knowledge(int seat) {
    final role = roleOf(seat);
    final card = _myCard;
    if (role == null || card == null) return '';
    final visible = [
      for (final v in card['visible'] as List? ?? const []) (v as num).toInt()
    ];
    return knowledgeText(role, visible, players);
  }

  @override
  bool get canAdvance => mySeat == leader || isHost;
  @override
  bool get canRestart => isHost;

  // ───────────── moves ─────────────

  @override
  Future<void> confirmIdentity(int seat) => _move('confirmIdentity');
  @override
  Future<void> proposeTeam(List<int> team) =>
      _move('proposeTeam', {'team': team});
  @override
  Future<void> vote(int seat, bool approve) =>
      _move('vote', {'approve': approve});
  @override
  Future<void> continueVote() => _move('continueVote');
  @override
  Future<void> playQuest(int seat, bool success) =>
      _move('playQuest', {'success': success});
  @override
  Future<void> continueQuest() => _move('continueQuest');
  @override
  Future<void> assassinate(int target) =>
      _move('assassinate', {'target': target});
  @override
  Future<void> restart() => start();
}
