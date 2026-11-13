import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../game/discussion_model.dart';
import '../game/expansion_model.dart';
import '../game/game_model.dart';
import '../game/game_session.dart';
import '../game/player_speech.dart';
import '../lobby/room_model.dart';
import 'bot_brain.dart';
import 'bot_difficulty.dart';
import 'bot_observation.dart';
import 'game_review.dart';
import 'bot_style.dart';
import 'bot_vote_plan.dart';
import 'dialogue/bot_contract.dart';

/// Local referee + one private human view. Bots receive only value snapshots.
/// Result screens wait for the human so animations and public evidence can be
/// read before any more decisions are made.
class SoloGameSession extends GameSession {
  SoloGameSession(Room room,
      {Random? random,
      this.difficulty = BotDifficulty.normal,
      this.botDelay = const Duration(milliseconds: 450),
      this.speechDuration = const Duration(seconds: 7)})
      : _random = random ?? Random.secure(),
        _local = LocalGameSession(room, random: random) {
    _resetBots();
    _local.addListener(_changed);
    _schedule();
  }
  final LocalGameSession _local;
  final Random _random;
  final Duration botDelay, speechDuration;

  /// How well every computer player reasons and acts in this game.
  final BotDifficulty difficulty;
  Timer? _botTimer;
  bool _disposed = false, _paused = false;
  int? _pausedSpeechMillis;
  final _brains = <int, BotBrain>{};
  final _facts = <int, List<BotFact>>{};
  final _ownCards = <int, Map<int, bool>>{};
  final _statements = <DiscussionStatement>[];
  final _plannedVotes = <int, BotVotePlan>{};
  final _plannedCards = <int, bool>{};

  // ── kept for the game review (private until the game is over) ──
  final _sources = <int, SpeechSource>{};
  final _decisions = <int, Map<int, BotVoteDecision>>{};
  String? _proposalKey, _speechKey, _currentStatement;
  String? _revealKey;
  Future<void> _saving = Future.value();
  AvalonGame get _rules => _local.game;

  /// Developer inspection only. Never attach this to public statements,
  /// Firebase, the notebook, or a release build's UI.
  Map<int, BotVotePlan> get debugVotePlans =>
      kDebugMode ? Map.unmodifiable(_plannedVotes) : const {};

  void _resetBots() {
    _brains.clear();
    _facts.clear();
    _ownCards.clear();
    final styles = BotStyle.deal(players.length, _random);
    for (var s = 0; s < players.length; s++) {
      final seed = _random.nextInt(1 << 30);
      _brains[s] = BotBrain(Random(seed),
          dialogueRandom: Random(seed ^ 0x5a17),
          style: styles[s],
          difficulty: difficulty);
      _facts[s] = [];
      _ownCards[s] = {};
    }
    _statements.clear();
    _sources.clear();
    _decisions.clear();
    _plannedVotes.clear();
    _plannedCards.clear();
    _proposalKey = _speechKey = _currentStatement = _revealKey = null;
  }

  // This projection is the ONLY input accepted by BotBrain. The hidden role
  // array stays inside the referee; even visible seats carry no role labels.
  BotObservation _observe(int seat) => BotObservation(
      seat: seat,
      role: _rules.roles[seat],
      evil: _rules.evilNow(seat),
      count: players.length,
      leader: leader,
      quest: questNumber,
      rejections: rejections,
      failsRequired: failsRequired,
      expansions: expansions,
      switched: lancelotSwitched,
      visible: visibleSeats(_rules.roles, seat),
      lancelotSeat: knownLancelot(_rules.roles, seat),
      team: team,
      history: history,
      proposals: proposalHistory,
      ladyPast: ladyPast,
      facts: _facts[seat]!,
      statements: _statements,
      ownCards: _ownCards[seat]!,
      loyalty: loyalty,
      generation: generation,
      phase: phase,
      configuredRoles: configuredRoles,
      names: players,
      ladyChecks: ladyChecks,
      excaliburHolder: excaliburHolder,
      plannedQuestSuccess: _plannedCards[seat]);

