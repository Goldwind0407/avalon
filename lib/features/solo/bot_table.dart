import 'dart:math';
import '../game/discussion_model.dart';
import '../game/expansion_model.dart';
import '../game/game_model.dart';
import '../game/player_speech.dart';
import '../game/speech_statements.dart';
import 'bot_brain.dart';
import 'bot_difficulty.dart';
import 'bot_observation.dart';
import 'bot_style.dart';
import 'bot_vote_plan.dart';
import 'dialogue/bot_contract.dart';
import 'game_review.dart';
import 'memory/match_archive.dart';
import 'memory/social_memory.dart';
import 'persona/bot_persona.dart';

// The computer players of one online table. The referee (Cloud Functions)
// sends everything it knows about the game; this answers with what each
// computer seat does next. It is the solo session's handling of its bots
// (solo_session.dart), without a screen and without a clock: when to ask
// is up to the caller. No Flutter here; the server runs this.

/// Something one seat alone was shown: a Lady result or an Excalibur card.
class TableReveal {
  const TableReveal(
      {required this.seat,
      required this.lady,
      required this.quest,
      required this.target,
      this.evil,
      this.card});
  final int seat, quest, target;
  final bool lady;
  final bool? evil, card;
}

/// Everything the referee knows about a game in progress.
class TableState {
  TableState({
    required this.generation,
    required this.phase,
    required this.roles,
    required this.names,
    required this.leader,
    required this.rejections,
    required this.team,
    required this.history,
    required this.proposals,
    required this.confirmed,
    required this.voted,
    required this.played,
    required this.speechVersion,
    required this.speaker,
    required this.expansions,
    required this.loyalty,
    required this.switched,
    required this.ladyHolder,
    required this.ladyPast,
    required this.ladyChecks,
    required this.excaliburHolder,
    required this.reveals,
    required this.ownCards,
  });

  /// From the referee's state as the Cloud Functions hold it
  /// (functions/src/rules.ts GameState, public and secret parts together).
  /// [cards] is what each seat played on each quest so far:
  /// {seat: {quest: success}}.
  factory TableState.fromServer(Map state,
      {required int generation, required List<String> names, Map? cards}) {
    List<int> ints(Object? v) =>
        [for (final x in v as List? ?? const []) (x as num).toInt()];
    final roles = [
      for (final r in state['roles'] as List) Role.values.byName(r as String)
    ];
    final phase = GamePhase.values.byName(state['phase'] as String);
    final leader = (state['leader'] as num).toInt();
    final expansions = ExpansionSettings.fromMap(
        (state['expansions'] as Map?)?.cast<String, dynamic>());
    return TableState(
        generation: generation,
        phase: phase,
        roles: roles,
        names: names,
        leader: leader,
        rejections: (state['rejections'] as num).toInt(),
        team: ints(state['team']),
        history: [
          for (final q in state['history'] as List? ?? const [])
            QuestResult(
                ints(q['team']), (q['fails'] as num).toInt(), q['succeeded'],
                excaliburHolder: (q['excalibur']?['holder'] as num?)?.toInt(),
                excaliburTarget: (q['excalibur']?['target'] as num?)?.toInt())
        ],
        proposals: [
          for (final p in state['proposals'] as List? ?? const [])
            ProposalRecord.fromMap((p as Map).cast<String, dynamic>())
        ],
        confirmed: ints(state['confirmed']).toSet(),
        voted: ints(state['voted']).toSet(),
        played: ints(state['played']).toSet(),
        speechVersion: (state['speechVersion'] as num?)?.toInt() ?? 0,
        speaker: phase == GamePhase.discussion
            ? (leader + 1 + ((state['speechIndex'] as num?)?.toInt() ?? 0)) %
                roles.length
            : null,
        expansions: expansions,
        loyalty: [
          for (final v in state['loyalty'] as List? ?? const []) v as bool?
        ],
        switched: state['lancelotSwitched'] == true,
        ladyHolder: (state['ladyHolder'] as num?)?.toInt(),
        ladyPast: ints(state['ladyPast']),
        ladyChecks: [
          for (final c in state['ladyChecks'] as List? ?? const [])
            LadyCheck((c['holder'] as num).toInt(),
                (c['target'] as num).toInt(), (c['quest'] as num).toInt())
        ],
        excaliburHolder: (state['excaliburHolder'] as num?)?.toInt(),
        reveals: [
          for (final r in state['reveals'] as List? ?? const [])
            TableReveal(
                seat: (r['seat'] as num).toInt(),
                lady: r['kind'] == 'lady',
                quest: (r['quest'] as num).toInt(),
                target: (r['target'] as num).toInt(),
                evil: r['evil'] as bool?,
                card: r['card'] as bool?)
        ],
        ownCards: {
          for (final e in (cards ?? const {}).entries)
            int.parse('${e.key}'): {
              for (final c in (e.value as Map).entries)
                int.parse('${c.key}'): c.value as bool
            }
        });
  }

