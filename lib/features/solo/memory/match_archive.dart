import '../../game/discussion_model.dart';
import '../../game/expansion_model.dart';
import '../../game/game_model.dart';
import '../bot_brain.dart';
import '../bot_vote_plan.dart';
import '../game_review.dart';

/// Something that happened between the player and one computer player in a
/// finished game. Every kind can be checked against that game's record.
enum EpisodeKind {
  /// The player was evil and this bot voted or led them onto a failed quest.
  fooled,

  /// The player was evil and this (good) bot said so.
  sawThrough,

  /// Both were good and this bot accused the player.
  wronged,

  /// This bot was evil and pointed the table at the (good) player.
  framed,

  /// The player accused this bot, who was good.
  accusedByYou,

  /// The player accused this bot, who was evil.
  caughtByYou,

  /// The player vouched for this bot, who was evil.
  trustedByYou,

  /// The (good) player voted or led this evil bot onto a failed quest.
  usedYou,

  /// This bot, the Assassin, found the player as Merlin.
  stabbedYou,

  /// This bot, the Assassin, took the player for Merlin and was wrong.
  mistookYou,

  /// The player, the Assassin, found this bot as Merlin.
  stabbedByYou,

  /// The player, the Assassin, took this bot for Merlin and was wrong.
  dodgedYou,
  wonTogether,
  lostTogether,
  beatYou,
  lostToYou;

  /// Worth bringing up on its own, not just "we won last time".
  bool get personal => index < EpisodeKind.wonTogether.index;
}

/// What the list of past games shows, and all that memory needs. Kept apart
/// from the full record so reading it stays cheap.
class MatchSummary {
  MatchSummary(
      {required this.id,
      required this.endedAt,
      required this.players,
      required this.myRole,
      required this.won,
      required this.winner,
      required this.difficulty,
      required Map<String, List<EpisodeKind>> episodes})
      : episodes = Map.unmodifiable(episodes);
  final String id;
  final DateTime endedAt;
  final int players;
  final Role myRole;
  final bool won;
  final String winner, difficulty;

  /// Persona id → what happened between that bot and the player.
  final Map<String, List<EpisodeKind>> episodes;

  Map<String, dynamic> toMap() => {
        'id': id,
        'at': endedAt.millisecondsSinceEpoch,
        'n': players,
        'role': myRole.name,
        'won': won,
        'winner': winner,
        'level': difficulty,
        'episodes': {
          for (final e in episodes.entries)
            e.key: [for (final k in e.value) k.name]
        },
      };

  factory MatchSummary.fromMap(Map<String, dynamic> m) => MatchSummary(
          id: m['id'] as String,
          endedAt:
              DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
          players: (m['n'] as num).toInt(),
          myRole: Role.values.byName(m['role'] as String),
          won: m['won'] == true,
          winner: m['winner'] as String? ?? '',
          difficulty: m['level'] as String? ?? '',
          episodes: {
            for (final e in (m['episodes'] as Map? ?? const {}).entries)
              e.key as String: [
                for (final k in e.value as List)
                  // a kind this version does not know is simply forgotten
                  ...EpisodeKind.values.where((v) => v.name == k)
              ]
          });
}

/// One finished solo game: the full review plus who sat where.
class MatchArchive {
  MatchArchive(
      {required this.id,
      required this.endedAt,
      required this.difficulty,
      required List<String?> personas,
      required this.review})
      : personas = List.unmodifiable(personas);
  static const schemaVersion = 1;
  final String id;
  final DateTime endedAt;
  final String difficulty;

  /// Persona id by seat; null for the player and for unnamed bots.
  final List<String?> personas;
  final GameReview review;

  MatchSummary get summary => MatchSummary(
          id: id,
          endedAt: endedAt,
          players: review.players.length,
          myRole: review.roles[review.mySeat],
          won: review.iWon,
          winner: review.winner ?? '',
          difficulty: difficulty,
          episodes: {
            for (final (seat, persona) in personas.indexed)
              if (persona != null && seat != review.mySeat)
                persona: episodesWith(review, seat)
          });

  Map<String, dynamic> toMap() => {
        'v': schemaVersion,
        'id': id,
        'at': endedAt.millisecondsSinceEpoch,
        'level': difficulty,
        'personas': personas,
        'review': reviewToMap(review),
      };

