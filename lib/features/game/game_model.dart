import 'dart:math';
import '../lobby/room_model.dart';
import 'discussion_model.dart';
import 'expansion_model.dart';

enum GamePhase {
  identity,
  team,
  discussion,
  freeDiscussion,
  vote,
  voteResult,
  quest,
  questResult,
  lady,
  ladyResult,
  excalibur,
  excaliburResult,
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
  minion('莫德雷德的爪牙', true),
  lancelotGood('正義蘭斯洛特', false),
  lancelotEvil('邪惡蘭斯洛特', true);

  const Role(this.label, this.isEvil);
  final String label;
  final bool isEvil;
  bool get isLancelot => this == lancelotGood || this == lancelotEvil;
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
              // evil Lancelot is known to evil but does not see them
              (role.isEvil &&
                  role != Role.oberon &&
                  role != Role.lancelotEvil &&
                  roles[i].isEvil &&
                  roles[i] != Role.oberon)))
        i
  ];
}

/// Display a seat and nickname consistently in game prompts.
String playerLabel(int seat, String name) => '${seat + 1} 號 【$name】';

class RoleInformation {
  const RoleInformation(this.heading, this.reminder,
      {this.listsPlayers = false});
  final String heading, reminder;
  final bool listsPlayers;
}

/// Shared wording for both the structured card view and plain-text knowledge.
RoleInformation roleInformation(Role role,
    {Set<Role>? configuredRoles, ExpansionSettings? expansions}) {
  bool has(Role candidate) =>
      configuredRoles == null || configuredRoles.contains(candidate);
  if (role == Role.merlin) {
    return RoleInformation('你看見的邪惡玩家', has(Role.mordred) ? '莫德雷德不會被你看見。' : '',
        listsPlayers: true);
  }
  if (role == Role.percival) {
    return has(Role.morgana)
        ? const RoleInformation('梅林候選人', '你無法分辨梅林與莫甘娜。', listsPlayers: true)
        : const RoleInformation('你看見的梅林', '請保護梅林，避免暴露他的身分。',
            listsPlayers: true);
  }
  if (role == Role.lancelotGood) {
    if (expansions?.lancelot == 2) {
      return const RoleInformation(
          '你沒有額外情報。', '你不知道另一位蘭斯洛特是誰。\n依公開的轉換牌換邊，按當前陣營出牌。');
    }
    return const RoleInformation(
        '你沒有額外情報。', '你不知道另一位蘭斯洛特是誰。\n翻出「轉換陣營」時，你會改為邪惡陣營。');
  }
  if (role == Role.lancelotEvil) {
    if (expansions?.lancelot == 2) {
      return const RoleInformation(
          '你屬於邪惡陣營。', '其他邪惡玩家認得你，但你看不到他們。\n依公開的轉換牌換邊，按當前陣營出牌。');
    }
    return const RoleInformation(
        '你屬於邪惡陣營。', '其他邪惡玩家認得你，但你看不到他們。\n翻出「轉換陣營」時，你會改為正義陣營。');
  }
  if (role == Role.oberon) {
    return const RoleInformation('你屬於邪惡陣營。', '你與其他邪惡玩家互不相認。');
  }
  if (role.isEvil) {
    return RoleInformation('你的邪惡同伴', has(Role.oberon) ? '奧伯倫不會出現在此。' : '',
        listsPlayers: true);
  }
  return const RoleInformation('你沒有額外情報。', '透過討論與投票，\n找出值得信任的隊友。');
}

String knowledgeText(Role role, List<int> visible, List<String> players,
    {Set<Role>? configuredRoles, ExpansionSettings? expansions}) {
  final info = roleInformation(role,
      configuredRoles: configuredRoles, expansions: expansions);
  final names = visible.map((i) => playerLabel(i, players[i])).join('、');
  final heading = info.listsPlayers
      ? '${info.heading}：${names.isEmpty ? '無' : names}。'
      : info.heading;
  return info.reminder.isEmpty ? heading : '$heading\n${info.reminder}';
}

class QuestResult {
  QuestResult(List<int> team, this.fails, this.succeeded,
      {this.excaliburHolder, this.excaliburTarget})
      : team = List.unmodifiable(team);
  final List<int> team;
  final int fails;
  final bool succeeded;

  /// Excalibur on this quest: who held it and whose card they flipped.
  final int? excaliburHolder, excaliburTarget;
}

/// One use of the Lady of the Lake (public: everyone sees who was examined).
class LadyCheck {
  const LadyCheck(this.holder, this.target, this.quest);
  final int holder, target, quest;
}