  final int generation;
  final GamePhase phase;
  final List<Role> roles;
  final List<String> names;
  final int leader, rejections, speechVersion;
  final List<int> team, ladyPast;
  final List<QuestResult> history;
  final List<ProposalRecord> proposals;
  final Set<int> confirmed, voted, played;
  final int? speaker, ladyHolder, excaliburHolder;
  final ExpansionSettings expansions;
  final List<bool?> loyalty;
  final bool switched;
  final List<LadyCheck> ladyChecks;
  final List<TableReveal> reveals;

  /// What each seat itself played on each quest (1-based).
  final Map<int, Map<int, bool>> ownCards;

  int get count => roles.length;
  int get questNumber => history.length + 1;
  int get requiredTeam => questTeamSize(count, history.length);
  int get failsRequired => count >= 7 && questNumber == 4 ? 2 : 1;
  bool evilNow(int seat) =>
      roles[seat].isEvil != (roles[seat].isLancelot && switched);
}

/// What the computer seats do next: lines to put on the record first, then
/// moves for the referee to check and apply, in this order.
class TableStep {
  /// Statements in their stored form ([statementToMap]), each with
  /// `'bot': true`; a seat's speech for its turn also carries `'sv'`, the
  /// speech version it was said in.
  final say = <Map<String, dynamic>>[];

  /// `{'seat': n, 'move': 'vote', ...}` with the arguments of that move as
  /// the referee names them.
  final moves = <Map<String, dynamic>>[];
  bool get isEmpty => say.isEmpty && moves.isEmpty;
}

class BotTable {
  /// [bots] maps each computer seat to its way of playing.
  BotTable(
      {required Map<int, BotStyle> bots,
      required this.difficulty,
      required int seed})
      : _styles = Map.of(bots),
        _random = Random(seed);
  final Map<int, BotStyle> _styles;

  /// Who the computers play for now. A game may go on while this changes:
  /// a person who goes quiet is played for until they are back. A seat that
  /// stays keeps what it had in mind; a new one starts from the record.
  void seat(Map<int, BotStyle> bots) {
    for (final gone
        in _styles.keys.where((s) => !bots.containsKey(s)).toList()) {
      _styles.remove(gone);
      _brains.remove(gone);
      _plannedVotes.remove(gone);
      _plannedCards.remove(gone);
    }
    for (final MapEntry(key: seat, value: style) in bots.entries) {
      if (_styles[seat] == style) continue;
      _styles[seat] = style;
      _plannedVotes.remove(seat);
      _plannedCards.remove(seat);
      if (_generation != null) _brains[seat] = _brain(style);
    }
  }

  BotBrain _brain(BotStyle style) {
    final seed = _random.nextInt(1 << 30);
    return BotBrain(Random(seed),
        dialogueRandom: Random(seed ^ 0x5a17),
        style: style,
        difficulty: difficulty);
  }

  final BotDifficulty difficulty;
  final Random _random;
  final _brains = <int, BotBrain>{};
  final _plannedVotes = <int, BotVotePlan>{};
  final _plannedCards = <int, bool>{};
  int? _generation;
  String? _proposalKey;

  /// Who the computers have played with before, for the generation that
  /// was given them ([remember]).
  int? _remembered;

  bool isBot(int? seat) => _styles.containsKey(seat);

  void _reset(int generation) {
    _generation = generation;
    _remembered = null;
    _brains.clear();
    _plannedVotes.clear();
    _plannedCards.clear();
    _proposalKey = null;
    for (final seat in _styles.keys) {
      _brains[seat] = _brain(_styles[seat]!);
    }
  }

