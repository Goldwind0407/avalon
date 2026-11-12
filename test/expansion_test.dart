import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';

// Mirrored by functions/test/expansions.test.ts.

Room room(int count, ExpansionSettings expansions,
    [Set<String> extras = const {}]) {
  final r = Room(
      code: '123456',
      players: List.generate(
          count, (i) => Player(id: '$i', name: '騎士 $i', isReady: true)));
  r.specialRoles.addAll(extras);
  r.expansions = expansions;
  return r;
}

AvalonGame setup(ExpansionSettings expansions, {int count = 7, int seed = 1}) {
  final game = AvalonGame(room(count, expansions), random: Random(seed));
  for (var i = 0; i < count; i++) {
    game.confirmIdentity();
  }
  return game;
}

/// One quest: the Assassin goes along and fails it when [fail] is set.
/// Everyone else plays what they must (variant 2 Lancelots included).
void play(AvalonGame game, {bool fail = false}) {
  final assassin = game.roles.indexOf(Role.assassin);
  final team = [
    assassin,
    ...List.generate(game.players.length, (i) => i)
        .where((i) => i != assassin && !game.roles[i].isLancelot),
  ].take(game.requiredTeam).toList();
  final sword = game.expansions.excalibur
      ? team.firstWhere((i) => i != game.leader)
      : null;
  game.proposeTeam(team, excalibur: sword);
  for (var i = 0; i < game.players.length; i++) {
    game.vote(true);
  }
  game.continueVote();
  while (game.phase == GamePhase.quest) {
    final seat = game.questActor;
    game.playQuest(!(seat == assassin && fail) && !game.mustFail(seat));
  }
  if (game.phase == GamePhase.excalibur) game.useExcalibur(null);
  game.continueQuest();
  if (game.phase == GamePhase.lady) {
    game.useLady(List.generate(game.players.length, (i) => i)
        .firstWhere((i) => !game.ladyPast.contains(i)));
    game.continueLady();
  }
}

/// First seed whose game satisfies [test].
AvalonGame seeded(ExpansionSettings e, bool Function(AvalonGame) test,
    {void Function(AvalonGame)? before}) {
  for (var seed = 0; seed < 500; seed++) {
    final game = setup(e, seed: seed);
    before?.call(game);
    if (test(game)) return game;
  }
  throw StateError('no seed found');
}