/// All secrets live on this device. Intended for trusted, pass-and-play games.
class AvalonGame {
  AvalonGame(Room room, {Random? random}) {
    if (!room.canStart) throw StateError('玩家或角色尚未準備完成');
    players = List.unmodifiable(room.players.map((p) => p.name));
    discussion = room.discussion;
    expansions = room.expansions;
    final rng = random ?? Random.secure();
    final deck = [
      ...room.specialRoles
          .map((name) => Role.values.firstWhere((r) => r.label == name)),
      if (expansions.lancelot > 0) ...[Role.lancelotGood, Role.lancelotEvil],
    ];
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
    if (expansions.lancelot > 0) {
      // 5 "no change" and 2 "switch" loyalty cards
      _loyaltyDeck.addAll(
          [false, false, false, false, false, true, true]..shuffle(rng));
      if (expansions.lancelot == 2) {
        loyalty.setAll(0, _loyaltyDeck.take(5));
        _loyaltyDeck.clear();
      }
    }
    if (expansions.lady) {
      // the Lady starts with the player on the first leader's right
      ladyHolder = (leader - 1 + players.length) % players.length;
      ladyPast.add(ladyHolder!);
    }
    _beginQuest();
  }

  late final ExpansionSettings expansions;

  /// Lancelot loyalty card on each quest (null: none turned over).
  final List<bool?> loyalty = List.filled(5, null);
  final List<bool> _loyaltyDeck = [];

  /// The Lancelots currently play for the other side.
  bool lancelotSwitched = false;
  int? ladyHolder;

  /// Everyone who has held the Lady (they cannot be examined).
  final List<int> ladyPast = [];
  final List<LadyCheck> ladyChecks = [];

  /// What the last Lady use showed (pass & play: shown to the holder).
  bool? ladySawEvil;

  /// Who holds Excalibur on the current team.
  int? excaliburHolder;

  /// Excalibur's last flip: whose card, and what it was before.
  int? excaliburTarget;
  bool? excaliburSawCard;

  /// The side the player at [seat] plays for right now.
  bool evilNow(int seat) =>
      roles[seat].isEvil != (roles[seat].isLancelot && lancelotSwitched);

  /// Variant 2: a Lancelot on the evil side may only play Fail.
  bool mustFail(int seat) =>
      expansions.lancelot == 2 && roles[seat].isLancelot && evilNow(seat);

  /// A new quest starts: turn over a loyalty card when one is due.
  void _beginQuest() {
    final q = _history.length;
    if (q > 4) return;
    if (expansions.lancelot == 1 && q >= 2 && _loyaltyDeck.isNotEmpty) {
      loyalty[q] = _loyaltyDeck.removeAt(0);
    }
    if (loyalty[q] == true) lancelotSwitched = !lancelotSwitched;
  }

  void _nextQuest() {
    _nextLeader();
    phase = GamePhase.team;
    _beginQuest();
  }

  late final List<String> players;
  late final List<Role> roles;
  late int leader;
  late final DiscussionSettings discussion;
  final List<ProposalRecord> proposals = [];
  int speechIndex = 0;
  int speechVersion = 0;
  int? speechDeadline;
  int? get speaker => phase == GamePhase.discussion
      ? (leader + 1 + speechIndex) % players.length
      : null;
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
      knowledgeText(roles[index], visibleSeats(roles, index), players,
          configuredRoles: roles.toSet(), expansions: expansions);

  void confirmIdentity() {
    _require(GamePhase.identity);
    actor++;
    if (actor == players.length) {
      actor = 0;
      phase = GamePhase.team;
    }
  }

  void proposeTeam(Iterable<int> selected, {int? now, int? excalibur}) {
    _require(GamePhase.team);
    final members = selected.toSet().toList()..sort();
    if (members.length != requiredTeam ||
        members.any((i) => i < 0 || i >= players.length)) {
      throw ArgumentError('隊伍人數不正確');
    }
    if (expansions.excalibur &&
        (excalibur == null ||
            !members.contains(excalibur) ||
            excalibur == leader)) {
      throw ArgumentError('請把王者之劍交給隊長以外的一名隊員');
    }
    excaliburHolder = expansions.excalibur ? excalibur : null;
    _team
      ..clear()
      ..addAll(members);
    _votes.clear();
    actor = 0;
    speechIndex = 0;
    speechVersion++;
    phase = discussion.enabled ? GamePhase.discussion : GamePhase.vote;
    speechDeadline = discussion.enabled
        ? (now ?? DateTime.now().millisecondsSinceEpoch) +
            discussion.speechSeconds * 1000
        : null;
  }