  /// Hands each computer what it remembers of earlier games in this room
  /// with the people now at the table. [past] are finished games, newest
  /// first, as the referee keeps them: `{players: [{uid, name, bot,
  /// persona}], state, talk}` (the state with every role, as at the end).
  /// [players] are this game's seats in the same form. Once a deal.
  void remember(TableState s, List<Map> players, List<Map> past) {
    if (_remembered == s.generation || past.isEmpty) return;
    _remembered = s.generation;
    // each person: their seat now, and what each computer went through
    // with them, game by game
    final people = <String, int>{
      for (final (seat, p) in players.indexed)
        if (p['bot'] != true && p['uid'] is String) p['uid'] as String: seat
    };
    final seatOfBot = <String, int>{
      for (final (seat, p) in players.indexed)
        if (p['bot'] == true && p['persona'] is String)
          p['persona'] as String: seat
    };
    final memories = <int, Map<int, List<MemoryEntry>>>{};
    for (final (ago, game) in past.indexed) {
      final review = _review(game);
      if (review == null) continue;
      final seats = [for (final p in game['players'] as List) p as Map];
      for (final (botThen, bot) in seats.indexed) {
        final seatNow = seatOfBot[bot['persona']];
        if (bot['bot'] != true || seatNow == null) continue;
        for (final (personThen, person) in seats.indexed) {
          final personNow = people[person['uid']];
          if (person['bot'] == true || personNow == null) continue;
          final kinds = episodesWith(review(personThen), botThen);
          if (kinds.isEmpty) continue;
          ((memories[seatNow] ??= {})[personNow] ??= [])
              .add(MemoryEntry(ago, kinds));
        }
      }
    }
    for (final MapEntry(key: seat, value: byPerson) in memories.entries) {
      // the one this computer has been through the most with
      final person = byPerson.keys
          .reduce((a, b) => byPerson[a]!.length >= byPerson[b]!.length ? a : b);
      _brains[seat]?.voice.memory = BotMemory(person, byPerson[person]!);
    }
  }

  /// What the computer in [seat] remembers of earlier games, if anything.
  BotMemory? memoryOf(int seat) => _brains[seat]?.voice.memory;

  /// A finished game as the referee kept it, seen from any seat; null when
  /// it cannot be read.
  GameReview Function(int seat)? _review(Map game) => finishedGameReview(game);

  /// The record as the computers read it (see [readTableTalk]).
  List<DiscussionStatement> readTalk(TableState s, List<Map> talk,
          {bool any = false}) =>
      readTableTalk(s, talk, any: any);

  // The ONLY input a brain gets: its own seat's view, as in solo play.
  BotObservation _observe(
          TableState s, int seat, List<DiscussionStatement> statements) =>
      BotObservation(
          seat: seat,
          role: s.roles[seat],
          evil: s.evilNow(seat),
          count: s.count,
          leader: s.leader,
          quest: s.questNumber,
          rejections: s.rejections,
          failsRequired: s.failsRequired,
          expansions: s.expansions,
          switched: s.switched,
          visible: visibleSeats(s.roles, seat),
          lancelotSeat: knownLancelot(s.roles, seat),
          team: s.team,
          history: s.history,
          proposals: s.proposals,
          ladyPast: s.ladyPast,
          facts: [
            for (final r in s.reveals)
              if (r.seat == seat)
                BotFact(
                    owner: seat,
                    generation: s.generation,
                    quest: r.quest,
                    target: r.target,
                    switched: _switchedAt(s, r.quest),
                    evil: r.evil,
                    originalCard: r.card)
          ],
          statements: statements,
          ownCards: s.ownCards[seat] ?? const {},
          loyalty: s.loyalty,
          generation: s.generation,
          phase: s.phase,
          configuredRoles: s.roles.toSet(),
          names: s.names,
          ladyChecks: s.ladyChecks,
          excaliburHolder: s.excaliburHolder,
          plannedQuestSuccess: _plannedCards[seat]);

  /// Whether the Lancelots had switched during quest [quest] (1-based).
  bool _switchedAt(TableState s, int quest) {
    final during = switchStates(s.loyalty, quest);
    return during.isEmpty ? false : during.last;
  }

  bool _plannedVote(
      TableState s, int seat, List<DiscussionStatement> statements) {
    final plan = _plannedVotes.putIfAbsent(
        seat, () => BotVotePlan(_random.nextInt(1 << 30)));
    return (plan.current ??
            plan.evaluate(_brains[seat]!, _observe(s, seat, statements)))
        .approve;
  }