void main() {
  const v1 = ExpansionSettings(lancelot: 1);
  const v2 = ExpansionSettings(lancelot: 2);

  test('the Lancelots take one good and one evil place', () {
    for (final count in [7, 8, 10]) {
      final game = setup(v1, count: count);
      expect(game.roles, containsAll([Role.lancelotGood, Role.lancelotEvil]));
      expect(game.roles.where((r) => r.isEvil).length, Room.evilCount(count));
    }
    // Lancelot needs 7 players
    expect(room(6, v1).roleIssue, '蘭斯洛特擴充需要 7 人以上');
    expect(room(7, v1, {'莫甘娜'}).roleIssue, isNull);
    // 7 players: Assassin, Morgana, Mordred and evil Lancelot are one too many
    expect(room(7, v1, {'莫甘娜', '莫德雷德'}).roleIssue, isNotNull);
  });

  test('evil sees evil Lancelot; Lancelot sees nobody', () {
    final game = setup(v1, count: 8);
    final good = game.roles.indexOf(Role.lancelotGood);
    final evil = game.roles.indexOf(Role.lancelotEvil);
    expect(visibleSeats(game.roles, game.roles.indexOf(Role.assassin)),
        contains(evil));
    expect(visibleSeats(game.roles, game.roles.indexOf(Role.merlin)),
        contains(evil));
    expect(visibleSeats(game.roles, evil), isEmpty);
    expect(visibleSeats(game.roles, good), isEmpty);
    // evil knows which ally is Lancelot; Merlin and Lancelot himself do not
    final assassin = game.roles.indexOf(Role.assassin);
    final merlin = game.roles.indexOf(Role.merlin);
    expect(knownLancelot(game.roles, assassin), evil);
    expect(knownLancelot(game.roles, merlin), isNull);
    expect(knownLancelot(game.roles, evil), isNull);
    expect(knownLancelot(game.roles, good), isNull);
    expect(game.knowledge(assassin), contains('（邪惡蘭斯洛特）'));
    expect(game.knowledge(assassin), contains('邪惡蘭斯洛特會改為正義陣營'));
    expect(game.knowledge(merlin), isNot(contains('蘭斯洛特')));
    // without the expansion nobody is singled out
    final plain = setup(const ExpansionSettings(), count: 8);
    for (var s = 0; s < 8; s++) {
      expect(knownLancelot(plain.roles, s), isNull);
    }
  });

  test('variant 1: loyalty cards are turned over from the third quest', () {
    final game = seeded(v1, (g) => g.loyalty[2] == true, before: (g) {
      play(g);
      play(g, fail: true);
    });
    expect(game.loyalty.take(2), [null, null]);
    expect(game.lancelotSwitched, isTrue);
    final good = game.roles.indexOf(Role.lancelotGood);
    final evil = game.roles.indexOf(Role.lancelotEvil);
    expect(game.evilNow(good), isTrue);
    expect(game.evilNow(evil), isFalse);
    expect(game.mustFail(good), isFalse); // variant 1: free choice
    // now on the good side, evil Lancelot may only succeed
    game.proposeTeam([evil, good, game.roles.indexOf(Role.merlin)]);
    for (var i = 0; i < 7; i++) {
      game.vote(true);
    }
    game.continueVote();
    while (game.phase == GamePhase.quest) {
      final seat = game.questActor;
      if (seat == evil) {
        expect(() => game.playQuest(false), throwsArgumentError);
      }
      game.playQuest(seat != good); // switched good Lancelot sabotages
    }
    expect(game.history.last.fails, 1);
    game.continueQuest();
    play(game, fail: true);
    // at most one card per quest from the third on
    expect(game.loyalty.where((c) => c != null).length, 3);
  });

  test('variant 2: five cards are dealt face up; evil Lancelot must fail', () {
    final game = seeded(v2, (g) => g.loyalty[0] == true);
    expect(game.loyalty.every((c) => c != null), isTrue);
    expect(game.loyalty.where((c) => c == true).length, lessThanOrEqualTo(2));
    expect(game.lancelotSwitched, isTrue); // the first quest's card counts
    final good = game.roles.indexOf(Role.lancelotGood);
    final evil = game.roles.indexOf(Role.lancelotEvil);
    expect(game.mustFail(good), isTrue);
    expect(game.mustFail(evil), isFalse);
    game.proposeTeam([good, evil]);
    for (var i = 0; i < 7; i++) {
      game.vote(true);
    }
    game.continueVote();
    while (game.phase == GamePhase.quest) {
      final seat = game.questActor;
      if (seat == good) {
        expect(() => game.playQuest(true), throwsArgumentError);
      } else {
        expect(() => game.playQuest(false), throwsArgumentError);
      }
      game.playQuest(seat != good);
    }
    expect(game.history.last.succeeded, isFalse);
  });

  test('Lady of the Lake after quests 2-4, never on a past holder', () {
    final game = setup(const ExpansionSettings(lady: true));
    final first = (game.leader - 1 + 7) % 7;
    expect(game.ladyHolder, first);
    play(game);
    expect(game.phase, GamePhase.team); // not after the first quest
    final assassin = game.roles.indexOf(Role.assassin);
    // second quest: play by hand to stop at the Lady
    final team = [
      assassin,
      ...[0, 1, 2, 3].where((i) => i != assassin)
    ].take(game.requiredTeam);
    game.proposeTeam(team);
    for (var i = 0; i < 7; i++) {
      game.vote(true);
    }
    game.continueVote();
    while (game.phase == GamePhase.quest) {
      game.playQuest(game.questActor != assassin);
    }
    game.continueQuest();
    expect(game.phase, GamePhase.lady);
    expect(() => game.useLady(first), throwsArgumentError);
    final target = first == assassin ? (first + 1) % 7 : assassin;
    game.useLady(target);
    expect(game.phase, GamePhase.ladyResult);
    expect(game.ladySawEvil, game.roles[target].isEvil);
    final leader = game.leader;
    game.continueLady();
    expect(game.ladyHolder, target);
    expect(game.ladyPast, [first, target]);
    expect(game.phase, GamePhase.team);
    expect(game.leader, (leader + 1) % 7);
    expect(game.ladyChecks.single.holder, first);
  });

  test('three successes go straight to the assassination', () {
    final game = setup(const ExpansionSettings(lady: true));
    play(game);
    play(game);
    play(game);
    expect(game.phase, GamePhase.assassination);
  });

  test('Excalibur: handed to a team member, may flip one other card', () {
    final game = setup(const ExpansionSettings(excalibur: true));
    final team = [0, 1, 2]..remove(game.leader);
    while (team.length < game.requiredTeam) {
      team.add(game.leader == 3 ? 4 : 3);
    }
    expect(() => game.proposeTeam(team), throwsArgumentError);
    if (team.contains(game.leader)) {
      expect(() => game.proposeTeam(team, excalibur: game.leader),
          throwsArgumentError);
    }
    final holder = team.first, target = team.last;
    game.proposeTeam(team, excalibur: holder);
    expect(game.excaliburHolder, holder);
    for (var i = 0; i < 7; i++) {
      game.vote(true);
    }
    game.continueVote();
    while (game.phase == GamePhase.quest) {
      game.playQuest(!game.mustFail(game.questActor));
    }
    expect(game.phase, GamePhase.excalibur);
    expect(() => game.useExcalibur(holder), throwsArgumentError);
    game.useExcalibur(target);
    expect(game.phase, GamePhase.excaliburResult);
    expect(game.excaliburSawCard, isTrue);
    game.continueExcalibur();
    expect(game.phase, GamePhase.questResult);
    expect(game.history.last.fails, 1);
    expect(game.history.last.succeeded, isFalse);
    expect(game.history.last.excaliburHolder, holder);
    expect(game.history.last.excaliburTarget, target);
    game.continueQuest();
    expect(game.excaliburHolder, isNull);
  });
}