  /// Null when the data was written by a newer or unknown format.
  static MatchArchive? fromMap(Map<String, dynamic> m) {
    if (m['v'] != schemaVersion) return null;
    return MatchArchive(
        id: m['id'] as String,
        endedAt: DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
        difficulty: m['level'] as String? ?? '',
        personas: [for (final p in m['personas'] as List) p as String?],
        review: reviewFromMap(Map<String, dynamic>.from(m['review'] as Map)));
  }
}

/// What happened between the player and the bot in [seat], read off the
/// finished game. Order: the most telling first.
List<EpisodeKind> episodesWith(GameReview r, int seat) {
  final me = r.mySeat;
  final iEvil = r.evil(me), botEvil = r.evil(seat);
  final kinds = <EpisodeKind>{};
  bool failed(ReviewQuest q) => q.result != null && q.result!.fails > 0;
  var botSuspectedMe = false, iSuspectedBot = false, iBackedBot = false;
  for (final q in r.quests) {
    for (final round in q.proposals) {
      final p = round.record;
      final went = p.approved && p.attempt < 5 && failed(q);
      if (went && p.team.contains(me) && iEvil && !botEvil) {
        if (p.votes[seat] || p.leader == seat) kinds.add(EpisodeKind.fooled);
      }
      if (went && p.team.contains(seat) && botEvil && !iEvil) {
        if (p.votes[me] || p.leader == me) kinds.add(EpisodeKind.usedYou);
      }
      for (final line in round.lines) {
        final s = line.statement;
        if (s.position == DiscussionPosition.suspect) {
          if (s.speaker == seat && s.target == me) botSuspectedMe = true;
          if (s.speaker == me && s.target == seat) iSuspectedBot = true;
        } else if (s.position == DiscussionPosition.defend &&
            s.speaker == me &&
            s.target == seat) {
          iBackedBot = true;
        }
      }
    }
  }
  if (botSuspectedMe) {
    kinds.add(iEvil
        ? (botEvil ? EpisodeKind.framed : EpisodeKind.sawThrough)
        : (botEvil ? EpisodeKind.framed : EpisodeKind.wronged));
    // two evil players pointing at each other is theatre, not a memory
    if (iEvil && botEvil) kinds.remove(EpisodeKind.framed);
  }
  if (iSuspectedBot) {
    kinds.add(botEvil ? EpisodeKind.caughtByYou : EpisodeKind.accusedByYou);
  }
  if (iBackedBot && botEvil && !iEvil) kinds.add(EpisodeKind.trustedByYou);
  final stab = r.assassinTarget;
  if (stab != null) {
    if (r.roles[seat] == Role.assassin && stab == me) {
      kinds.add(r.roles[me] == Role.merlin
          ? EpisodeKind.stabbedYou
          : EpisodeKind.mistookYou);
    }
    if (r.roles[me] == Role.assassin && stab == seat) {
      kinds.add(r.roles[seat] == Role.merlin
          ? EpisodeKind.stabbedByYou
          : EpisodeKind.dodgedYou);
    }
  }
  if (r.winner != null) {
    final botWon = (r.winner == '邪惡') == botEvil;
    kinds.add(iEvil == botEvil
        ? (botWon ? EpisodeKind.wonTogether : EpisodeKind.lostTogether)
        : (botWon ? EpisodeKind.beatYou : EpisodeKind.lostToYou));
  }
  return kinds.toList()..sort((a, b) => a.index.compareTo(b.index));
}

// ── the review as plain data ──

Map<String, dynamic> _quest(QuestResult q) => {
      'team': q.team,
      'fails': q.fails,
      'ok': q.succeeded,
      if (q.excaliburHolder != null) 'swordBy': q.excaliburHolder,
      if (q.excaliburTarget != null) 'swordOn': q.excaliburTarget,
    };

QuestResult _questFrom(Map m) => QuestResult(
    [for (final s in m['team'] as List) (s as num).toInt()],
    (m['fails'] as num).toInt(),
    m['ok'] == true,
    excaliburHolder: (m['swordBy'] as num?)?.toInt(),
    excaliburTarget: (m['swordOn'] as num?)?.toInt());