  /// Each of [seats] looks at the discussion again; one that has said one
  /// thing and now means to vote the other says so.
  void _reviewVotes(TableState s, Iterable<int> seats,
      List<DiscussionStatement> statements, TableStep out,
      {bool lock = false}) {
    // all of them see the same discussion, before any of them amends
    final views = {
      for (final seat in seats) seat: _observe(s, seat, statements)
    };
    for (final MapEntry(key: seat, value: view) in views.entries) {
      final plan = _plannedVotes.putIfAbsent(
          seat, () => BotVotePlan(_random.nextInt(1 << 30)));
      if (plan.locked) continue;
      final decision = plan.evaluate(_brains[seat]!, view, lock: lock);
      final prior = view.statements
          .where((x) =>
              x.speaker == seat &&
              x.supportsTeam != null &&
              x.quest == view.quest &&
              x.attempt == view.proposalId.attempt)
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
      final name = '${source.$2.speaker + 1}號';
      _say(
          out,
          statements,
          DiscussionStatement(
              generation: s.generation,
              quest: view.quest,
              attempt: view.proposalId.attempt,
              speaker: seat,
              team: s.team,
              supportsTeam: decision.approve,
              switched: s.switched,
              intent: 'reassess',
              replyTo: source.$1,
              evidenceIds: [
                BotEvidenceId(s.generation, BotEvidenceKind.statement,
                        's${source.$1}')
                    .id
              ],
              text: (decision.approve
                  ? [
                      '聽完討論，包括$name的說法，我收回剛才的反對。這隊我願意試。',
                      '$name說的有道理，我改一下：這隊我還是讓它過。',
                      '我想了一下$name的話，剛才的反對收回，這票改投贊成。',
                    ]
                  : [
                      '聽完討論，包括$name的說法，我對這隊沒那麼放心了。剛才說支持，現在改投反對。',
                      '$name提醒得對，我收回剛才的支持，這隊我改投反對。',
                      '聽了$name的話，我覺得這隊有風險，改投反對。',
                    ])[(seat + view.quest + view.proposalId.attempt) % 3]));
    }
  }

  void _say(TableStep out, List<DiscussionStatement> statements,
      DiscussionStatement statement,
      {int? speechVersion}) {
    statements.add(statement);
    out.say.add({
      ...statementToMap(statement),
      'bot': true,
      if (speechVersion != null) 'sv': speechVersion,
    });
  }

  void _move(TableStep out, int seat, String move,
          [Map<String, dynamic> arguments = const {}]) =>
      out.moves.add({'seat': seat, 'move': move, ...arguments});

  /// What a computer Lady holder says it saw (which may be a lie: an evil
  /// holder covers for an evil player and sometimes frames a good one).
  DiscussionStatement _ladyAnnouncement(TableState s, TableReveal reveal) {
    final owner = reveal.seat;
    final lie = s.evilNow(owner) &&
        _random.nextDouble() <
            (reveal.evil! ? .9 : _brains[owner]!.style.frame);
    final claim = reveal.evil! != lie;
    final who = '${reveal.target + 1}號';
    final then = s.expansions.lancelot > 0 ? '當時' : '';
    final side = claim ? '邪惡' : '正義';
    final lines = [
      '我用湖中女神查驗了$who，他$then是$side陣營。',
      '女神我拿去看了$who，結果是$side。',
      '報一下查驗：$who$then是$side陣營。',
      '我查的是$who，看到的是$side，大家參考。',
    ];
    return DiscussionStatement(
        generation: s.generation,
        attempt: s.rejections + 1,
        speaker: owner,
        quest: s.questNumber,
        target: reveal.target,
        claimedEvil: claim,
        switched: s.switched,
        intent: BotSpeechIntent.interpretLady.name,
        certainty: DiscussionCertainty.certain,
        evidenceIds: [_ladyEvidence(s, reveal)],
        text: lines[(owner + reveal.target + reveal.quest) % lines.length]);
  }

  String _ladyEvidence(TableState s, TableReveal reveal) => BotEvidenceId(
          s.generation,
          BotEvidenceKind.ladyUse,
          'q${reveal.quest}/${reveal.seat}/${reveal.target}')
      .id;