  void _rememberReveal() {
    final reveal = _local.latestReveal;
    if (reveal == null) return;
    final owner =
        phase == GamePhase.ladyResult ? ladyHolder! : excaliburHolder!;
    final key = '$generation/${reveal.kind}/${reveal.quest}/${reveal.target}';
    if (_revealKey == key) return;
    _revealKey = key;
    _facts[owner]!.add(BotFact(
        owner: owner,
        generation: generation,
        quest: reveal.quest,
        target: reveal.target,
        switched: lancelotSwitched,
        evil: reveal.evil,
        originalCard: reveal.card));
    if (phase == GamePhase.ladyResult && owner != mySeat) {
      // The public statement may be a lie. Only this holder's fact is true.
      // An evil holder covers for an evil player and sometimes frames a
      // good one; they do not give their own side away.
      final lie = _rules.evilNow(owner) &&
          _random.nextDouble() <
              (reveal.evil! ? .9 : _brains[owner]!.style.frame);
      final claim = reveal.evil! != lie;
      _sources[_statements.length] = SpeechSource(
          '湖中女神宣稱（${reveal.evil! ? '實際查到邪惡' : '實際查到正義'}）',
          'lib/features/solo/solo_session.dart 的 _rememberReveal()');
      _statements.add(DiscussionStatement(
          generation: generation,
          attempt: rejections + 1,
          speaker: owner,
          quest: questNumber,
          target: reveal.target,
          claimedEvil: claim,
          switched: lancelotSwitched,
          intent: BotSpeechIntent.interpretLady.name,
          certainty: DiscussionCertainty.certain,
          evidenceIds: [
            BotEvidenceId(generation, BotEvidenceKind.ladyUse,
                    'q${reveal.quest}/$owner/${reveal.target}')
                .id
          ],
          text:
              '我用湖中女神查驗了 ${playerLabel(reveal.target, players[reveal.target])}，'
              '我宣稱他當時是${claim ? '邪惡' : '正義'}陣營。'));
    }
  }

  BotVotePlan _votePlan(int seat) => _plannedVotes.putIfAbsent(
      seat, () => BotVotePlan(_random.nextInt(1 << 30)));

  bool _plannedVote(int seat) {
    final plan = _votePlan(seat);
    return (plan.current ?? plan.evaluate(_brains[seat]!, _observe(seat)))
        .approve;
  }

  void _reviewVotes(Iterable<int> seats, {bool lock = false}) {
    // All final votes see the same public discussion, before any amendments
    // are appended. No partially submitted ballots enter these observations.
    final views = {for (final seat in seats) seat: _observe(seat)};
    for (final entry in views.entries) {
      final seat = entry.key, view = entry.value;
      final plan = _votePlan(seat);
      if (plan.locked) continue;
      final decision = plan.evaluate(_brains[seat]!, view, lock: lock);
      final prior = view.statements
          .where((s) =>
              s.speaker == seat &&
              s.supportsTeam != null &&
              s.quest == view.quest &&
              s.attempt == view.proposalId.attempt)
          .lastOrNull;
      if (prior == null || prior.supportsTeam == decision.approve) continue;
      final source = view.statements.indexed
          .where((e) =>
              e.$2.speaker != seat &&
              e.$2.quest == view.quest &&
              e.$2.attempt == view.proposalId.attempt &&
              (e.$2.position != null ||
                  e.$2.claimedEvil != null ||
                  e.$2.supportsTeam != null))
          .lastOrNull;
      if (source == null) continue;
      final name = playerLabel(source.$2.speaker, players[source.$2.speaker]);
      _sources[_statements.length] = const SpeechSource(
          '改口', 'lib/features/solo/solo_session.dart 的 _reviewVotes()');
      _statements.add(DiscussionStatement(
          generation: generation,
          quest: view.quest,
          attempt: view.proposalId.attempt,
          speaker: seat,
          team: team,
          supportsTeam: decision.approve,
          switched: lancelotSwitched,
          intent: 'reassess',
          replyTo: source.$1,
          evidenceIds: [
            BotEvidenceId(
                    generation, BotEvidenceKind.statement, 's${source.$1}')
                .id
          ],
          text: decision.approve
              ? '聽完討論，包括$name的說法，我收回剛才的反對。這隊我願意試。'
              : '聽完討論，包括$name的說法，我對這隊沒那麼放心了。剛才說支持，現在改投反對。'));
    }
  }

