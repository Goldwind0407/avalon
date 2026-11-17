import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_difficulty.dart';
import 'package:avalon_shadow_council/features/solo/bot_service.dart';
import 'package:avalon_shadow_council/features/solo/bot_style.dart';
import 'package:avalon_shadow_council/features/solo/bot_table.dart';
import 'package:avalon_shadow_council/features/solo/memory/social_memory.dart';

/// A referee (the pass-and-play rules) with a [BotTable] playing some of
/// the seats, the way the online referee and the computers' server do.
class Harness {
  Harness(int count,
      {required Set<int> humans,
      ExpansionSettings expansions = const ExpansionSettings(),
      Set<String> extras = const {},
      bool talk = true,
      int seed = 1,
      BotDifficulty level = BotDifficulty.normal})
      : _humans = humans {
    final room = Room(
        code: '123456',
        players: List.generate(
            count, (i) => Player(id: '$i', name: '玩家${i + 1}', isReady: true)))
      ..specialRoles.addAll(['梅林', '刺客', ...extras])
      ..expansions = expansions
      ..discussion =
          talk ? DiscussionSettings.recommended : const DiscussionSettings();
    game = AvalonGame(room, random: Random(seed));
    final styles = BotStyle.deal(count, Random(seed));
    table = BotTable(bots: {
      for (var s = 0; s < count; s++)
        if (!humans.contains(s)) s: styles[s]
    }, difficulty: level, seed: seed);
  }
  final Set<int> _humans;
  late final AvalonGame game;
  late final BotTable table;
  final talk = <Map<String, dynamic>>[];
  final reveals = <TableReveal>[];
  final cards = <int, Map<int, bool>>{};
  final spoke = <String, int>{};
  var steps = 0;

  TableState get state => TableState(
      generation: 1,
      phase: game.phase,
      roles: game.roles,
      names: game.players,
      leader: game.leader,
      rejections: game.rejections,
      team: game.team,
      history: game.history,
      proposals: game.proposals,
      confirmed: game.phase == GamePhase.identity
          ? {for (var s = 0; s < game.actor; s++) s}
          : {for (var s = 0; s < game.players.length; s++) s},
      voted: game.phase == GamePhase.vote
          ? {for (var s = 0; s < game.actor; s++) s}
          : {},
      played: game.phase == GamePhase.quest
          ? game.team.take(game.actor).toSet()
          : {},
      speechVersion: game.speechVersion,
      speaker: game.speaker,
      expansions: game.expansions,
      loyalty: game.loyalty,
      switched: game.lancelotSwitched,
      ladyHolder: game.ladyHolder,
      ladyPast: game.ladyPast,
      ladyChecks: game.ladyChecks,
      excaliburHolder: game.excaliburHolder,
      reveals: reveals,
      ownCards: cards);

  /// What a person in [seat] does when the game waits for them.
  Map<String, dynamic>? human(int seat) {
    final g = game;
    switch (g.phase) {
      case GamePhase.identity:
        return {'move': 'confirmIdentity'};
      case GamePhase.team:
        if (seat != g.leader) return null;
        final team = [
          seat,
          for (var s = 0; s < g.players.length; s++)
            if (s != seat) s
        ].take(g.requiredTeam).toList();
        return {'move': 'proposeTeam', 'team': team, 'excalibur': team[1]};
      case GamePhase.discussion:
        if (seat != g.speaker) return null;
        final said = talk.any((l) =>
            l['by'] == seat && l['bot'] != true && l['sv'] == g.speechVersion);
        if (said) {
          return {'move': 'endSpeech', 'expectedVersion': g.speechVersion};
        }
        // typed lines, as a person would write them
        final other = (seat + 2) % g.players.length + 1;
        talk.add({
          'by': seat,
          'q': g.questNumber,
          'a': g.rejections + 1,
          'g': 1,
          'sv': g.speechVersion,
          'team': g.team,
          'switched': g.lancelotSwitched,
          'text': [
            '我覺得$other號有點可疑，這隊我反對',
            '這隊我可以接受，支持。',
            '$other號，你怎麼看？'
          ][talk.where((l) => l['bot'] != true).length % 3],
        });
        return null;
      case GamePhase.vote:
        return {'move': 'vote', 'approve': true};
      case GamePhase.quest:
        if (!g.team.contains(seat)) return null;
        return {'move': 'playQuest', 'success': !g.evilNow(seat)};
      case GamePhase.lady:
        if (seat != g.ladyHolder) return null;
        return {
          'move': 'useLady',
          'target': [
            for (var s = 0; s < g.players.length; s++)
              if (!g.ladyPast.contains(s)) s
          ].first
        };
      case GamePhase.ladyResult:
        return seat == g.ladyHolder ? {'move': 'continueLady'} : null;
      case GamePhase.excalibur:
        return seat == g.excaliburHolder
            ? {'move': 'useExcalibur', 'target': null}
            : null;
      case GamePhase.excaliburResult:
        return seat == g.excaliburHolder ? {'move': 'continueExcalibur'} : null;
      case GamePhase.voteResult:
        return seat == g.leader ? {'move': 'continueVote'} : null;
      case GamePhase.questResult:
        return seat == g.leader ? {'move': 'continueQuest'} : null;
      case GamePhase.assassination:
        return g.roles[seat] == Role.assassin
            ? {'move': 'assassinate', 'target': (seat + 1) % g.players.length}
            : null;
      default:
        return null;
    }
  }