  /// What the computer seats do now. [talk] is the record so far, in its
  /// stored form: the computers' own lines, and people's lines as
  /// `{'by': seat, 'q': quest, 'a': attempt, 'g': generation, 'text': ...,
  /// 'team': [...], 'switched': bool}`.
  TableStep step(TableState s, List<Map> talk,
      {List<Map> players = const [], List<Map> past = const []}) {
    if (_generation != s.generation) _reset(s.generation);
    remember(s, players, past);
    final out = TableStep();
    final statements = readTalk(s, talk);
    final bots = _styles.keys.where((seat) => seat < s.count).toList()..sort();

    // A new proposal: what each computer means to vote, and the card each
    // one on the team means to play (talking about it must not change it).
    final planning = [
      GamePhase.discussion,
      GamePhase.freeDiscussion,
      GamePhase.vote
    ].contains(s.phase);
    if (planning) {
      final key = '${s.questNumber}/${s.rejections}/${s.leader}/'
          '${s.team.join(',')}';
      if (_proposalKey != key) {
        _proposalKey = key;
        _plannedVotes.clear();
        _plannedCards.clear();
        for (final seat in bots) {
          _plannedVote(s, seat, statements);
        }
        for (final seat in bots.where(s.team.contains)) {
          _plannedCards[seat] =
              _brains[seat]!.questCard(_observe(s, seat, statements));
        }
      }
    }

    switch (s.phase) {
      case GamePhase.identity:
        for (final seat in bots.where((b) => !s.confirmed.contains(b))) {
          _move(out, seat, 'confirmIdentity');
        }
      case GamePhase.team:
        if (isBot(s.leader)) {
          final view = _observe(s, s.leader, statements);
          final brain = _brains[s.leader]!;
          final picked = brain.chooseTeam(view, s.requiredTeam);
          _move(out, s.leader, 'proposeTeam', {
            'team': picked,
            if (s.expansions.excalibur)
              'excalibur': brain.swordHolder(view, picked),
          });
        }
      case GamePhase.discussion:
        final speaker = s.speaker;
        if (speaker == null || !isBot(speaker)) break;
        final spoken = talk.any((line) =>
            line['bot'] == true &&
            line['by'] == speaker &&
            line['sv'] == s.speechVersion &&
            (line['g'] == null || line['g'] == s.generation));
        if (spoken) {
          _move(
              out, speaker, 'endSpeech', {'expectedVersion': s.speechVersion});
        } else {
          _reviewVotes(s, [speaker], statements, out);
          final statement = _brains[speaker]!.speech(
              _observe(s, speaker, statements),
              _plannedVote(s, speaker, statements));
          _say(out, statements, statement, speechVersion: s.speechVersion);
        }
      case GamePhase.vote:
        final voters = bots.where((b) => !s.voted.contains(b)).toList();
        _reviewVotes(s, voters, statements, out, lock: true);
        for (final seat in voters) {
          final approve = _plannedVote(s, seat, statements);
          final why = _plannedVotes[seat]?.current;
          _move(out, seat, 'vote', {
            'approve': approve,
            // why, for the review once the game is over (kept secret till then)
            if (why != null)
              'why': {
                'reason': why.reason,
                'risk': double.parse(why.risk.toStringAsFixed(3)),
                'doubt': [
                  for (final d in why.suspicion)
                    double.parse(d.toStringAsFixed(3))
                ],
              },
          });
        }
      case GamePhase.voteResult:
        if (isBot(s.leader)) _move(out, s.leader, 'continueVote');
      case GamePhase.quest:
        for (final seat
            in bots.where((b) => s.team.contains(b) && !s.played.contains(b))) {
          _move(out, seat, 'playQuest', {
            'success': _plannedCards[seat] ??
                _brains[seat]!.questCard(_observe(s, seat, statements))
          });
        }
      case GamePhase.questResult:
        if (isBot(s.leader)) _move(out, s.leader, 'continueQuest');
      case GamePhase.lady:
        final holder = s.ladyHolder;
        if (holder != null && isBot(holder)) {
          _move(out, holder, 'useLady', {
            'target':
                _brains[holder]!.ladyTarget(_observe(s, holder, statements))
          });
        }
      case GamePhase.ladyResult:
        final holder = s.ladyHolder;
        if (holder == null || !isBot(holder)) break;
        final reveal =
            s.reveals.where((r) => r.lady && r.seat == holder).lastOrNull;
        if (reveal == null) {
          _move(out, holder, 'continueLady');
          break;
        }
        // first what was seen is announced; the Lady moves on next time
        final evidence = _ladyEvidence(s, reveal);
        if (statements.any(
            (x) => x.speaker == holder && x.evidenceIds.contains(evidence))) {
          _move(out, holder, 'continueLady');
        } else {
          _say(out, statements, _ladyAnnouncement(s, reveal));
        }
      case GamePhase.excalibur:
        final holder = s.excaliburHolder;
        if (holder != null && isBot(holder)) {
          _move(out, holder, 'useExcalibur', {
            'target':
                _brains[holder]!.swordTarget(_observe(s, holder, statements))
          });
        }
      case GamePhase.excaliburResult:
        final holder = s.excaliburHolder;
        if (holder != null && isBot(holder)) {
          _move(out, holder, 'continueExcalibur');
        }
      case GamePhase.assassination:
        final assassin = s.roles.indexOf(Role.assassin);
        if (isBot(assassin)) {
          final view = _observe(s, assassin, statements);
          final brain = _brains[assassin]!;
          final target = brain.assassinate(view);
          _say(out, statements, brain.assassinationSpeech(view, target));
          _move(out, assassin, 'assassinate', {'target': target});
        }
      case GamePhase.freeDiscussion || GamePhase.finished:
        break;
    }
    return out;
  }
}