  void _changed() {
    if (_disposed) return;
    _rememberReveal();
    final planning = [
      GamePhase.discussion,
      GamePhase.freeDiscussion,
      GamePhase.vote
    ].contains(phase);
    final proposal = planning
        ? '${_observe(0).proposalId.id}/$leader/${team.join(',')}'
        : null;
    if (proposal != null && _proposalKey != proposal) {
      _proposalKey = proposal;
      _plannedVotes.clear();
      _plannedCards.clear();
      // Initial intentions use private projections, not irrevocable ballots.
      for (var seat = 1; seat < players.length; seat++) {
        _plannedVote(seat);
      }
      // Commit only each participant's own card policy. Speaking about hiding
      // must not randomly change the card once the proposal is approved.
      for (final seat in team.where((s) => s != mySeat)) {
        _plannedCards[seat] = _brains[seat]!.questCard(_observe(seat));
      }
    }
    if (phase == GamePhase.vote) {
      _reviewVotes(Iterable.generate(players.length - 1, (i) => i + 1),
          lock: true);
    }
    // the votes are in: keep why each bot cast its ballot
    final index = proposalHistory.length - 1;
    if (phase == GamePhase.voteResult && !_decisions.containsKey(index)) {
      _decisions[index] = {
        for (final e in _plannedVotes.entries)
          if (e.value.current case final decision?) e.key: decision
      };
    }
    final speech = '$generation/$speechVersion';
    if (phase == GamePhase.discussion && speaker != mySeat) {
      if (_speechKey != speech) {
        _speechKey = speech;
        _reviewVotes([speaker!]);
        final statement = _brains[speaker]!
            .speech(_observe(speaker!), _plannedVote(speaker!));
        _currentStatement = statement.text;
        if (_brains[speaker]!.lastSpeechSource case final source?) {
          _sources[_statements.length] = source;
        }
        _statements.add(statement);
      }
    } else {
      _currentStatement = null;
    }
    final scope = notebookScope;
    final ownRole = roleOf(mySeat!)!;
    final opening = '${ownRole.label}\n${knowledge(mySeat!)}';
    final records = proposalHistory;
    final pages = openingNotesByPlayer(mySeat!);
    _saving = _saving.then((_) async {
      if (!_disposed && notebookScope == scope) {
        await notebook.synchronize(scope,
            opening: opening, proposals: records, openingNotes: pages);
      }
    });
    notifyListeners();
    _schedule();
  }

  /// Used by the table while a rulebook, notebook, or exit dialog is open.
  @override
  void pauseAutomation(bool paused) {
    if (_disposed || _paused == paused) return;
    if (paused && discussing && speechDeadline != null) {
      _pausedSpeechMillis = max(0, speechDeadline! - nowMillis);
    } else if (!paused) {
      if (discussing && _pausedSpeechMillis != null) {
        _rules.speechDeadline = nowMillis + _pausedSpeechMillis!;
      }
      _pausedSpeechMillis = null;
    }
    _paused = paused;
    _botTimer?.cancel();
    _local.refreshSpeechTimer(active: !paused);
    if (!paused) {
      _schedule();
      notifyListeners();
    }
  }

  int? get _botActor => switch (phase) {
        GamePhase.identity || GamePhase.vote => _rules.actor,
        GamePhase.team => leader,
        GamePhase.discussion => speaker,
        GamePhase.quest => _rules.questActor,
        GamePhase.lady || GamePhase.ladyResult => ladyHolder,
        GamePhase.excalibur || GamePhase.excaliburResult => excaliburHolder,
        GamePhase.assassination => _rules.roles.indexOf(Role.assassin),
        _ => null,
      };

  /// Long enough to read the speech: [speechDuration] at least, plus about a
  /// fifth of a second per character past 25, up to twice as long.
  Duration _readingTime(String? text) {
    final extra = max(0, (text?.length ?? 0) - 25) * 200;
    final base = speechDuration.inMilliseconds;
    return Duration(milliseconds: min(base * 2, base + extra));
  }

