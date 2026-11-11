import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../core/assets.dart';
import '../lobby/room_model.dart';
import 'game_model.dart';

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
  bool get isOnline => mySeat != null;

  /// The seat that has to take the phone for the current secret step
  /// (pass & play only).
  int? get handoffSeat => null;

  /// The role at [seat], if this device is allowed to know it.
  Role? roleOf(int seat);

  /// Card artwork for the role at [seat] (null when unknown here).
  String? roleArt(int seat);

  /// What the player at [seat] learns when they look at their card.
  String knowledge(int seat);

  /// May this device press the shared "continue" buttons?
  bool get canAdvance;

  /// May this device deal a new game once this one is over?
  bool get canRestart;

  // ───────────── moves ─────────────

  Future<void> confirmIdentity(int seat);
  Future<void> proposeTeam(List<int> team);
  Future<void> vote(int seat, bool approve);
  Future<void> continueVote();
  Future<void> playQuest(int seat, bool success);
  Future<void> continueQuest();
  Future<void> assassinate(int target);
  Future<void> restart();

  /// Online only: give up this player's seat (ends a game in progress).
  bool get canLeaveRoom => false;
  Future<void> leaveRoom() async {}
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
        GamePhase.questResult => team.toSet(),
        _ => const {},
      };

  @override
  int? get mySeat => null;
  @override
  int? get handoffSeat => switch (phase) {
        GamePhase.quest => _game.questActor,
        GamePhase.assassination => _game.roles.indexOf(Role.assassin),
        _ => _game.actor,
      };
  @override
  Role? roleOf(int seat) => _game.roles[seat];
  @override
  String? roleArt(int seat) => _art[seat];
  @override
  String knowledge(int seat) => _game.knowledge(seat);
  @override
  bool get canAdvance => true;
  @override
  bool get canRestart => true;

  @override
  Future<void> confirmIdentity(int seat) => _apply(_game.confirmIdentity);
  @override
  Future<void> proposeTeam(List<int> team) =>
      _apply(() => _game.proposeTeam(team));
  @override
  Future<void> vote(int seat, bool approve) =>
      _apply(() => _game.vote(approve));
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
}
