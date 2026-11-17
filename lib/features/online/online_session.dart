import 'dart:async';
import '../../core/assets.dart';
import '../game/game_model.dart';
import '../game/game_session.dart';
import '../game/discussion_model.dart';
import '../game/expansion_model.dart';
import '../game/player_speech.dart';
import '../game/speech_statements.dart';
import '../solo/bot_table.dart' show finishedGameReview;
import '../solo/game_review.dart';
import '../lobby/room_model.dart';
import '../notebook/notebook_model.dart';
import 'online_service.dart';

/// Calls a game-server function with some arguments.
typedef ServerCall = Future<Map<String, dynamic>> Function(
    String name, Map<String, Object?> data);

class OnlinePlayer {
  const OnlinePlayer(this.uid, this.name, {this.bot = false, this.persona});
  final String uid;
  final String name;

  /// A computer player, and who it is in the cast (BotPersona.id).
  final bool bot;
  final String? persona;
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
            OnlinePlayer(p['uid'] as String, p['name'] as String,
                bot: p['bot'] == true, persona: p['persona'] as String?)
        ],
        botLevel = m['botLevel'] as String? ?? 'normal',
        talk = [
          for (final line in (m['talk'] as List? ?? const []))
            (line as Map).cast<String, dynamic>()
        ],
        optionalRoles = {
          for (final r in (m['optionalRoles'] as List? ?? const []))
            Role.values.byName(r as String)
        },
        gen = (m['gen'] as num?)?.toInt() ?? 0,
        away = {
          for (final seat in (m['away'] as List? ?? const []))
            (seat as num).toInt()
        },
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

  /// Seats whose phone has gone quiet; the server plays for them until
  /// their player is back.
  final Set<int> away;

  /// How well the computers play: novice, normal or expert.
  final String botLevel;

  /// What has been said in this game: the computers' lines in their stored
  /// form, and people's typed lines as `{by, q, a, sv, text}`.
  final List<Map<String, dynamic>> talk;
  bool get hasBots => players.any((p) => p.bot);

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
  if (expansions.lancelot > 0 && players < lancelotMinPlayers) {
    return lancelotPlayersIssue;
  }
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
    Future<void> Function(int now)? beat,
    Future<Map<String, dynamic>?> Function(int gen)? loadReview,
    super.notebook,
  })  : _call = call,
        _beat = beat,
        _loadReview = loadReview {
    _subs = [
      room.listen((data) {
        // once this player has left, their seat is gone: ignore the rest
        if (leaving) return;
        if (data == null) {
          closed = true;
          this.room = null;
          _mine = null;
        } else {
          closed = false;
          _roomError = null;
          this.room = OnlineRoom.fromMap(data);
        }
        _updated();
      }, onError: (Object e) => _failed(e, private: false)),
      mine.listen((data) {
        if (leaving) return;
        _mineError = null;
        _mine = data;
        _updated();
      }, onError: (Object e) => _failed(e, private: true)),
    ];
    clockReady = _synchronizeClock();
    if (beat != null) {
      unawaited(clockReady.then((_) => reportPresence()));
      _beatTimer = Timer.periodic(beatInterval, (_) => reportPresence());
    }
  }
  late final Future<void> clockReady;

  // ───────────── presence and stand-ins ─────────────

  /// How often this phone tells the server it is here. The server plays
  /// for a player it has not heard from for a minute (functions/src/proxy.ts).
  static const beatInterval = Duration(seconds: 20);

  /// How long the game may stand still before this phone asks the server
  /// to look for players who are gone: soon when someone is already known
  /// to be away, otherwise the host first and the others after.
  static const nudgeAwayDelay = Duration(seconds: 8),
      nudgeHostDelay = Duration(seconds: 30),
      nudgeDelay = Duration(seconds: 45);

  final Future<void> Function(int now)? _beat;
  Timer? _beatTimer, _nudgeTimer;

  /// Tells the server this phone is here (also called when the app comes
  /// back to the front). Failures are left to the next beat.
  void reportPresence() {
    final beat = _beat;
    if (beat == null || _disposed || leaving) return;
    unawaited(beat(nowMillis).catchError((Object _) {}));
    // back after being played for: take the seat back without waiting
    if (room?.away.contains(mySeat) ?? false) unawaited(_nudge());
  }

  /// Seats the game is waiting for, as far as this phone can tell.
  Set<int> get _awaited => switch (phase) {
        GamePhase.identity => {
            for (var s = 0; s < players.length; s++)
              if (!confirmedSeats.contains(s)) s
          },
        GamePhase.team || GamePhase.voteResult || GamePhase.questResult => {
            leader
          },
        GamePhase.discussion => {if (speaker != null) speaker!},
        GamePhase.vote => {
            for (var s = 0; s < players.length; s++)
              if (!votedSeats.contains(s)) s
          },
        GamePhase.quest => team.toSet().difference(playedSeats),
        GamePhase.lady || GamePhase.ladyResult => {
            if (ladyHolder != null) ladyHolder!
          },
        GamePhase.excalibur || GamePhase.excaliburResult => {
            if (excaliburHolder != null) excaliburHolder!
          },
        // who the Assassin is stays hidden: -1 stands for "someone else"
        GamePhase.assassination => {
            mySeat != null && roleOf(mySeat!) == Role.assassin ? mySeat! : -1
          },
        _ => const {},
      };

  /// (Re)starts the wait before asking the server to play for whoever has
  /// gone quiet. Runs on every change of the room.
  void _scheduleNudge() {
    _nudgeTimer?.cancel();
    if (_beat == null || _disposed || !tableAvailable) return;
    final me = mySeat, away = room!.away;
    if (away.contains(me)) {
      unawaited(_nudge());
      return;
    }
    final awaited = _awaited;
    if (awaited.every((s) => s == me)) return;
    final known =
        awaited.any(away.contains) || (awaited.contains(-1) && away.isNotEmpty);
    final forComputer = _computerDelay(awaited);
    final delay = forComputer ??
        (known
                ? nudgeAwayDelay
                : isHost
                    ? nudgeHostDelay
                    : nudgeDelay) +
            // a little apart, so the phones do not all ask at once
            Duration(milliseconds: 400 * (me ?? 0));
    _nudgeTimer = Timer(delay, () async {
      await _nudge();
      if (!_disposed) _scheduleNudge();
    });
  }

  /// How long to leave the table alone before the computers it waits for
  /// are asked to move; null when it waits for no computer. The host's
  /// phone asks first; the others only if nothing has come of that.
  Duration? _computerDelay(Set<int> awaited) {
    final waitsForBot = awaited.any((s) => s >= 0 && isComputer(s)) ||
        (awaited.contains(-1) && (room!.hasBots || room!.away.isNotEmpty));
    if (!waitsForBot) return null;
    final Duration wait;
    if (phase == GamePhase.discussion) {
      // first its line, then time to read it (as in solo play)
      final line = currentStatement;
      wait = line == null
          ? const Duration(milliseconds: 700)
          : Duration(
              milliseconds:
                  (7000 + (line.length - 25).clamp(0, 35) * 200).toInt());
    } else if (const [
      GamePhase.voteResult,
      GamePhase.questResult,
      GamePhase.ladyResult,
      GamePhase.excaliburResult
    ].contains(phase)) {
      wait = const Duration(milliseconds: 6500);
    } else if (phase == GamePhase.assassination) {
      wait = const Duration(seconds: 5);
    } else {
      wait = const Duration(milliseconds: 1200);
    }
    return isHost ? wait : wait + const Duration(seconds: 4);
  }

  @override
  bool get hasComputers =>
      room != null &&
      (room!.hasBots || room!.away.isNotEmpty || room!.talk.isNotEmpty);

  /// A computer seat's own voice; a player who is away has none of theirs.
  @override
  String? voiceOf(int seat) {
    final players = room?.players ?? const <OnlinePlayer>[];
    return seat >= 0 && seat < players.length && players[seat].bot
        ? players[seat].persona
        : null;
  }

  /// A computer seat, or a player who is away and played for meanwhile.
  @override
  bool isComputer(int seat) =>
      seat >= 0 &&
      seat < (room?.players.length ?? 0) &&
      (room!.players[seat].bot || room!.away.contains(seat));

  @override
  List<DiscussionStatement> get statements => [
        for (final line in room?.talk ?? const <Map<String, dynamic>>[])
          line['bot'] == true
              ? statementFromMap(line)
              : DiscussionStatement(
                  speaker: (line['by'] as num).toInt(),
                  quest: (line['q'] as num).toInt(),
                  attempt: (line['a'] as num?)?.toInt(),
                  generation: (line['g'] as num?)?.toInt(),
                  text: line['text'] as String)
      ];

  /// What the player now speaking has put in writing this turn.
  @override
  String? get currentStatement {
    if (phase != GamePhase.discussion) return null;
    final who = speaker;
    for (final line in (room?.talk ?? const []).reversed) {
      if (line['by'] == who && line['sv'] == speechVersion) {
        return line['text'] as String;
      }
    }
    return null;
  }

  /// A line typed in this player's speaking turn, for the computers (and
  /// everyone else) to read.
  @override
  Future<void> say(PlayerSpeech speech) async {
    final text = speechText(speech, ballot: proposalHistory.lastOrNull);
    if (text.isEmpty) return;
    await _call('say', {'code': code, 'generation': generation, 'text': text});
  }

  @override
  Future<void> expressOpinion(bool approve) async {
    final version = speechVersion;
    await _call('say', {
      'code': code,
      'generation': generation,
      'text': approve ? '這隊我可以接受，支持。' : '這隊我不放心，想換個組合。'
    });
    await endSpeech(version);
  }

  /// Host: seats the computer [persona] under [name], or sends it away.
  Future<void> setBot(String persona, String name, {required bool seated}) =>
      _call('setBot',
          {'code': code, 'persona': persona, 'name': name, 'seated': seated});
  Future<void> setBotLevel(String level) =>
      _call('setBotLevel', {'code': code, 'level': level});

  // ───────────── the review, once the game is over ─────────────

  final Future<Map<String, dynamic>?> Function(int gen)? _loadReview;
  int? _reviewGen;
  GameReview? _review;

  @override
  GameReview? get review =>
      _reviewGen == generation && phase == GamePhase.finished ? _review : null;

  @override
  String? get reviewDifficulty => room?.hasBots ?? false
      ? switch (room!.botLevel) {
          'novice' => '新手',
          'expert' => '高手',
          _ => '一般',
        }
      : null;

  /// Fetches the server's record of a finished game, once a deal.
  void _fetchReview() {
    final load = _loadReview, seat = mySeat, gen = generation;
    if (load == null ||
        seat == null ||
        phase != GamePhase.finished ||
        _reviewGen == gen) {
      return;
    }
    _reviewGen = gen;
    _review = null;
    unawaited(() async {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final game = await load(gen);
          if (_disposed || _reviewGen != gen) return;
          if (game != null) {
            _review = finishedGameReview(game)?.call(seat);
            notifyListeners();
            return;
          }
        } catch (_) {/* try again shortly */}
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }());
  }

  bool _nudging = false;
  Future<void> _nudge() async {
    if (_nudging || _disposed || leaving) return;
    _nudging = true;
    try {
      await _call('nudge', {'code': code});
    } catch (_) {
      // an older server, or no connection: the game goes on as before
    } finally {
      _nudging = false;
    }
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
      refreshSpeechTimer(active: tableAvailable);
    } catch (_) {/* Local time remains a usable offline fallback. */}
  }

  void _updated() {
    refreshSpeechTimer(active: tableAvailable);
    _scheduleNudge();
    _fetchReview();
    if (tableAvailable) {
      final scope = notebookScope;
      final card = _myCard;
      final role =
          card == null ? null : Role.values.byName(card['role'] as String);
      final opening = role == null
          ? null
          : '${role.label}・${role.isEvil ? '邪惡陣營' : '正義陣營'}\n${role.isEvil ? '讓任務失敗或找出梅林' : '完成三次任務，並保護梅林'}\n${knowledgeText(role, [
                for (final i in card!['visible'] as List? ?? const [])
                  (i as num).toInt()
              ], players, configuredRoles: configuredRoles, expansions: expansions, lancelot: (card['lancelot'] as num?)?.toInt())}';
      final records = proposalHistory;
      final seat = mySeat;
      final pages = role == null || seat == null
          ? const <String, PlayerNote>{}
          : openingNotesByPlayer(seat);
      _notebookSync = _notebookSync.then((_) async {
        if (_disposed || notebookScope != scope) return;
        await notebook.synchronize(scope,
            opening: opening, proposals: records, openingNotes: pages);
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
      beat: (now) => service.beat(code, uid, now),
      loadReview: (gen) => service.review(code, gen),
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
  Object? _roomError, _mineError;
  Object? get error => _roomError ?? _mineError;
  @override
  bool get tableAvailable =>
      room?.inGame == true &&
      !closed &&
      !leaving &&
      error == null &&
      mySeat != null;

  void _failed(Object e, {required bool private}) {
    if (leaving) return;
    if (private) {
      _mineError = e;
      _mine = null;
    } else {
      _roomError = e;
    }
    refreshSpeechTimer(active: false);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _beatTimer?.cancel();
    _nudgeTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  bool get isHost => room?.hostUid == uid;
  @override
  Set<int> get awaySeats => room?.away ?? const {};

  Map<String, dynamic> get _game => room?.game ?? const {};

  List<int> _ints(String key) =>
      [for (final v in (_game[key] as List? ?? const [])) (v as num).toInt()];

  Future<void> _move(String move,
      [Map<String, Object?> extra = const {}]) async {
    final before = super.nowMillis;
    final response = await _call('move', {
      'code': code,
      'move': move,
      'generation': generation,
      'historyLength': history.length,
      'rejections': rejections,
      ...extra
    });
    if (_disposed) return;
    final server = (response['serverNow'] as num?)?.toInt();
    if (server != null) {
      _clockOffset = server - ((before + super.nowMillis) ~/ 2);
      refreshSpeechTimer(active: tableAvailable);
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
      refreshSpeechTimer(active: tableAvailable);
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
    return knowledgeText(role, visiblePlayers(seat), players,
        configuredRoles: configuredRoles,
        expansions: expansions,
        lancelot: knownLancelotSeat(seat));
  }

  @override
  int? knownLancelotSeat(int seat) {
    final card = _myCard;
    if (seat != mySeat || card == null) return null;
    return (card['lancelot'] as num?)?.toInt();
  }

  @override
  Set<Role> get configuredRoles => {
        Role.merlin,
        Role.assassin,
        ...?room?.optionalRoles,
        if (expansions.lancelot > 0) ...[Role.lancelotGood, Role.lancelotEvil],
      };

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
  Future<void> proposeTeam(List<int> team, {int? excalibur}) => _move(
      'proposeTeam',
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
    return [
      for (var i = 0; i < 5; i++) i < cards.length ? cards[i] as bool? : null
    ];
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

  /// One phone per player: what the Lady showed this player can stay.
  @override
  List<PrivateReveal> get myLadyResults => [
        for (final r in myReveals)
          if (r.kind == 'lady') r
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