  /// One round: the computers answer, the people act, the referee applies
  /// what the rules allow (and throws on anything they do not).
  void round() {
    steps++;
    final g = game;
    // through JSON, as it travels between the referee and the server
    final step = table
        .step(state, [for (final l in talk) jsonDecode(jsonEncode(l)) as Map]);
    for (final line in step.say) {
      expect(_humans.contains(line['by']), isFalse);
      expect((line['text'] as String).trim(), isNotEmpty);
      if (line['sv'] != null) {
        final key = '${line['by']}/${line['sv']}';
        spoke[key] = (spoke[key] ?? 0) + 1;
      }
      talk.add(jsonDecode(jsonEncode(line)) as Map<String, dynamic>);
    }
    final moves = <int, Map<String, dynamic>>{
      for (final m in step.moves) m['seat'] as int: m
    };
    expect(moves.keys.any(_humans.contains), isFalse);
    for (final seat in _humans) {
      final move = human(seat);
      if (move != null) moves[seat] = move;
    }
    Map<String, dynamic>? of(int seat, String kind) =>
        moves[seat]?['move'] == kind ? moves[seat] : null;
    switch (g.phase) {
      case GamePhase.identity:
        while (g.phase == GamePhase.identity &&
            of(g.actor, 'confirmIdentity') != null) {
          g.confirmIdentity();
        }
      case GamePhase.team:
        final m = of(g.leader, 'proposeTeam');
        if (m != null) {
          g.proposeTeam(List<int>.from(m['team'] as List),
              now: 0,
              excalibur: g.expansions.excalibur ? m['excalibur'] as int : null);
        }
      case GamePhase.discussion:
        final m = of(g.speaker!, 'endSpeech');
        if (m != null) {
          g.endSpeech(
              seat: g.speaker, now: 0, expectedVersion: m['expectedVersion']);
        }
      case GamePhase.vote:
        // everyone's vote is in hand before any is counted
        if (List.generate(g.players.length, (s) => s)
            .every((s) => of(s, 'vote') != null)) {
          for (var s = 0; s < g.players.length; s++) {
            g.vote(moves[s]!['approve'] as bool);
          }
        }
      case GamePhase.voteResult:
        if (of(g.leader, 'continueVote') != null) g.continueVote();
      case GamePhase.quest:
        if (g.team.every((s) => of(s, 'playQuest') != null)) {
          for (final s in g.team) {
            final card = moves[s]!['success'] as bool;
            (cards[s] ??= {})[g.questNumber] = card;
            g.playQuest(card);
          }
        }
      case GamePhase.questResult:
        if (of(g.leader, 'continueQuest') != null) g.continueQuest();
      case GamePhase.lady:
        final holder = g.ladyHolder!;
        final m = of(holder, 'useLady');
        if (m != null) {
          g.useLady(m['target'] as int);
          reveals.add(TableReveal(
              seat: holder,
              lady: true,
              quest: g.history.length,
              target: m['target'] as int,
              evil: g.ladySawEvil));
        }
      case GamePhase.ladyResult:
        if (of(g.ladyHolder!, 'continueLady') != null) g.continueLady();
      case GamePhase.excalibur:
        final holder = g.excaliburHolder!;
        final m = of(holder, 'useExcalibur');
        if (m != null) {
          final target = m['target'] as int?;
          g.useExcalibur(target);
          if (target != null) {
            reveals.add(TableReveal(
                seat: holder,
                lady: false,
                quest: g.questNumber,
                target: target,
                card: g.excaliburSawCard));
          }
        }
      case GamePhase.excaliburResult:
        if (of(g.excaliburHolder!, 'continueExcalibur') != null) {
          g.continueExcalibur();
        }
      case GamePhase.assassination:
        final assassin = g.roles.indexOf(Role.assassin);
        final m = of(assassin, 'assassinate');
        if (m != null) g.assassinate(m['target'] as int);
      default:
        break;
    }
  }