/// The record as the computers read it: their own lines as stored, and
/// each line a person typed as what it says about whom. [any]: every line,
/// whatever deal it was said in (for a game read back as a whole).
List<DiscussionStatement> readTableTalk(TableState s, List<Map> talk,
    {bool any = false}) {
  final statements = <DiscussionStatement>[];
  for (final line in talk) {
    if (!any && line['g'] != null && line['g'] != s.generation) continue;
    if (line['bot'] == true) {
      statements.add(statementFromMap(line));
      continue;
    }
    final speaker = (line['by'] as num).toInt();
    final quest = (line['q'] as num).toInt();
    final attempt = (line['a'] as num?)?.toInt() ?? 1;
    final text = (line['text'] as String).trim();
    final speech = PlayerSpeech.parse(text, s.names, speaker);
    statements.addAll(statementsFromSpeech(speech, text,
        speaker: speaker,
        generation: s.generation,
        quest: quest,
        attempt: attempt,
        team: [for (final x in line['team'] as List? ?? const []) x as int],
        switched: line['switched'] == true,
        ladyChecks: s.ladyChecks,
        loyalty: s.loyalty,
        questsPlayed: s.history.length));
  }
  return statements;
}

/// A finished online game as the referee keeps it (`{gen, players: [{uid,
/// name, bot, persona}], state, talk}`, the state with every role, card
/// and reason), as a review from any seat; null when it cannot be read.
GameReview Function(int seat)? finishedGameReview(Map game) {
  try {
    final players = [for (final p in game['players'] as List) p as Map];
    final raw = game['state'] as Map;
    final state = TableState.fromServer(raw,
        generation: (game['gen'] as num?)?.toInt() ?? 0,
        names: [for (final p in players) '${p['name']}'],
        cards: raw['cardLog'] as Map?);
    final talk = readTableTalk(
        state,
        [
          for (final line in game['talk'] as List? ?? const [])
            if (line is Map) line
        ],
        any: true);
    // why each computer voted as it did, by proposal
    final decisions = <int, Map<int, BotVoteDecision>>{};
    for (final MapEntry(:key, :value)
        in ((raw['botReasons'] as Map?) ?? const {}).entries) {
      final [proposal, seat] = '$key'.split('/').map(int.parse).toList();
      final why = value as Map;
      (decisions[proposal] ??= {})[seat] = BotVoteDecision(
          why['approve'] == true,
          why['reason'] as String,
          (why['risk'] as num?)?.toDouble() ?? 0, [
        for (final d in why['doubt'] as List? ?? const []) (d as num).toDouble()
      ]);
    }
    final styles = [
      for (final p in players)
        p['bot'] == true
            ? BotPersona.byId(p['persona'] as String?)?.style.label
            : null
    ];
    return (seat) => GameReview.build(
        players: state.names,
        roles: state.roles,
        styles: styles,
        mySeat: seat,
        winner: raw['winner'] as String?,
        result: raw['result'] as String?,
        proposals: state.proposals,
        history: state.history,
        statements: talk,
        sources: const {},
        decisions: decisions,
        cardsBySeat: state.ownCards,
        ladyChecks: state.ladyChecks,
        assassinTarget: (raw['assassinTarget'] as num?)?.toInt(),
        expansions: state.expansions,
        switchedDuring: switchStates(state.loyalty, state.history.length),
        switchedAtEnd: state.switched);
  } catch (_) {
    return null;
  }
}