Map<String, dynamic> _line(ReviewLine l) {
  final s = l.statement;
  return {
    'by': s.speaker,
    'q': s.quest,
    if (s.attempt != null) 'a': s.attempt,
    'text': s.text,
    if (s.target != null) 'to': s.target,
    if (s.position != null) 'pos': s.position!.name,
    if (s.supportsTeam != null) 'for': s.supportsTeam,
    if (s.intent != null) 'intent': s.intent,
    if (s.topic != null) 'topic': s.topic,
    if (s.questionTo != null) 'ask': s.questionTo,
    if (l.source != null) 'src': [l.source!.label, l.source!.where],
  };
}

ReviewLine _lineFrom(Map m) => ReviewLine(
    DiscussionStatement(
        speaker: (m['by'] as num).toInt(),
        quest: (m['q'] as num).toInt(),
        attempt: (m['a'] as num?)?.toInt(),
        text: m['text'] as String,
        target: (m['to'] as num?)?.toInt(),
        position: m['pos'] == null
            ? null
            : DiscussionPosition.values.byName(m['pos'] as String),
        supportsTeam: m['for'] as bool?,
        intent: m['intent'] as String?,
        topic: m['topic'] as String?,
        questionTo: (m['ask'] as num?)?.toInt()),
    m['src'] == null
        ? null
        : SpeechSource(
            (m['src'] as List)[0] as String, (m['src'] as List)[1] as String));

Map<String, dynamic> reviewToMap(GameReview r) => {
      'players': r.players,
      'roles': [for (final role in r.roles) role.name],
      'styles': r.styles,
      'me': r.mySeat,
      'winner': r.winner,
      'result': r.result,
      'stab': r.assassinTarget,
      'expansions': r.expansions.toMap(),
      'lady': [
        for (final c in r.ladyChecks) [c.holder, c.target, c.quest]
      ],
      'end': [for (final l in r.endLines) _line(l)],
      'quests': [
        for (final q in r.quests)
          {
            'n': q.number,
            if (q.result != null) 'result': _quest(q.result!),
            'cards': {
              for (final e in q.cards.entries) '${e.key}': e.value,
            },
            'proposals': [
              for (final p in q.proposals)
                {
                  'record': p.record.toMap(),
                  'lines': [for (final l in p.lines) _line(l)],
                  'why': {
                    for (final e in p.decisions.entries)
                      '${e.key}': {
                        'yes': e.value.approve,
                        'reason': e.value.reason,
                        'risk': e.value.risk,
                        'doubt': e.value.suspicion,
                      }
                  },
                }
            ],
          }
      ],
    };

GameReview reviewFromMap(Map<String, dynamic> m) => GameReview(
    players: [for (final p in m['players'] as List) p as String],
    roles: [
      for (final r in m['roles'] as List) Role.values.byName(r as String)
    ],
    styles: [for (final s in m['styles'] as List) s as String?],
    mySeat: (m['me'] as num).toInt(),
    winner: m['winner'] as String?,
    result: m['result'] as String?,
    assassinTarget: (m['stab'] as num?)?.toInt(),
    expansions: ExpansionSettings.fromMap(
        Map<String, dynamic>.from(m['expansions'] as Map)),
    ladyChecks: [
      for (final c in m['lady'] as List)
        LadyCheck(((c as List)[0] as num).toInt(), (c[1] as num).toInt(),
            (c[2] as num).toInt())
    ],
    endLines: [for (final l in m['end'] as List) _lineFrom(l as Map)],
    quests: [
      for (final q in m['quests'] as List)
        ReviewQuest(
            ((q as Map)['n'] as num).toInt(),
            [
              for (final p in q['proposals'] as List)
                ReviewProposal(
                    ProposalRecord.fromMap(
                        Map<String, dynamic>.from((p as Map)['record'] as Map)),
                    [
                      for (final l in p['lines'] as List) _lineFrom(l as Map)
                    ],
                    {
                      for (final e in (p['why'] as Map).entries)
                        int.parse(e.key as String): BotVoteDecision(
                            (e.value as Map)['yes'] == true,
                            e.value['reason'] as String,
                            (e.value['risk'] as num).toDouble(), [
                          for (final d in e.value['doubt'] as List)
                            (d as num).toDouble()
                        ])
                    })
            ],
            q['result'] == null ? null : _questFrom(q['result'] as Map),
            {
              for (final e in (q['cards'] as Map).entries)
                int.parse(e.key as String): e.value as bool
            })
    ]);
