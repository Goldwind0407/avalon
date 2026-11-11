import 'dart:async';
import '../../core/assets.dart';
import '../game/game_model.dart';
import '../game/game_session.dart';
import '../game/discussion_model.dart';
import '../game/expansion_model.dart';
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
        voiceRoomId = m['voiceRoomId'] as String?,
        discussion = DiscussionSettings.fromMap(
            (m['discussion'] as Map?)?.cast<String, dynamic>()),
        expansions = ExpansionSettings.fromMap(
            (m['expansions'] as Map?)?.cast<String, dynamic>()),
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
        notice = m['notice'] as String?,
        noticeStep = (m['noticeStep'] as num?)?.toInt(),
        game = (m['game'] as Map?)?.cast<String, dynamic>();

  final String code;
  final String hostUid;
  final String? voiceRoomId;
  final DiscussionSettings discussion;
  final ExpansionSettings expansions;
  final String status;
  final List<OnlinePlayer> players;
  final Set<Role> optionalRoles;
  final int gen;

  /// Something to tell everyone, e.g. "阿瘋 離開了房間，對局已中止",
  /// written at [noticeStep] so each phone shows it once.
  final String? notice;
  final int? noticeStep;
  final Map<String, dynamic>? game;

  bool get inGame => status == 'playing' && game != null;
  int seatOf(String uid) => players.indexWhere((p) => p.uid == uid);
}

/// Roles the host can add on top of Merlin and the Assassin.
const optionalRoles = [Role.percival, Role.morgana, Role.mordred, Role.oberon];