  void _schedule() {
    _botTimer?.cancel();
    if (_disposed || _paused) return;
    final actor = _botActor;
    if (actor == null || actor == mySeat) return;
    final deal = generation, version = speechVersion, stage = phase;
    final delay = phase == GamePhase.discussion
        ? _readingTime(_currentStatement)
        : botDelay;
    _botTimer = Timer(delay, () async {
      if (_disposed ||
          _paused ||
          generation != deal ||
          phase != stage ||
          speechVersion != version ||
          _botActor != actor) {
        return;
      }
      final view = _observe(actor), brain = _brains[actor]!;
      switch (phase) {
        case GamePhase.identity:
          await _local.confirmIdentity(actor);
        case GamePhase.team:
          final picked = brain.chooseTeam(view, requiredTeam);
          await _local.proposeTeam(picked,
              excalibur: expansions.excalibur
                  ? brain.swordHolder(view, picked)
                  : null);
        case GamePhase.discussion:
          await _local.endSpeech(version);
        case GamePhase.vote:
          await _local.vote(actor, _plannedVote(actor));
        case GamePhase.quest:
          final card = _plannedCards[actor] ?? brain.questCard(view);
          _ownCards[actor]![questNumber] = card;
          await _local.playQuest(actor, card);
        case GamePhase.lady:
          await _local.useLady(brain.ladyTarget(view));
        case GamePhase.ladyResult:
          await _local.continueLady();
        case GamePhase.excalibur:
          await _local.useExcalibur(brain.swordTarget(view));
        case GamePhase.excaliburResult:
          await _local.continueExcalibur();
        case GamePhase.assassination:
          final target = brain.assassinate(view);
          final announcement = brain.assassinationSpeech(view, target);
          await _local.assassinate(target);
          if (!_disposed && generation == deal) {
            _sources[_statements.length] =
                SpeechSource.catalog(brain.dialogue.lastTrace?.ruleId);
            _statements.add(announcement);
            notifyListeners();
          }
        default:
          break;
      }
    });
  }

  void _requireHuman(GamePhase expected) {
    if (_disposed || phase != expected || _botActor != mySeat) {
      throw const GameMoveException('請等待輪到你再操作');
    }
  }

  @override
  Future<void> confirmIdentity(int seat) {
    _requireHuman(GamePhase.identity);
    if (seat != mySeat) throw const GameMoveException('只能確認自己的身分');
    return _local.confirmIdentity(seat);
  }

  @override
  Future<void> proposeTeam(List<int> team, {int? excalibur}) {
    _requireHuman(GamePhase.team);
    return _local.proposeTeam(team, excalibur: excalibur);
  }

  @override
  Future<void> vote(int seat, bool approve) {
    _requireHuman(GamePhase.vote);
    if (seat != mySeat) throw const GameMoveException('只能投自己的票');
    return _local.vote(seat, approve);
  }

  @override
  Future<void> playQuest(int seat, bool success) {
    _requireHuman(GamePhase.quest);
    if (seat != mySeat) throw const GameMoveException('只能出自己的任務牌');
    if ((!success && !evilNow(seat)!) || (success && mustFail(seat))) {
      throw const GameMoveException('這張任務牌不符合目前陣營規則');
    }
    _ownCards[seat]![questNumber] = success;
    return _local.playQuest(seat, success);
  }

  @override
  Future<void> useLady(int target) {
    _requireHuman(GamePhase.lady);
    return _local.useLady(target);
  }

  @override
  Future<void> continueLady() {
    _requireHuman(GamePhase.ladyResult);
    return _local.continueLady();
  }

  @override
  Future<void> useExcalibur(int? target) {
    _requireHuman(GamePhase.excalibur);
    return _local.useExcalibur(target);
  }

  @override
  Future<void> continueExcalibur() {
    _requireHuman(GamePhase.excaliburResult);
    return _local.continueExcalibur();
  }

  @override
  Future<void> assassinate(int target) {
    _requireHuman(GamePhase.assassination);
    return _local.assassinate(target);
  }

