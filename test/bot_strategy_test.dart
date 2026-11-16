import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/solo/bot_brain.dart';
import 'package:avalon_shadow_council/features/solo/bot_observation.dart';
import 'package:avalon_shadow_council/features/solo/bot_style.dart';
import 'support/bot_dialogue_fixtures.dart';

/// How many of 300 differently seeded bots do [act].
double share(bool Function(BotBrain) act) {
  var n = 0;
  for (var seed = 0; seed < 300; seed++) {
    if (act(BotBrain(Random(seed)))) n++;
  }
  return n / 300;
}

void main() {
  group('a lone evil player on the first quest', () {
    BotObservation first(int count, List<int> team) => observe(
        role: Role.minion,
        evil: true,
        count: count,
        visible: [count - 1],
        leader: 0,
        phase: GamePhase.quest,
        team: team);

    test('usually lies low at a small table', () {
      expect(share((b) => b.questCard(first(5, [0, 1]))), greaterThan(.65));
      expect(share((b) => b.questCard(first(7, [0, 1]))), greaterThan(.65));
    });

    test('holds back less at a large one', () {
      final small = share((b) => b.questCard(first(7, [0, 1, 2])));
      final large = share((b) => b.questCard(first(10, [0, 1, 2])));
      expect(large, lessThan(small - .15));
    });

    test('later he mostly plays Fail', () {
      final later = observe(
          role: Role.minion,
          evil: true,
          visible: [6],
          leader: 0,
          phase: GamePhase.quest,
          team: [0, 1, 2],
          history: [
            QuestResult([3, 4], 0, true)
          ]);
      expect(share((b) => b.questCard(later)), lessThan(.35));
    });
  });

  group('an evil player alone with Excalibur', () {
    // seat 2 sat on a quest that the ally in seat 6 failed; seat 1 has a
    // clean record
    final o = observe(
        role: Role.minion,
        evil: true,
        // seven players: both of his allies are known to him
        visible: [5, 6],
        leader: 3,
        phase: GamePhase.quest,
        team: [0, 1, 2],
        expansions: const ExpansionSettings(excalibur: true),
        excaliburHolder: 0,
        history: [
          QuestResult([1, 4], 0, true),
          QuestResult([2, 6], 1, false)
        ]);

    test('plays Success himself', () {
      expect(share((b) => b.questCard(o)), 1);
    });

    test('and turns over the card of the member the table doubts', () {
      final played = BotObservation(
          seat: o.seat,
          role: o.role,
          evil: true,
          count: o.count,
          leader: o.leader,
          quest: o.quest,
          rejections: 0,
          failsRequired: 1,
          expansions: o.expansions,
          switched: false,
          visible: o.visible,
          team: o.team,
          history: o.history,
          proposals: const [],
          ladyPast: const [],
          facts: const [],
          statements: const [],
          ownCards: {o.quest: true},
          excaliburHolder: 0,
          phase: GamePhase.excalibur);
      for (var seed = 0; seed < 30; seed++) {
        expect(BotBrain(Random(seed)).swordTarget(played), 2);
      }
    });

    test('with an ally on the team he leaves the cards alone', () {
      final withAlly = observe(
          role: Role.minion,
          evil: true,
          visible: [1],
          leader: 3,
          phase: GamePhase.quest,
          team: [0, 1, 2],
          expansions: const ExpansionSettings(excalibur: true),
          excaliburHolder: 0,
          history: [
            QuestResult([3, 4], 0, true)
          ]);
      // seat order decides who sabotages: the first ally plays the Fail
      expect(share((b) => b.questCard(withAlly)), 0);
    });
  });

  test('the evil Lancelot keeps a clean record before the switch cards', () {
    BotObservation lancelot(int variant) => observe(
        role: Role.lancelotEvil,
        evil: true,
        leader: 1,
        phase: GamePhase.quest,
        team: [0, 1, 2],
        expansions: ExpansionSettings(lancelot: variant),
        history: [
          QuestResult([3, 4], 0, true)
        ]);
    final early = share((b) => b.questCard(lancelot(1)));
    expect(early, greaterThan(.55));
    // from the third quest on he sabotages like anyone else
    final late = observe(
        role: Role.lancelotEvil,
        evil: true,
        leader: 1,
        phase: GamePhase.quest,
        team: [0, 1, 2],
        expansions: const ExpansionSettings(lancelot: 1),
        loyalty: const [null, null, false, null, null],
        history: [
          QuestResult([3, 4], 0, true),
          QuestResult([3, 4, 5], 0, true)
        ]);
    expect(share((b) => b.questCard(late)), lessThan(early - .3));
  });

  test('a leader always backs the team he picked', () {
    for (final (role, evil, visible) in [
      (Role.merlin, false, [5, 6]),
      (Role.minion, true, [6]),
      (Role.loyal, false, <int>[]),
    ]) {
      final o = observe(
          role: role,
          evil: evil,
          visible: visible,
          seat: 0,
          leader: 0,
          phase: GamePhase.vote,
          team: [
            0,
            6,
            2
          ],
          history: [
            QuestResult([3, 4], 0, true)
          ]);
      expect(share((b) => b.vote(o)), 1, reason: '$role');
    }
  });

  test('a leader does not send again the team just turned down', () {
    final rejected = ProposalRecord(
        quest: 2,
        attempt: 1,
        leader: 6,
        team: [1, 2, 3],
        votes: [false, true, true, false, false, false, false]);
    final o = observe(
        seat: 0,
        leader: 0,
        rejections: 1,
        phase: GamePhase.team,
        history: [
          QuestResult([1, 2], 0, true)
        ],
        proposals: [
          rejected
        ]);
    for (var seed = 0; seed < 50; seed++) {
      expect(BotBrain(Random(seed)).chooseTeam(o, 3), isNot([1, 2, 3]));
    }
  });

  test('a leader leaves out the player the table keeps turning down', () {
    // seat 1 sat on both rejected teams; most of the table voted against
    ProposalRecord rejected(int attempt, int leader, List<int> team) =>
        ProposalRecord(
            quest: 2,
            attempt: attempt,
            leader: leader,
            team: team,
            votes: [
              for (var s = 0; s < 7; s++) team.contains(s) && s == leader
            ]);
    final o = observe(
        seat: 0,
        leader: 0,
        rejections: 2,
        phase: GamePhase.team,
        history: [
          QuestResult([3, 4], 0, true)
        ],
        proposals: [
          rejected(1, 5, [1, 3, 5]),
          rejected(2, 6, [1, 4, 6]),
        ]);
    final kept = share((b) => b.chooseTeam(o, 3).contains(1));
    expect(kept, lessThan(.1));
  });

  group('Merlin plays the servant where it costs nothing', () {
    /// How many of 300 Merlins with a taste for acting do [act].
    double actors(bool Function(BotBrain) act) {
      var n = 0;
      for (var seed = 0; seed < 300; seed++) {
        if (act(BotBrain(Random(seed), style: BotStyle.actor))) n++;
      }
      return n / 300;
    }

    test('he can tell when his vote will not decide a proposal', () {
      final merlin = BotBrain(Random(1), style: BotStyle.actor);
      // nobody turns the first team down
      expect(
          merlin.voteDecides(observe(
              role: Role.merlin,
              count: 5,
              visible: [3, 4],
              leader: 1,
              phase: GamePhase.vote,
              team: [1, 3])),
          0);
      // Five players, both evil players on the leader's team: with the
      // leader they carry it, whatever Merlin and the last player do.
      final carried = observe(
          role: Role.merlin,
          count: 5,
          visible: [3, 4],
          leader: 1,
          phase: GamePhase.vote,
          team: [1, 3, 4],
          history: [
            QuestResult([1, 2], 0, true)
          ]);
      expect(merlin.voteDecides(carried), lessThan(.15));
      // Two players on a team of strangers: every vote may be the one.
      final open = observe(
          role: Role.merlin,
          count: 5,
          visible: [3, 4],
          leader: 2,
          phase: GamePhase.vote,
          team: [0, 2, 3],
          history: [
            QuestResult([1, 2], 0, true)
          ]);
      expect(
          merlin.voteDecides(open), greaterThan(merlin.voteDecides(carried)));
    });

    test('he never lets evil through when one more failed quest loses', () {
      // six players, so the fourth quest still fails on a single card
      final o = observe(
          role: Role.merlin,
          count: 6,
          visible: [4, 5],
          leader: 1,
          phase: GamePhase.vote,
          team: [0, 1, 4],
          history: [
            QuestResult([3, 5], 1, false),
            QuestResult([0, 1, 4], 0, true),
            QuestResult([2, 3, 5], 1, false)
          ]);
      expect(actors((b) => b.vote(o)), 0);
    });

    test('leading a quest that needs two Fails he may bring one of them', () {
      // fourth quest at seven players: one evil player cannot fail it
      final o = observe(
          role: Role.merlin,
          visible: [5, 6],
          seat: 0,
          leader: 0,
          phase: GamePhase.team,
          history: [
            QuestResult([0, 1], 0, true),
            QuestResult([1, 2, 6], 1, false),
            QuestResult([0, 1, 5], 0, true)
          ]);
      var withOne = 0;
      for (var seed = 0; seed < 300; seed++) {
        final team =
            BotBrain(Random(seed), style: BotStyle.actor).chooseTeam(o, 4);
        final evil = team.where([5, 6].contains).length;
        expect(evil, lessThan(2), reason: 'seed $seed: $team');
        if (evil == 1) withOne++;
      }
      // seat 5 has two clean quests on the record: a servant would take him
      expect(withOne / 300, greaterThan(.3));
    });
  });

  group('a player stands by whom he accused on this quest', () {
    // seat 0 said earlier on the second quest that seat 3 is suspicious
    final accusation = DiscussionStatement(
        speaker: 0,
        quest: 2,
        generation: 4,
        attempt: 1,
        text: '3號很可疑',
        target: 3,
        position: DiscussionPosition.suspect);
    BotObservation at(int rejections, {int leader = 1}) => observe(
            seat: 0,
            leader: leader,
            rejections: rejections,
            phase: leader == 0 ? GamePhase.team : GamePhase.vote,
            team: [
              0,
              4,
              3
            ],
            history: [
              QuestResult([4, 5], 0, true)
            ],
            statements: [
              accusation
            ]);

    test('he does not back a team with him while proposals are to spare', () {
      expect(share((b) => b.vote(at(1))), 0);
      // once proposals run short, getting a team out comes first
      expect(share((b) => b.vote(at(3))), greaterThan(0));
    });

    test('nor does he put him on his own team', () {
      for (var seed = 0; seed < 50; seed++) {
        expect(BotBrain(Random(seed)).chooseTeam(at(1, leader: 0), 3),
            isNot(contains(3)));
      }
    });

    test('speaking up for him later lifts it', () {
      final o = observe(
          seat: 0,
          leader: 1,
          rejections: 1,
          phase: GamePhase.vote,
          team: [
            0,
            4,
            3
          ],
          history: [
            QuestResult([4, 5], 0, true)
          ],
          statements: [
            accusation,
            DiscussionStatement(
                speaker: 0,
                quest: 2,
                generation: 4,
                attempt: 2,
                text: '3號先別急著定',
                target: 3,
                position: DiscussionPosition.defend)
          ]);
      expect(share((b) => b.vote(o)), greaterThan(0));
    });
  });

  test('after a failed quest Merlin does not let evil through on his vote', () {
    // A reported 5-player game: seats 0 and 4 are evil; Merlin (seat 2)
    // votes on seat 3's team 2, 3, 4 after quests of 1 fail, then two
    // clean ones. Seats 0 and 1 will turn it down, 3 and 4 pass it: his
    // vote decides it, so a cover vote would hand evil a quest.
    final o = observe(
        role: Role.merlin,
        count: 5,
        seat: 2,
        leader: 3,
        visible: [0, 4],
        phase: GamePhase.vote,
        team: [2, 3, 4],
        history: [
          QuestResult([0, 1], 1, false),
          QuestResult([2, 3, 4], 0, true),
          QuestResult([2, 3], 0, true),
        ]);
    for (var seed = 0; seed < 300; seed++) {
      expect(BotBrain(Random(seed), style: BotStyle.actor).vote(o), isFalse,
          reason: 'seed $seed');
    }
  });

  group('the hard push', () {
    const roles = {Role.merlin, Role.assassin, Role.percival, Role.morgana};
    // five players: Morgana in seat 0, the Assassin in seat 4
    BotObservation firstQuest() => observe(
        role: Role.morgana,
        evil: true,
        count: 5,
        visible: [4],
        leader: 1,
        phase: GamePhase.quest,
        team: [0, 1],
        configuredRoles: roles);

    test('an aggressive Morgana fails the first quest on purpose', () {
      double fails(BotStyle style) =>
          [
            for (var seed = 0; seed < 300; seed++)
              if (!BotBrain(Random(seed), style: style).questCard(firstQuest()))
                1
          ].length /
          300;
      expect(fails(BotStyle.aggressive), greaterThan(.5));
      expect(fails(BotStyle.cautious), lessThan(.35));
      BotBrain.hardlineChance = 0;
      addTearDown(() => BotBrain.hardlineChance = 1);
      expect(fails(BotStyle.aggressive), lessThan(.3));
    });

    test('then claims Percival and names her partner as Morgana', () {
      // the quest failed; second quest, seat 1 is not on the team
      final later = observe(
          role: Role.morgana,
          evil: true,
          count: 5,
          visible: [4],
          leader: 2,
          phase: GamePhase.discussion,
          team: [2, 3, 4],
          configuredRoles: roles,
          history: [
            QuestResult([0, 1], 1, false)
          ]);
      var claimed = 0;
      for (var seed = 0; seed < 100; seed++) {
        final brain = BotBrain(Random(seed), style: BotStyle.aggressive);
        if (!brain.hardline(firstQuest())) continue;
        final said = brain.speech(later, false);
        expect(said.claimsPercival, isTrue, reason: 'seed $seed');
        expect(said.target, 1);
        claimed++;
      }
      expect(claimed, greaterThan(30));
    });

    test('and her ally piles onto the player she named', () {
      final o = observe(
          role: Role.assassin,
          evil: true,
          count: 5,
          seat: 4,
          visible: [0],
          leader: 2,
          phase: GamePhase.discussion,
          team: [2, 3, 4],
          configuredRoles: roles,
          history: [
            QuestResult([0, 1], 1, false)
          ],
          statements: [
            DiscussionStatement(
                speaker: 0,
                quest: 2,
                generation: 4,
                attempt: 1,
                text: '我是派西維爾，2號是莫甘娜',
                target: 1,
                intent: DiscussionStatement.percivalClaim,
                position: DiscussionPosition.suspect)
          ]);
      var named = 0, spoke = 0;
      for (var seed = 0; seed < 100; seed++) {
        final said =
            BotBrain(Random(seed), style: BotStyle.aggressive).speech(o, false);
        if (said.position == DiscussionPosition.suspect) {
          spoke++;
          if (said.target == 1) named++;
        }
      }
      expect(spoke, greaterThan(20));
      expect(named, spoke);
    });
  });

  test('倒鉤: an evil player steps on an ally the table has caught', () {
    // seat 0 (evil) sat on both failed quests; seat 1 has just accused him.
    // Seat 4 is his ally.
    final o = observe(
        role: Role.minion,
        evil: true,
        count: 7,
        seat: 4,
        visible: [0, 6],
        leader: 2,
        phase: GamePhase.discussion,
        team: [2, 3, 5],
        history: [
          QuestResult([0, 1], 1, false),
          QuestResult([0, 2, 3], 1, false)
        ],
        statements: [
          DiscussionStatement(
              speaker: 1,
              quest: 3,
              generation: 4,
              attempt: 1,
              text: '1號兩次都在出事的隊上',
              target: 0,
              position: DiscussionPosition.suspect)
        ]);
    (int, int) said(bool bussing) {
      var against = 0, for0 = 0;
      for (var seed = 0; seed < 100; seed++) {
        final brain = BotBrain(Random(seed), style: BotStyle.actor);
        brain.speech(o, false); // decides once; then set the plan
        brain.voice.bussing = bussing;
        final s = brain.speech(o, false);
        if (s.target != 0) continue;
        if (s.position == DiscussionPosition.suspect) against++;
        if (s.position == DiscussionPosition.defend) for0++;
      }
      return (against, for0);
    }

    final (against, defended) = said(true);
    expect(against, greaterThan(20));
    expect(defended, 0);
    final (againstNormally, _) = said(false);
    expect(againstNormally, 0);
  });

  test('a quest from before a Lancelot switch is no clean record', () {
    // variant two, the sides switched for the first quest: its two Fails
    // say nothing now. Nobody may speak of "第次" (an empty list).
    final o = observe(
        count: 10,
        seat: 5,
        leader: 2,
        phase: GamePhase.discussion,
        team: [1, 2, 5, 8],
        switched: true,
        expansions: const ExpansionSettings(lady: true, lancelot: 2),
        loyalty: const [true, false, false, false, false],
        history: [
          QuestResult([1, 3, 7], 2, false)
        ]);
    for (var seed = 0; seed < 200; seed++) {
      final said = BotBrain(Random(seed)).speech(o, true).text;
      expect(said, isNot(contains('第次')), reason: 'seed $seed: $said');
    }
  });

  test('two evil players do not both rush to defend the same ally', () {
    // seat 2 is accused; his ally seat 6 has already spoken up for him
    final o = observe(
        role: Role.minion,
        evil: true,
        count: 7,
        seat: 4,
        visible: [2, 6],
        leader: 1,
        phase: GamePhase.discussion,
        team: [0, 1, 3],
        history: [
          QuestResult([1, 2, 3], 1, false)
        ],
        statements: [
          DiscussionStatement(
              speaker: 0,
              quest: 2,
              generation: 4,
              attempt: 1,
              text: '3號可疑',
              target: 2,
              position: DiscussionPosition.suspect),
          DiscussionStatement(
              speaker: 6,
              quest: 2,
              generation: 4,
              attempt: 1,
              text: '3號還不到要排掉的程度',
              target: 2,
              position: DiscussionPosition.defend),
        ]);
    for (var seed = 0; seed < 100; seed++) {
      final said =
          BotBrain(Random(seed), style: BotStyle.aggressive).speech(o, false);
      expect(said.position == DiscussionPosition.defend && said.target == 2,
          isFalse,
          reason: 'seed $seed');
    }
  });

  test('the Assassin counts who called out evil players early', () {
    // seven players; the Assassin (seat 3) and his ally seat 6. Seats 1
    // and 4 have the same record; seat 4 named the Assassin while nobody
    // had a reason to doubt him.
    BotObservation at({required bool called}) => observe(
        role: Role.assassin,
        evil: true,
        count: 7,
        seat: 3,
        visible: [6],
        phase: GamePhase.assassination,
        history: [
          QuestResult([0, 2], 0, true),
          QuestResult([0, 1, 4], 0, true),
          QuestResult([0, 2, 5], 0, true),
        ],
        statements: [
          if (called)
            DiscussionStatement(
                speaker: 4,
                quest: 2,
                generation: 4,
                attempt: 1,
                text: '4號有點可疑',
                target: 3,
                position: DiscussionPosition.suspect)
        ]);
    int stabs(BotObservation o) => [
          for (var seed = 0; seed < 300; seed++)
            if (BotBrain(Random(seed)).assassinate(o) == 4) 1
        ].length;
    expect(stabs(at(called: true)), greaterThan(stabs(at(called: false)) + 20));
  });
}
