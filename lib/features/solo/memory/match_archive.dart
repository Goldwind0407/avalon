import '../../game/discussion_model.dart';
import '../../game/expansion_model.dart';
import '../../game/game_model.dart';
import '../bot_brain.dart';
import '../bot_vote_plan.dart';
import '../game_review.dart';
import 'player_model.dart';

/// Something that happened between the player and one computer player in a
/// finished game. Every kind can be checked against that game's record.
enum EpisodeKind {
  /// The player was evil, this bot voted or led them onto a quest, the
  /// player played Fail and the quest failed.
  fooled,

  /// The player was evil and this bot voted or led them onto a quest, but
  /// the quest did not fail by the player's hand.
  letYouThrough,

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

  /// The (good) player voted or led this evil bot onto a quest, the bot
  /// played Fail and the quest failed.
  usedYou,

  /// The (good) player voted or led this evil bot onto a quest, and the
  /// bot did not fail it.
  slippedPastYou,

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
      required Map<String, List<EpisodeKind>> episodes,
      Map<String, int>? traits})
      : episodes = Map.unmodifiable(episodes),
        traits = traits == null ? null : Map.unmodifiable(traits);
  final String id;
  final DateTime endedAt;
  final int players;
  final Role myRole;
  final bool won;
  final String winner, difficulty;

  /// Persona id → what happened between that bot and the player.
  final Map<String, List<EpisodeKind>> episodes;

  /// What the game showed about how the player plays ([playerTraits]);
  /// null for a game saved before these were counted.
  final Map<String, int>? traits;

  /// The same summary with [traits] counted from the full record.
  MatchSummary withTraits(Map<String, int> traits) => MatchSummary(
      id: id,
      endedAt: endedAt,
      players: players,
      myRole: myRole,
      won: won,
      winner: winner,
      difficulty: difficulty,
      episodes: episodes,
      traits: traits);

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
        if (traits != null) 'traits': traits,
      };

  factory MatchSummary.fromMap(Map<String, dynamic> m) => MatchSummary(
      id: m['id'] as String,
      endedAt: DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
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
      },
      traits: m['traits'] == null
          ? null
          : {
              for (final e in (m['traits'] as Map).entries)
                e.key as String: (e.value as num).toInt()
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
      },
      traits: playerTraits(review));

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
///
/// Every side is the one played at the time (a Lancelot may switch), and
/// blame for a quest goes by the cards: a Fail flipped in by Excalibur, or
/// a quest that survives one Fail, is not "the quest failed in your hands".
List<EpisodeKind> episodesWith(GameReview r, int seat) {
  final me = r.mySeat;
  final kinds = <EpisodeKind>{};
  for (final q in r.quests) {
    final result = q.result;
    final iEvil = r.evilIn(me, q.number), botEvil = r.evilIn(seat, q.number);
    for (final round in q.proposals) {
      final p = round.record;
      // the fifth proposal goes whatever anyone votes; its leader still chose
      bool backed(int s) => p.leader == s || (p.attempt < 5 && p.votes[s]);
      if (result != null && p.approved) {
        if (iEvil && !botEvil && p.team.contains(me) && backed(seat)) {
          kinds.add(!result.succeeded && q.cards[me] == false
              ? EpisodeKind.fooled
              : EpisodeKind.letYouThrough);
        }
        if (botEvil && !iEvil && p.team.contains(seat) && backed(me)) {
          kinds.add(!result.succeeded && q.cards[seat] == false
              ? EpisodeKind.usedYou
              : EpisodeKind.slippedPastYou);
        }
      }
      for (final line in round.lines) {
        final s = line.statement;
        final iThen = r.evilIn(me, s.quest), botThen = r.evilIn(seat, s.quest);
        if (s.position == DiscussionPosition.suspect) {
          if (s.speaker == seat && s.target == me) {
            // two evil players pointing at each other is theatre
            if (!(iThen && botThen)) {
              kinds.add(botThen
                  ? EpisodeKind.framed
                  : iThen
                      ? EpisodeKind.sawThrough
                      : EpisodeKind.wronged);
            }
          }
          if (s.speaker == me && s.target == seat) {
            kinds.add(
                botThen ? EpisodeKind.caughtByYou : EpisodeKind.accusedByYou);
          }
        } else if (s.position == DiscussionPosition.defend &&
            s.speaker == me &&
            s.target == seat &&
            botThen &&
            !iThen) {
          kinds.add(EpisodeKind.trustedByYou);
        }
      }
    }
  }
  // a stronger memory of the same game makes the weaker one redundant
  if (kinds.contains(EpisodeKind.fooled)) {
    kinds.remove(EpisodeKind.letYouThrough);
  }
  if (kinds.contains(EpisodeKind.usedYou)) {
    kinds.remove(EpisodeKind.slippedPastYou);
  }
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
    // who won goes by the side each played for at the end
    final iEvil = r.evil(me), botEvil = r.evil(seat);
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

/// Every field of a statement, so a reopened review reads exactly as the
/// one shown at the end of the game. Missing keys (older saves) read back
/// as the field's default.
Map<String, dynamic> _line(ReviewLine l) {
  final s = l.statement;
  return {
    'by': s.speaker,
    'q': s.quest,
    if (s.generation != null) 'g': s.generation,
    if (s.attempt != null) 'a': s.attempt,
    'text': s.text,
    if (s.target != null) 'to': s.target,
    if (s.claimedEvil != null) 'evil': s.claimedEvil,
    if (s.switched != null) 'switched': s.switched,
    if (s.position != null) 'pos': s.position!.name,
    if (s.certainty != DiscussionCertainty.tentative) 'sure': s.certainty.name,
    if (s.supportsTeam != null) 'for': s.supportsTeam,
    if (s.team.isNotEmpty) 'team': s.team,
    if (s.intent != null) 'intent': s.intent,
    if (s.topic != null) 'topic': s.topic,
    if (s.questionTo != null) 'ask': s.questionTo,
    if (s.replyTo != null) 'reply': s.replyTo,
    if (s.quotedFrom != null) 'quote': s.quotedFrom,
    if (s.claimedOriginalSuccess != null) 'cardOk': s.claimedOriginalSuccess,
    if (s.originalCardQuest != null) 'cardQ': s.originalCardQuest,
    if (s.claimsOpeningKnowledge) 'opening': true,
    if (s.continues) 'cont': true,
    if (s.evidenceIds.isNotEmpty) 'ev': s.evidenceIds,
    if (l.source != null) 'src': [l.source!.label, l.source!.where],
  };
}

ReviewLine _lineFrom(Map m) => ReviewLine(
    DiscussionStatement(
        speaker: (m['by'] as num).toInt(),
        quest: (m['q'] as num).toInt(),
        generation: (m['g'] as num?)?.toInt(),
        attempt: (m['a'] as num?)?.toInt(),
        text: m['text'] as String,
        target: (m['to'] as num?)?.toInt(),
        claimedEvil: m['evil'] as bool?,
        switched: m['switched'] as bool?,
        position: m['pos'] == null
            ? null
            : DiscussionPosition.values.byName(m['pos'] as String),
        certainty: m['sure'] == null
            ? DiscussionCertainty.tentative
            : DiscussionCertainty.values.byName(m['sure'] as String),
        supportsTeam: m['for'] as bool?,
        team: [
          for (final s in m['team'] as List? ?? const []) (s as num).toInt()
        ],
        intent: m['intent'] as String?,
        topic: m['topic'] as String?,
        questionTo: (m['ask'] as num?)?.toInt(),
        replyTo: (m['reply'] as num?)?.toInt(),
        quotedFrom: (m['quote'] as num?)?.toInt(),
        claimedOriginalSuccess: m['cardOk'] as bool?,
        originalCardQuest: (m['cardQ'] as num?)?.toInt(),
        claimsOpeningKnowledge: m['opening'] == true,
        continues: m['cont'] == true,
        evidenceIds: [
          for (final e in m['ev'] as List? ?? const []) e as String
        ]),
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
      if (r.expansions.lancelot > 0) 'switches': r.switchedDuring,
      if (r.switchedAtEnd) 'switchedEnd': true,
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
    switchedDuring: [
      for (final x in m['switches'] as List? ?? const []) x == true
    ],
    switchedAtEnd: m['switchedEnd'] == true,
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