  void play() {
    while (game.phase != GamePhase.finished) {
      if (steps > 3000) fail('stuck in ${game.phase}');
      round();
    }
  }
}

void main() {
  const setups = [
    (5, ExpansionSettings(), <String>{}),
    (6, ExpansionSettings(lady: true), {'派西維爾', '莫甘娜'}),
    (
      7,
      ExpansionSettings(lady: true, lancelot: 1, excalibur: true),
      {'派西維爾', '莫甘娜'}
    ),
    (8, ExpansionSettings(lancelot: 2, excalibur: true), {'派西維爾', '莫甘娜'}),
    (9, ExpansionSettings(lady: true, excalibur: true), {'派西維爾', '莫甘娜', '奧伯倫'}),
    (10, ExpansionSettings(lady: true, lancelot: 2), {'派西維爾', '莫甘娜', '莫德雷德'}),
  ];

  test('a table of computers plays whole games by the rules', () {
    for (final (count, expansions, extras) in setups) {
      for (var seed = 1; seed <= 6; seed++) {
        final h = Harness(count,
            humans: {},
            expansions: expansions,
            extras: extras,
            talk: seed.isOdd,
            seed: seed * 17 + count,
            level: BotDifficulty.values[seed % 3]);
        h.play();
        expect(h.game.winner, isNotNull, reason: '$count players, seed $seed');
        // a computer speaks once in its turn, never twice
        expect(h.spoke.values.every((n) => n == 1), isTrue);
        if (seed.isOdd) expect(h.spoke, isNotEmpty);
      }
    }
  });

  test('people and computers at one table: typed lines are read', () {
    for (final (count, expansions, extras) in setups) {
      for (var seed = 1; seed <= 4; seed++) {
        final humans = {0, if (seed.isEven) count - 1, if (seed > 2) 2};
        final h = Harness(count,
            humans: humans,
            expansions: expansions,
            extras: extras,
            seed: seed * 29 + count);
        h.play();
        expect(h.game.winner, isNotNull, reason: '$count players, seed $seed');
        // what the people typed reaches the computers as statements
        final read = h.table.readTalk(h.state, h.talk);
        expect(
            read.where((s) => humans.contains(s.speaker) && s.target != null),
            isNotEmpty,
            reason: '$count players, seed $seed: '
                '${[
              for (final l in h.talk)
                if (l['bot'] != true) l['text']
            ]}');
        expect(
            read
                .where((s) => humans.contains(s.speaker))
                .every((s) => s.intent != null),
            isTrue);
      }
    }
  });

  test('a person who goes away is played for, and takes the seat back', () {
    for (var seed = 1; seed <= 6; seed++) {
      final humans = {0, 3};
      final h = Harness(7,
          humans: humans,
          expansions: const ExpansionSettings(lady: true, excalibur: true),
          extras: {'派西維爾', '莫甘娜'},
          seed: seed * 13);
      final styles = BotStyle.deal(7, Random(seed));
      Map<int, BotStyle> seats() => {
            for (var s = 0; s < 7; s++)
              if (!humans.contains(s)) s: styles[s]
          };
      var changes = 0;
      while (h.game.phase != GamePhase.finished) {
        if (h.steps > 3000) fail('stuck in ${h.game.phase}');
        // seat 3 comes and goes every so often, whatever the game is at
        if (h.steps % 23 == 11) {
          humans.contains(3) ? humans.remove(3) : humans.add(3);
          h.table.seat(seats());
          changes++;
        }
        h.round();
      }
      expect(h.game.winner, isNotNull, reason: 'seed $seed');
      expect(changes, greaterThan(1));
      // while away, seat 3 was spoken for; back at the table, it was not
      expect(h.talk.where((l) => l['by'] == 3 && l['bot'] == true), isNotEmpty);
    }
  });

  test('the same answer is not needed twice: a turn already spoken ends', () {
    final h = Harness(5, humans: {}, seed: 3);
    while (h.game.phase != GamePhase.discussion) {
      h.round();
    }
    final speaker = h.game.speaker!;
    final first = h.table.step(h.state, h.talk);
    expect(first.say.single['by'], speaker);
    expect(first.moves, isEmpty);
    h.talk.addAll(first.say);
    final second = h.table.step(h.state, h.talk);
    expect(second.say, isEmpty);
    expect(second.moves.single['move'], 'endSpeech');
    // a table that has lost its memory (the server restarted) goes by the
    // record: it does not speak again in the same turn
    final fresh = BotTable(
        bots: {for (var s = 0; s < 5; s++) s: BotStyle.balanced},
        difficulty: BotDifficulty.normal,
        seed: 99);
    expect(fresh.step(h.state, h.talk).moves.single['move'], 'endSpeech');
  });

  test('the referee\'s own state is read as sent', () {
    final state = TableState.fromServer(jsonDecode('''{
      "phase": "ladyResult", "leader": 3, "rejections": 1, "team": [1, 3],
      "confirmed": [0,1,2,3,4], "voted": [], "votes": null, "played": [],
      "history": [
        {"team": [0, 1], "fails": 1, "succeeded": false, "order": [true, false],
         "excalibur": {"holder": 1, "target": 0}},
        {"team": [1, 2, 3], "fails": 0, "succeeded": true, "order": [true, true, true],
         "excalibur": null}
      ],
      "proposals": [{"quest": 1, "attempt": 1, "leader": 0, "team": [0, 1],
        "votes": [true, true, true, false, false], "approved": true}],
      "speechIndex": 2, "speechVersion": 9, "speechDeadline": null,
      "expansions": {"lady": true, "lancelot": 0, "excalibur": true},
      "loyalty": [null, null, null, null, null], "lancelotSwitched": false,
      "ladyHolder": 4, "ladyPast": [4], "ladyChecks": [{"holder": 4, "target": 2, "quest": 2}],
      "excaliburHolder": null,
      "roles": ["merlin", "assassin", "loyal", "percival", "morgana"],
      "pendingVotes": {}, "pendingCards": {},
      "reveals": [{"seat": 1, "kind": "excalibur", "quest": 1, "target": 0, "card": true},
                  {"seat": 4, "kind": "lady", "quest": 2, "target": 2, "evil": false}]
    }''') as Map, generation: 4, names: [
      '甲',
      '乙',
      '丙',
      '丁',
      '戊'
    ], cards: {
      '1': {'1': false, '2': true}
    });
    expect(state.phase, GamePhase.ladyResult);
    expect(state.roles[4], Role.morgana);
    expect(state.history.first.excaliburTarget, 0);
    expect(state.history.last.succeeded, isTrue);
    expect(state.proposals.single.votes[3], isFalse);
    expect(state.ladyChecks.single.target, 2);
    expect(state.reveals.last.evil, isFalse);
    expect(state.reveals.first.card, isTrue);
    expect(state.ownCards[1], {1: false, 2: true});
    expect(state.speaker, isNull);
    // Morgana's computer announces what the Lady showed, then passes it on
    final table = BotTable(
        bots: {4: BotStyle.actor}, difficulty: BotDifficulty.normal, seed: 1);
    final said = table.step(state, const []);
    expect(said.say.single['by'], 4);
    expect(said.say.single['to'], 2);
    expect(said.moves, isEmpty);
    expect(table.step(state, said.say).moves.single['move'], 'continueLady');
  });

  test('the service keeps a table per game and refuses what it cannot read',
      () {
    final service = BotService(keep: const Duration(hours: 1));
    final h = Harness(5, humans: {0}, seed: 5);
    while (h.game.phase != GamePhase.vote) {
      h.round();
    }
    Map<String, dynamic> request({int gen = 1, String room = '123456'}) => {
          'room': room,
          'gen': gen,
          'seed': 7,
          'level': 'expert',
          'players': [
            for (var s = 0; s < 5; s++)
              {'name': '玩家${s + 1}', 'bot': s != 0, 'persona': 'kai'}
          ],
          'state': {
            'phase': 'vote',
            'leader': h.game.leader,
            'rejections': 0,
            'team': h.game.team,
            'voted': [0],
            'roles': [for (final r in h.game.roles) r.name],
            'history': [],
            'proposals': [],
            'speechVersion': h.game.speechVersion,
          },
          'talk': h.talk,
        };
    final start = DateTime(2026, 11, 17, 12);
    final answer = service.step(request(), now: start);
    expect([for (final m in answer['moves'] as List) m['seat']], [1, 2, 3, 4]);
    expect((answer['moves'] as List).every((m) => m['move'] == 'vote'), isTrue);
    expect(service.tables, 1);
    service.step(request(gen: 2), now: start);
    service.step(request(room: '654321'), now: start);
    expect(service.tables, 3);
    // tables nobody asks about are forgotten
    service.step(request(),
        now: start.add(const Duration(hours: 1, minutes: 1)));
    expect(service.tables, 1);
    // no computers at the table: nothing to do
    final people = request()
      ..['players'] = [
        for (var s = 0; s < 5; s++) {'name': '玩家$s', 'bot': false}
      ];
    expect(service.step(people)['moves'], isEmpty);
    expect(() => service.step(request()..remove('seed')),
        throwsA(isA<BotRequestError>()));
    expect(() => service.step(request()..['level'] = 'godlike'),
        throwsA(isA<BotRequestError>()));
    expect(() => service.step(request()..['players'] = []),
        throwsA(isA<BotRequestError>()));
  });

  test('computers remember earlier games in the room with the people now there',
      () {
    // a finished game: seat 0 a person, the rest computers
    final h = Harness(5, humans: {0}, seed: 21);
    h.play();
    final g = h.game;
    Map<String, dynamic> player(int seat, {String? uid}) => seat == 0
        ? {'uid': uid ?? 'alice', 'name': '小明', 'bot': false}
        : {
            'uid': 'bot:p$seat',
            'name': '電腦$seat',
            'bot': true,
            'persona': ['chen', 'yu', 'zhe', 'mia'][seat - 1]
          };
    final finished = jsonDecode(jsonEncode({
      'gen': 1,
      'players': [for (var s = 0; s < 5; s++) player(s)],
      'state': {
        'phase': 'finished',
        'leader': g.leader,
        'rejections': g.rejections,
        'team': g.team,
        'history': [
          for (final q in g.history)
            {'team': q.team, 'fails': q.fails, 'succeeded': q.succeeded}
        ],
        'proposals': [for (final p in g.proposals) p.toMap()],
        'roles': [for (final r in g.roles) r.name],
        'winner': g.winner,
        'result': g.result,
        'cardLog': {
          for (final e in h.cards.entries)
            '${e.key}': {for (final c in e.value.entries) '${c.key}': c.value}
        },
      },
      'talk': h.talk,
    })) as Map;
    // the next deal in the same room: the same people and computers
    final next = Harness(5, humans: {0}, seed: 22);
    final table = next.table;
    final players = [for (var s = 0; s < 5; s++) player(s)];
    table.step(next.state, const [], players: players, past: [finished]);
    final memories = [for (var s = 1; s < 5; s++) table.memoryOf(s)];
    expect(memories.whereType<Object>(), isNotEmpty,
        reason: 'someone remembers a whole game together');
    for (final m in memories.whereType<BotMemory>()) {
      expect(m.humanSeat, 0);
      expect(m.entries.single.ago, 0);
      expect(m.entries.single.kinds, isNotEmpty);
    }
    // someone else in the person's seat now: nobody is remembered
    final stranger = Harness(5, humans: {0}, seed: 23);
    stranger.table.step(stranger.state, const [],
        players: [player(0, uid: 'bob'), for (var s = 1; s < 5; s++) player(s)],
        past: [finished]);
    expect([for (var s = 1; s < 5; s++) stranger.table.memoryOf(s)],
        everyElement(isNull));
    // an unreadable game is passed over
    final odd = Harness(5, humans: {0}, seed: 24);
    odd.table.step(odd.state, const [],
        players: players,
        past: [
          {'players': players, 'state': 'nonsense'}
        ]);
    expect([for (var s = 1; s < 5; s++) odd.table.memoryOf(s)],
        everyElement(isNull));
  });
}