  @override
  Future<void> continueVote() => _local.continueVote();
  @override
  Future<void> continueQuest() => _local.continueQuest();
  @override
  Future<void> endSpeech(int expectedVersion) =>
      _local.endSpeech(expectedVersion);
  @override
  Future<void> expressOpinion(bool approve) async {
    _requireHuman(GamePhase.discussion);
    _statements.add(DiscussionStatement(
        generation: generation,
        attempt: rejections + 1,
        speaker: mySeat!,
        quest: questNumber,
        supportsTeam: approve,
        switched: lancelotSwitched,
        intent: approve
            ? BotSpeechIntent.supportTeam.name
            : BotSpeechIntent.opposeTeam.name,
        team: team,
        text: approve ? '我目前支持這次隊伍提案。' : '我對這隊有疑慮，想換個組合。'));
    await endSpeech(speechVersion);
  }

  @override
  Future<void> say(PlayerSpeech speech) async {
    _requireHuman(GamePhase.discussion);
    final me = mySeat!;
    final t = speech.target;
    if (speech.needsTarget &&
        (t == null || t < 0 || t == me || t >= players.length)) {
      throw const GameMoveException('請選擇另一位玩家');
    }
    String who(int seat) => playerLabel(seat, players[seat]);
    final ballot = speech.kind == PlayerSpeechKind.challengeVote
        ? proposalHistory.lastOrNull
        : null;
    if (speech.kind == PlayerSpeechKind.challengeVote && ballot == null) {
      throw const GameMoveException('還沒有公開的投票紀錄，可以先詢問立場');
    }
    final typed = speech.text?.trim();
    final text = typed != null && typed.isNotEmpty
        ? typed
        : switch (speech.kind) {
            PlayerSpeechKind.support => '我支持這隊。',
            PlayerSpeechKind.oppose => '這隊我想換人。',
            PlayerSpeechKind.suspect => '我懷疑${who(t!)}。',
            PlayerSpeechKind.trust => '我相信${who(t!)}是好人。',
            PlayerSpeechKind.ask => '${who(t!)}，你怎麼看？說說你的理由。',
            PlayerSpeechKind.challengeVote =>
              '${who(t!)}，第${ballot!.quest}次遠征的第${ballot.attempt}次提案，你投${ballot.votes[t] ? '贊成' : '反對'}的理由是什麼？',
            PlayerSpeechKind.claimGood => '我是好人，請相信我。',
            PlayerSpeechKind.remark => '',
          };
    if (text.isEmpty) return;
    _statements.add(DiscussionStatement(
        generation: generation,
        attempt: rejections + 1,
        speaker: me,
        quest: questNumber,
        switched: lancelotSwitched,
        team: team,
        text: text,
        supportsTeam: switch (speech.kind) {
          PlayerSpeechKind.support => true,
          PlayerSpeechKind.oppose => false,
          _ => null,
        },
        intent: switch (speech.kind) {
          PlayerSpeechKind.support => BotSpeechIntent.supportTeam.name,
          PlayerSpeechKind.oppose => BotSpeechIntent.opposeTeam.name,
          PlayerSpeechKind.suspect => BotSpeechIntent.accuse.name,
          PlayerSpeechKind.trust => BotSpeechIntent.defendOther.name,
          PlayerSpeechKind.ask => BotSpeechIntent.questionTeam.name,
          PlayerSpeechKind.challengeVote => BotSpeechIntent.challengeVote.name,
          PlayerSpeechKind.claimGood => BotSpeechIntent.defendSelf.name,
          PlayerSpeechKind.remark => 'opinion',
        },
        target: switch (speech.kind) {
          PlayerSpeechKind.claimGood => me,
          _ => t,
        },
        position: switch (speech.kind) {
          PlayerSpeechKind.suspect => DiscussionPosition.suspect,
          PlayerSpeechKind.trust => DiscussionPosition.defend,
          _ => null,
        },
        evidenceIds: [
          if (ballot != null)
            BotEvidenceId(generation, BotEvidenceKind.ballot,
                    'q${ballot.quest}/a${ballot.attempt}')
                .id
        ],
        questionTo: [PlayerSpeechKind.ask, PlayerSpeechKind.challengeVote]
                .contains(speech.kind)
            ? t
            : null));
    notifyListeners();
  }

  @override
  Future<void> restart() async {
    _botTimer?.cancel();
    _local.removeListener(_changed);
    await _local.restart();
    _resetBots();
    _local.addListener(_changed);
    _changed();
  }

