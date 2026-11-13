import 'dart:math';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/assets.dart';
import '../lobby/room_model.dart';
import 'game_model.dart';
import 'discussion_model.dart';
import 'player_speech.dart';
import 'expansion_model.dart';
import '../notebook/notebook_model.dart';

/// A move was refused (wrong phase, not your turn, connection lost…).
class GameMoveException implements Exception {
  const GameMoveException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What this device knows about a game, and the moves it can make.
///
/// The table screen only talks to this, so the same table, pieces and
/// animations serve both ways of playing:
///  * [LocalGameSession] — one phone passed around; it knows everything and
///    hides secrets behind hand-off screens.
///  * the online session — every player on their own phone; it only knows
///    what its player may see and asks the server to make moves.
abstract class GameSession extends ChangeNotifier {
  GameSession({GameNotebook? notebook}) : _notebook = notebook;
  Timer? _speechTimer;
  bool _disposed = false;
  DiscussionSettings get discussionSettings => const DiscussionSettings();
  List<ProposalRecord> get proposalHistory => const [];
  List<DiscussionStatement> get statements => const [];
  String? get currentStatement => null;
  Future<void> expressOpinion(bool approve) async {}

  /// Solo: say something during this player's turn to speak, without ending
  /// it. Computer players take it into account and may answer.
  Future<void> say(PlayerSpeech speech) async {}
  void pauseAutomation(bool paused) {}
  int? get speaker => null;
  int get speechVersion => 0;
  int? get speechDeadline => null;
  int get nowMillis => DateTime.now().millisecondsSinceEpoch;
  bool get discussing =>
      phase == GamePhase.discussion || phase == GamePhase.freeDiscussion;
  Future<void> endSpeech(int expectedVersion) async {}

  /// One deadline timer per device; version checks make concurrent expiry safe.
  void refreshSpeechTimer({bool active = true, bool retry = false}) {
    _speechTimer?.cancel();
    if (_disposed || !active || !discussing || speechDeadline == null) return;
    final version = speechVersion, deal = generation;
    final delay = max(
        retry ? 3000 : 0,
        speechDeadline! -
            nowMillis +
            (canAdvance || mySeat == speaker ? 250 : 4250));
    _speechTimer = Timer(Duration(milliseconds: delay), () async {
      if (_disposed || deal != generation || version != speechVersion) return;
      try {
        await endSpeech(version);
      } catch (_) {/* Retry after a transient connection failure. */}
      if (!_disposed && deal == generation && version == speechVersion) {
        refreshSpeechTimer(retry: true);
      }
    });
  }

  GameNotebook? _notebook;
  GameNotebook get notebook => _notebook ??= GameNotebook();

  /// What [seat] learnt from their own card, as notes for the notebook's
  /// player pages (keyed by seat). Only this device's own knowledge.
  Map<int, PlayerNote> openingNotes(int seat) {
    final role = roleOf(seat);
    if (role == null) return const {};
    final seen = visiblePlayers(seat);
    final lancelot = knownLancelotSeat(seat);
    return {
      seat: PlayerNote(
          text: '我：${role.label}',
          side: role.isEvil ? SuspectedSide.evil : SuspectedSide.good),
      for (final s in seen)
        s: switch (role) {
          Role.merlin =>
            const PlayerNote(text: '開局看到：邪惡', side: SuspectedSide.evil),
          Role.percival => seen.length == 1
              ? const PlayerNote(text: '開局看到：梅林', side: SuspectedSide.good)
              : const PlayerNote(text: '梅林候選人（其中一位可能是莫甘娜）'),
          _ => PlayerNote(
              text: s == lancelot ? '邪惡同伴（邪惡蘭斯洛特）' : '邪惡同伴',
              side: SuspectedSide.evil),
        },
    };
  }

  /// [openingNotes] keyed like the notebook's player pages.
  Map<String, PlayerNote> openingNotesByPlayer(int seat) => {
        for (final e in openingNotes(seat).entries)
          if (e.key < playerIds.length) playerIds[e.key]: e.value
      };
  String get notebookScope => 'local/${identityHashCode(this)}/$generation';
  @override
  void dispose() {
    _disposed = true;
    _speechTimer?.cancel();
    _notebook?.dispose();
    super.dispose();
  }

  // ───────────── public table ─────────────

  List<String> get players;
  List<String> get playerIds => List.generate(players.length, (i) => 'seat$i');
  GamePhase get phase;
  int get leader;
  int get rejections;
  List<int> get team;

  /// Everyone's vote; only filled while the result is shown.
  List<bool> get votes;
  List<QuestResult> get history;
  String? get winner;
  String get result;
  int? get assassinTarget;

  /// Seats that have looked at their identity.
  Set<int> get confirmedSeats;

  /// Seats whose vote is lying face down on the table.
  Set<int> get votedSeats;

  /// Team members that have played their quest card.
  Set<int> get playedSeats;

  /// Increases every time a new game is dealt.
  int get generation;