/// Why a game with [players] players and these extra roles cannot start
/// (same check as the server's configIssue).
String? onlineSetupIssue(int players, Set<Role> extra,
    [ExpansionSettings expansions = const ExpansionSettings()]) {
  if (players < 5 || players > 10) return '需要 5～10 位玩家';
  final special = [
    Role.merlin,
    Role.assassin,
    ...extra,
    if (expansions.lancelot > 0) ...[Role.lancelotGood, Role.lancelotEvil],
  ];
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
    super.notebook,
  }) : _call = call {
    _subs = [
      room.listen((data) {
        // once this player has left, their seat is gone: ignore the rest
        if (leaving) return;
        if (data == null) {
          closed = true;
        } else {
          error = null;
          this.room = OnlineRoom.fromMap(data);
        }
        _updated();
      }, onError: _failed),
      mine.listen((data) {
        if (leaving) return;
        _mine = data;
        _updated();
      }, onError: _failed),
    ];
    unawaited(_synchronizeClock());
  }

  int _clockOffset = 0;
  bool _disposed = false;
  Future<void> _notebookSync = Future.value();
  @override
  int get nowMillis => super.nowMillis + _clockOffset;

  Future<void> _synchronizeClock() async {
    final before = super.nowMillis;
    try {
      final response = await _call('serverTime', {});
      if (_disposed) return;
      final server = (response['serverNow'] as num?)?.toInt();
      if (server != null) {
        _clockOffset = server - ((before + super.nowMillis) ~/ 2);
      }
      refreshSpeechTimer(active: room?.inGame == true && !leaving && !closed);
    } catch (_) {/* Local time remains a usable offline fallback. */}
  }

  void _updated() {
    refreshSpeechTimer(active: room?.inGame == true && !leaving && !closed);
    if (room?.inGame == true && mySeat != null) {
      final scope = notebookScope;
      final card = _myCard;
      final role =
          card == null ? null : Role.values.byName(card['role'] as String);
      final opening = role == null
          ? null
          : '${role.label}・${role.isEvil ? '邪惡陣營' : '正義陣營'}\n${role.isEvil ? '讓任務失敗或找出梅林' : '完成三次任務，並保護梅林'}\n${knowledgeText(role, [
                for (final i in card!['visible'] as List? ?? const [])
                  (i as num).toInt()
              ], players)}';
      final records = proposalHistory;
      _notebookSync = _notebookSync.then((_) async {
        if (_disposed || notebookScope != scope) return;
        await notebook.synchronize(scope, opening: opening, proposals: records);
      });
    }
    notifyListeners();
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
  @override
  String get notebookScope =>
      'online/${room?.voiceRoomId ?? code}/$uid/$generation';
  late final List<StreamSubscription<Object?>> _subs;

  /// Latest room document; null until it arrives.
  OnlineRoom? room;
  Map<String, dynamic>? _mine;

  /// The room no longer exists (everyone left).
  bool closed = false;

  /// Reading the room failed (e.g. this player is no longer in it).
  Object? error;

  void _failed(Object e) {
    if (leaving) return;
    error = e;
    refreshSpeechTimer(active: false);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  bool get isHost => room?.hostUid == uid;

  Map<String, dynamic> get _game => room?.game ?? const {};

  List<int> _ints(String key) =>
      [for (final v in (_game[key] as List? ?? const [])) (v as num).toInt()];

  Future<void> _move(String move,
      [Map<String, Object?> extra = const {}]) async {
    final before = super.nowMillis;
    final response =
        await _call('move', {'code': code, 'move': move, ...extra});
    if (_disposed) return;
    final server = (response['serverNow'] as num?)?.toInt();
    if (server != null) {
      _clockOffset = server - ((before + super.nowMillis) ~/ 2);
      refreshSpeechTimer(active: room?.inGame == true && !leaving && !closed);
    }
  }

  // ───────────── lobby ─────────────

  Future<void> setRoles(Set<Role> roles) => _call('setRoles', {
        'code': code,
        'roles': [for (final r in roles) r.name],
      });
  Future<void> setExpansions(ExpansionSettings settings) =>
      _call('setExpansions', {'code': code, 'expansions': settings.toMap()});
  Future<void> setDiscussion(DiscussionSettings settings) =>
      _call('setDiscussion', {'code': code, 'discussion': settings.toMap()});
  Future<void> start() => _call('startGame', {'code': code});
  Future<void> backToLobby() => _call('backToLobby', {'code': code});

  /// This player has asked to leave the room.
  bool leaving = false;

  /// Gives up this player's seat. During a game this ends it for everyone.
  Future<void> leave() async {
    leaving = true;
    refreshSpeechTimer(active: false);
    try {
      await _call('leaveRoom', {'code': code});
    } catch (_) {
      leaving = false;
      refreshSpeechTimer(active: room?.inGame == true && !closed);
      rethrow;
    }
  }

  @override
  bool get canLeaveRoom => true;
  @override
  Future<void> leaveRoom() => leave();

  // ───────────── table ─────────────

  @override
  List<String> get players => [for (final p in room?.players ?? []) p.name];
  @override
  List<String> get playerIds => [for (final p in room?.players ?? []) p.uid];
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
              (q['fails'] as num).toInt(), q['succeeded'] as bool,
              excaliburHolder: (q['excalibur']?['holder'] as num?)?.toInt(),
              excaliburTarget: (q['excalibur']?['target'] as num?)?.toInt())
      ];
  @override
  DiscussionSettings get discussionSettings => DiscussionSettings.fromMap(
      (_game['discussion'] as Map?)?.cast<String, dynamic>());
  @override
  List<ProposalRecord> get proposalHistory => [
        for (final p in _game['proposals'] as List? ?? const [])
          ProposalRecord.fromMap(Map<String, dynamic>.from(p as Map))
      ];
  @override
  int get speechVersion => (_game['speechVersion'] as num?)?.toInt() ?? 0;
  @override
  int? get speechDeadline => (_game['speechDeadline'] as num?)?.toInt();
  @override
  int? get speaker => phase == GamePhase.discussion && players.isNotEmpty
      ? (leader + 1 + ((_game['speechIndex'] as num?)?.toInt() ?? 0)) %
          players.length
      : null;
  @override
  Future<void> endSpeech(int expectedVersion) => _move('endSpeech',
      {'expectedVersion': expectedVersion, 'generation': generation});
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
    return knowledgeText(role, visiblePlayers(seat), players);
  }

  @override
  List<int> visiblePlayers(int seat) {
    final card = _myCard;
    if (seat != mySeat || card == null) return const [];
    return [
      for (final v in card['visible'] as List? ?? const []) (v as num).toInt()
    ];
  }

  @override
  bool get canAdvance => mySeat == leader || isHost;
  @override
  bool get canRestart => isHost;

  // ───────────── moves ─────────────

  @override
  Future<void> confirmIdentity(int seat) => _move('confirmIdentity');
  @override
  Future<void> proposeTeam(List<int> team, {int? excalibur}) =>
      _move('proposeTeam',
          {'team': team, if (excalibur != null) 'excalibur': excalibur});
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

  // ───────────── expansions ─────────────

  @override
  ExpansionSettings get expansions => ExpansionSettings.fromMap(
      (_game['expansions'] as Map?)?.cast<String, dynamic>());
  @override
  List<bool?> get loyalty {
    final cards = _game['loyalty'] as List? ?? const [];
    return [for (var i = 0; i < 5; i++) i < cards.length ? cards[i] as bool? : null];
  }

  @override
  bool get lancelotSwitched => _game['lancelotSwitched'] == true;
  @override
  int? get ladyHolder => (_game['ladyHolder'] as num?)?.toInt();
  @override
  List<int> get ladyPast => _ints('ladyPast');
  @override
  List<LadyCheck> get ladyChecks => [
        for (final c in _game['ladyChecks'] as List? ?? const [])
          LadyCheck((c['holder'] as num).toInt(), (c['target'] as num).toInt(),
              (c['quest'] as num).toInt())
      ];
  @override
  int? get excaliburHolder => (_game['excaliburHolder'] as num?)?.toInt();

  /// Everything the Lady and Excalibur have shown this player.
  List<PrivateReveal> get myReveals => [
        for (final r in _myCard?['reveals'] as List? ?? const [])
          PrivateReveal.fromMap(Map<String, dynamic>.from(r as Map))
      ];

  @override
  PrivateReveal? get latestReveal {
    final (kind, quest) = switch (phase) {
      GamePhase.ladyResult => ('lady', history.length),
      GamePhase.excaliburResult => ('excalibur', questNumber),
      _ => ('', -1),
    };
    for (final r in myReveals.reversed) {
      if (r.kind == kind && r.quest == quest) return r;
    }
    return null;
  }

  @override
  Future<void> useLady(int target) => _move('useLady', {'target': target});
  @override
  Future<void> continueLady() => _move('continueLady');
  @override
  Future<void> useExcalibur(int? target) =>
      _move('useExcalibur', {'target': target});
  @override
  Future<void> continueExcalibur() => _move('continueExcalibur');
}