  @override
  bool get isSolo => true;

  /// The whole game with roles and the bots' reasons; only once it is over.
  GameReview? get review => phase != GamePhase.finished
      ? null
      : GameReview.build(
          players: players,
          roles: _rules.roles,
          styles: [for (var s = 0; s < players.length; s++) seatStyle(s)],
          mySeat: mySeat!,
          winner: winner,
          result: result,
          proposals: proposalHistory,
          history: history,
          statements: _statements,
          sources: Map.unmodifiable(_sources),
          decisions: Map.unmodifiable(_decisions),
          cardsBySeat: Map.unmodifiable(_ownCards),
          ladyChecks: ladyChecks,
          assassinTarget: assassinTarget,
          expansions: expansions);

  /// How each computer player liked to play; shown once the game is over.
  @override
  String? seatStyle(int seat) => seat == mySeat || phase != GamePhase.finished
      ? null
      : _brains[seat]?.style.label;
  @override
  int? get mySeat => 0;
  @override
  bool get hasPrivateInput => _botActor == mySeat;
  @override
  bool get canAdvance => true;
  @override
  bool get canRestart => true;
  @override
  String get notebookScope => 'solo/${identityHashCode(this)}/$generation';
  @override
  List<String> get players => _local.players;
  @override
  List<String> get playerIds => _local.playerIds;
  @override
  GamePhase get phase => _local.phase;
  @override
  int get leader => _local.leader;
  @override
  int get generation => _local.generation;
  @override
  int get rejections => _local.rejections;
  @override
  List<int> get team => _local.team;
  @override
  List<bool> get votes => _local.votes;
  @override
  List<QuestResult> get history => _local.history;
  @override
  String? get winner => _local.winner;
  @override
  String get result => _local.result;
  @override
  int? get assassinTarget => _local.assassinTarget;
  @override
  Set<int> get confirmedSeats => _local.confirmedSeats;
  @override
  Set<int> get votedSeats => _local.votedSeats;
  @override
  Set<int> get playedSeats => _local.playedSeats;
  @override
  DiscussionSettings get discussionSettings => _local.discussionSettings;
  @override
  List<ProposalRecord> get proposalHistory => _local.proposalHistory;
  @override
  int? get speaker => _local.speaker;
  @override
  int get speechVersion => _local.speechVersion;
  @override
  int? get speechDeadline => _local.speechDeadline;
  @override
  List<DiscussionStatement> get statements => List.unmodifiable(_statements);
  @override
  String? get currentStatement => _currentStatement;
  @override
  Set<Role> get configuredRoles => _local.configuredRoles;
  @override
  Role? roleOf(int seat) => seat == mySeat || phase == GamePhase.finished
      ? _local.roleOf(seat)
      : null;
  @override
  String? roleArt(int seat) =>
      roleOf(seat) == null ? null : _local.roleArt(seat);
  @override
  String knowledge(int seat) => seat == mySeat ? _local.knowledge(seat) : '';
  @override
  List<int> visiblePlayers(int seat) =>
      seat == mySeat ? _local.visiblePlayers(seat) : const [];
  @override
  int? knownLancelotSeat(int seat) =>
      seat == mySeat ? _local.knownLancelotSeat(seat) : null;
  @override
  ExpansionSettings get expansions => _local.expansions;
  @override
  List<bool?> get loyalty => _local.loyalty;
  @override
  bool get lancelotSwitched => _local.lancelotSwitched;
  @override
  int? get ladyHolder => _local.ladyHolder;
  @override
  List<int> get ladyPast => _local.ladyPast;
  @override
  List<LadyCheck> get ladyChecks => _local.ladyChecks;
  @override
  int? get excaliburHolder => _local.excaliburHolder;
  @override
  PrivateReveal? get latestReveal =>
      (phase == GamePhase.ladyResult && ladyHolder == mySeat) ||
              (phase == GamePhase.excaliburResult && excaliburHolder == mySeat)
          ? _local.latestReveal
          : null;
  @override
  void dispose() {
    _disposed = true;
    _botTimer?.cancel();
    _local.removeListener(_changed);
    _local.dispose();
    super.dispose();
  }
}