  /// The order the last quest's cards are turned over in, when the server
  /// decides it (so every phone shows the same order).
  List<bool>? get revealOrder => null;

  int get successes => history.where((q) => q.succeeded).length;
  int get failures => history.length - successes;
  int get questNumber => history.length + 1;
  int get requiredTeam => questTeamSize(players.length, history.length);
  int get failsRequired => players.length >= 7 && questNumber == 4 ? 2 : 1;
  bool get teamApproved => votes.where((v) => v).length > players.length / 2;

  // ───────────── this device ─────────────

  /// Seat of the person holding this phone, or null when it is passed round.
  int? get mySeat;
  bool get hasOwnSeat => mySeat != null;
  bool get isSolo => false;

  /// Solo: a computer player's style, once it may be shown.
  String? seatStyle(int seat) => null;
  bool get isOnline => hasOwnSeat && !isSolo;
  bool get hasPrivateInput => true;
  bool get tableAvailable => true;

  /// The seat that has to take the phone for the current secret step
  /// (pass & play only).
  int? get handoffSeat => null;

  /// The role at [seat], if this device is allowed to know it.
  Role? roleOf(int seat);

  /// Card artwork for the role at [seat] (null when unknown here).
  String? roleArt(int seat);

  /// What the player at [seat] learns when they look at their card.
  String knowledge(int seat);

  /// Public seat numbers this player is allowed to see in their private card.
  List<int> visiblePlayers(int seat) => const [];

  /// Which of [seat]'s visible allies is the evil Lancelot, if this device
  /// may know.
  int? knownLancelotSeat(int seat) => null;
  Set<Role>? get configuredRoles => null;

  /// May this device press the shared "continue" buttons?
  bool get canAdvance;

  /// May this device deal a new game once this one is over?
  bool get canRestart;

  // ───────────── moves ─────────────

  Future<void> confirmIdentity(int seat);
  Future<void> proposeTeam(List<int> team, {int? excalibur});
  Future<void> vote(int seat, bool approve);
  Future<void> recordVotes(List<bool> ballots) async {
    throw const GameMoveException('只有一機模式支援公開登記投票');
  }

  Future<void> continueVote();
  Future<void> playQuest(int seat, bool success);
  Future<void> continueQuest();
  Future<void> assassinate(int target);
  Future<void> restart();

  /// Online only: give up this player's seat (ends a game in progress).
  bool get canLeaveRoom => false;
  Future<void> leaveRoom() async {}

  // ───────────── expansions ─────────────

  ExpansionSettings get expansions => const ExpansionSettings();

  /// Lancelot loyalty card on each quest (null: none turned over).
  List<bool?> get loyalty => const [null, null, null, null, null];

  /// The Lancelots currently play for the other side.
  bool get lancelotSwitched => false;
  int? get ladyHolder => null;

  /// Everyone who has held the Lady (they cannot be examined).
  List<int> get ladyPast => const [];
  List<LadyCheck> get ladyChecks => const [];

  /// Who holds Excalibur on the current team.
  int? get excaliburHolder => null;

  /// What the Lady or Excalibur has just shown the player using it (only on
  /// the device allowed to see it).
  PrivateReveal? get latestReveal => null;

  /// The side the player at [seat] plays for now, if this device knows.
  bool? evilNow(int seat) {
    final role = roleOf(seat);
    return role == null
        ? null
        : role.isEvil != (role.isLancelot && lancelotSwitched);
  }

  /// Variant 2: a Lancelot on the evil side may only play Fail.
  bool mustFail(int seat) =>
      expansions.lancelot == 2 &&
      (roleOf(seat)?.isLancelot ?? false) &&
      evilNow(seat) == true;

  Future<void> useLady(int target) async {}
  Future<void> continueLady() async {}
  Future<void> useExcalibur(int? target) async {}
  Future<void> continueExcalibur() async {}
}

/// Card art for every seat, giving each loyal servant and minion its own
/// picture where possible.
List<String> roleArtwork(List<Role> roles) {
  final seen = <Role, int>{};
  return [
    for (final r in roles)
      Assets.role(r, seen.update(r, (v) => v + 1, ifAbsent: () => 0))
  ];
}

/// One phone passed around the table; secrets are protected by hand-offs.
class LocalGameSession extends GameSession {
  LocalGameSession(this.room, {Random? random}) : _random = random {
    _deal();
  }

  final Room room;
  final Random? _random;
  late AvalonGame _game;
  late List<String> _art;
  int _generation = 0;
  int? _assassinTarget;

  /// The rules object behind this session (pass & play keeps everything).
  AvalonGame get game => _game;

  void _deal() {
    _game = AvalonGame(room, random: _random);
    _art = roleArtwork(_game.roles);
    _assassinTarget = null;
    _generation++;
  }

  Future<void> _apply(void Function() move) async {
    try {
      move();
    } on StateError catch (e) {
      throw GameMoveException(e.message);
    } on ArgumentError catch (e) {
      throw GameMoveException('${e.message}');
    }
    notifyListeners();
    refreshSpeechTimer();
  }