  void endSpeech({int? seat, int? now, required int expectedVersion}) {
    if (speechVersion != expectedVersion ||
        ![GamePhase.discussion, GamePhase.freeDiscussion].contains(phase)) {
      return;
    }
    final time = now ?? DateTime.now().millisecondsSinceEpoch;
    if (phase == GamePhase.freeDiscussion) {
      if (time < speechDeadline!) throw StateError('自由討論尚未結束');
      speechVersion++;
      phase = GamePhase.vote;
      speechDeadline = null;
      return;
    }
    if (time < speechDeadline! && seat != null && seat != speaker) {
      throw StateError('只有目前發言者可以過麥');
    }
    speechVersion++;
    speechIndex++;
    if (speechIndex < players.length) {
      speechDeadline = time + discussion.speechSeconds * 1000;
    } else if (discussion.freeSeconds > 0) {
      phase = GamePhase.freeDiscussion;
      speechDeadline = time + discussion.freeSeconds * 1000;
    } else {
      phase = GamePhase.vote;
      speechDeadline = null;
    }
  }

  void recordVotes(List<bool> ballots) {
    _require(GamePhase.vote);
    if (ballots.length != players.length || actor != 0) {
      throw ArgumentError('請完整登記每位玩家的票型');
    }
    for (final approve in List<bool>.of(ballots)) {
      vote(approve);
    }
  }

  void vote(bool approve) {
    _require(GamePhase.vote);
    _votes.add(approve);
    actor++;
    if (actor == players.length) {
      actor = 0;
      phase = GamePhase.voteResult;
      proposals.add(ProposalRecord(
          quest: questNumber,
          attempt: rejections + 1,
          leader: leader,
          team: _team,
          votes: _votes));
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
    if (!success && !evilNow(questActor)) throw ArgumentError('正義玩家只能出成功');
    if (success && mustFail(questActor)) {
      throw ArgumentError('邪惡方的蘭斯洛特必須出失敗');
    }
    _cards.add(success);
    actor++;
    if (actor == _team.length) {
      actor = 0;
      excaliburTarget = excaliburSawCard = null;
      if (excaliburHolder != null) {
        phase = GamePhase.excalibur;
      } else {
        _resolveQuest();
      }
    }
  }

  void _resolveQuest() {
    final fails = _cards.where((v) => !v).length;
    final succeeded = fails < failsRequired;
    _history.add(QuestResult(_team, fails, succeeded,
        excaliburHolder: excaliburHolder, excaliburTarget: excaliburTarget));
    phase = GamePhase.questResult;
  }

  /// Excalibur: flip one other team member's card ([target] null to pass).
  void useExcalibur(int? target) {
    _require(GamePhase.excalibur);
    if (target == null) return _resolveQuest();
    final index = _team.indexOf(target);
    if (index < 0 || target == excaliburHolder) {
      throw ArgumentError('請選擇另一名隊員');
    }
    excaliburTarget = target;
    excaliburSawCard = _cards[index];
    _cards[index] = !_cards[index];
    phase = GamePhase.excaliburResult;
  }

  void continueExcalibur() {
    _require(GamePhase.excaliburResult);
    _resolveQuest();
  }

  /// Lady of the Lake: the holder examines one player's loyalty.
  void useLady(int target) {
    _require(GamePhase.lady);
    if (target < 0 || target >= players.length) throw ArgumentError('請選擇玩家');
    if (ladyPast.contains(target)) {
      throw ArgumentError('持有過湖中女神的玩家不能被查驗');
    }
    ladyChecks.add(LadyCheck(ladyHolder!, target, _history.length));
    ladySawEvil = evilNow(target);
    phase = GamePhase.ladyResult;
  }

  /// The examined player receives the Lady; the next quest begins.
  void continueLady() {
    _require(GamePhase.ladyResult);
    ladyHolder = ladyChecks.last.target;
    ladyPast.add(ladyHolder!);
    ladySawEvil = null;
    _nextQuest();
  }

  void continueQuest() {
    _require(GamePhase.questResult);
    if (failures == 3) {
      _finish('邪惡', '三次任務失敗，邪惡陣營獲勝。');
    } else if (successes == 3) {
      phase = GamePhase.assassination;
    } else if (ladyHolder != null &&
        const [2, 3, 4].contains(_history.length)) {
      phase = GamePhase.lady;
    } else {
      _nextQuest();
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
    excaliburHolder = null;
  }

  void _finish(String side, String reason) {
    winner = side;
    result = reason;
    phase = GamePhase.finished;
  }
}