  Set<int> _first(int count, [List<int>? seats]) =>
      (seats ?? List.generate(players.length, (i) => i)).take(count).toSet();

  @override
  List<String> get players => _game.players;
  @override
  GamePhase get phase => _game.phase;
  @override
  int get leader => _game.leader;
  @override
  int get rejections => _game.rejections;
  @override
  List<int> get team => _game.team;
  @override
  List<bool> get votes => _game.votes;
  @override
  List<QuestResult> get history => _game.history;
  @override
  DiscussionSettings get discussionSettings => _game.discussion;
  @override
  List<ProposalRecord> get proposalHistory =>
      List.unmodifiable(_game.proposals);
  @override
  int? get speaker => _game.speaker;
  @override
  int get speechVersion => _game.speechVersion;
  @override
  int? get speechDeadline => _game.speechDeadline;
  @override
  Future<void> endSpeech(int expectedVersion) =>
      _apply(() => _game.endSpeech(expectedVersion: expectedVersion));
  @override
  String? get winner => _game.winner;
  @override
  String get result => _game.result;
  @override
  int? get assassinTarget => _assassinTarget;
  @override
  int get generation => _generation;

  @override
  Set<int> get confirmedSeats =>
      phase == GamePhase.identity ? _first(_game.actor) : const {};
  @override
  Set<int> get votedSeats =>
      phase == GamePhase.vote ? _first(_game.actor) : const {};
  @override
  Set<int> get playedSeats => switch (phase) {
        GamePhase.quest => _first(_game.actor, team),
        GamePhase.questResult ||
        GamePhase.excalibur ||
        GamePhase.excaliburResult =>
          team.toSet(),
        _ => const {},
      };

  @override
  int? get mySeat => null;
  @override
  int? get handoffSeat => switch (phase) {
        GamePhase.quest => _game.questActor,
        GamePhase.assassination => _game.roles.indexOf(Role.assassin),
        GamePhase.lady || GamePhase.ladyResult => _game.ladyHolder,
        GamePhase.excalibur ||
        GamePhase.excaliburResult =>
          _game.excaliburHolder,
        _ => _game.actor,
      };
  @override
  Role? roleOf(int seat) => _game.roles[seat];
  @override
  String? roleArt(int seat) => _art[seat];
  @override
  String knowledge(int seat) => _game.knowledge(seat);
  @override
  Set<Role> get configuredRoles => _game.roles.toSet();
  @override
  List<int> visiblePlayers(int seat) => visibleSeats(_game.roles, seat);
  @override
  int? knownLancelotSeat(int seat) => knownLancelot(_game.roles, seat);
  @override
  bool get canAdvance => true;
  @override
  bool get canRestart => true;

  @override
  Future<void> confirmIdentity(int seat) => _apply(_game.confirmIdentity);
  @override
  Future<void> proposeTeam(List<int> team, {int? excalibur}) =>
      _apply(() => _game.proposeTeam(team, excalibur: excalibur));
  @override
  Future<void> vote(int seat, bool approve) =>
      _apply(() => _game.vote(approve));
  @override
  Future<void> recordVotes(List<bool> ballots) =>
      _apply(() => _game.recordVotes(ballots));
  @override
  Future<void> continueVote() => _apply(_game.continueVote);
  @override
  Future<void> playQuest(int seat, bool success) =>
      _apply(() => _game.playQuest(success));
  @override
  Future<void> continueQuest() => _apply(_game.continueQuest);
  @override
  Future<void> assassinate(int target) => _apply(() {
        _game.assassinate(target);
        _assassinTarget = target;
      });
  @override
  Future<void> restart() => _apply(_deal);

  @override
  ExpansionSettings get expansions => _game.expansions;
  @override
  List<bool?> get loyalty => List.unmodifiable(_game.loyalty);
  @override
  bool get lancelotSwitched => _game.lancelotSwitched;
  @override
  int? get ladyHolder => _game.ladyHolder;
  @override
  List<int> get ladyPast => List.unmodifiable(_game.ladyPast);
  @override
  List<LadyCheck> get ladyChecks => List.unmodifiable(_game.ladyChecks);
  @override
  int? get excaliburHolder => _game.excaliburHolder;
  @override
  PrivateReveal? get latestReveal => switch (phase) {
        GamePhase.ladyResult => PrivateReveal(
            kind: 'lady',
            quest: history.length,
            target: _game.ladyChecks.last.target,
            evil: _game.ladySawEvil),
        GamePhase.excaliburResult => PrivateReveal(
            kind: 'excalibur',
            quest: questNumber,
            target: _game.excaliburTarget!,
            card: _game.excaliburSawCard),
        _ => null,
      };
  @override
  Future<void> useLady(int target) => _apply(() => _game.useLady(target));
  @override
  Future<void> continueLady() => _apply(_game.continueLady);
  @override
  Future<void> useExcalibur(int? target) =>
      _apply(() => _game.useExcalibur(target));
  @override
  Future<void> continueExcalibur() => _apply(_game.continueExcalibur);
}
