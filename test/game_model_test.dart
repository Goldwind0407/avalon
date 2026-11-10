import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';

AvalonGame setup({int count = 5, Set<String> extras = const {}}) {
  final room = Room(
      code: '123456',
      players: List.generate(
          count, (i) => Player(id: '$i', name: '騎士 $i', isReady: true)));
  room.specialRoles.addAll(extras);
  final game = AvalonGame(room, random: Random(42));
  for (var i = 0; i < count; i++) {
    game.confirmIdentity();
  }
  return game;
}

void approve(AvalonGame game, Iterable<int> team) {
  game.proposeTeam(team);
  for (var i = 0; i < game.players.length; i++) {
    game.vote(true);
  }
  game.continueVote();
}

void succeed(AvalonGame game) {
  approve(game, List.generate(game.requiredTeam, (i) => i));
  while (game.phase == GamePhase.quest) {
    game.playQuest(true);
  }
  game.continueQuest();
}

void main() {
  test('all supported player counts receive correct alignment and quest sizes',
      () {
    for (var count = 5; count <= 10; count++) {
      final game = setup(count: count);
      expect(game.roles.length, count);
      expect(game.roles.where((r) => r.isEvil).length, Room.evilCount(count));
      expect(game.roles.where((r) => r == Role.merlin).length, 1);
      expect(game.roles.where((r) => r == Role.assassin).length, 1);
      expect(game.requiredTeam, count <= 7 ? 2 : 3);
    }
  });

  test('invalid role configuration and unready players cannot start', () {
    final room = Room(
        code: '123456',
        players: List.generate(
            5, (i) => Player(id: '$i', name: '$i', isReady: true)));
    room.specialRoles.addAll(['莫甘娜', '莫德雷德']);
    expect(() => AvalonGame(room), throwsStateError);
    room.specialRoles.remove('莫德雷德');
    room.players.first.isReady = false;
    expect(() => AvalonGame(room), throwsStateError);
  });

  test('Merlin, Percival and evil have the correct private knowledge', () {
    final game = setup(count: 10, extras: {'派西維爾', '莫甘娜', '莫德雷德', '奧伯倫'});
    String label(Role role) {
      final i = game.roles.indexOf(role);
      return '${i + 1} 號 ${game.players[i]}';
    }

    final merlin = game.knowledge(game.roles.indexOf(Role.merlin));
    expect(merlin, contains(label(Role.oberon)));
    expect(merlin, contains(label(Role.assassin)));
    expect(merlin, isNot(contains(label(Role.mordred))));
    final percival = game.knowledge(game.roles.indexOf(Role.percival));
    expect(percival, contains(label(Role.merlin)));
    expect(percival, contains(label(Role.morgana)));
    final assassin = game.knowledge(game.roles.indexOf(Role.assassin));
    expect(assassin, contains(label(Role.mordred)));
    expect(assassin, isNot(contains(label(Role.oberon))));
  });

  test('tie rejects the team; fifth rejection ends the game', () {
    final game = setup(count: 6);
    final leader = game.leader;
    for (var attempt = 0; attempt < 5; attempt++) {
      game.proposeTeam([0, 1]);
      for (var voter = 0; voter < 6; voter++) {
        game.vote(voter < 3);
        if (voter < 5) expect(game.votes, isEmpty);
      }
      expect(game.teamApproved, isFalse);
      game.continueVote();
    }
    expect(game.phase, GamePhase.finished);
    expect(game.winner, '邪惡');
    expect(game.leader, (leader + 4) % 6);
  });

  test('good players cannot sabotage; three failed quests end the game', () {
    final game = setup();
    for (var round = 0; round < 3; round++) {
      final evil = game.roles.indexWhere((r) => r.isEvil);
      final team = [evil, ...List.generate(5, (i) => i).where((i) => i != evil)]
          .take(game.requiredTeam);
      approve(game, team);
      while (game.phase == GamePhase.quest) {
        final isEvil = game.roles[game.questActor].isEvil;
        if (!isEvil) expect(() => game.playQuest(false), throwsArgumentError);
        game.playQuest(!isEvil);
      }
      game.continueQuest();
    }
    expect(game.winner, '邪惡');
    expect(game.failures, 3);
  });

  test('fourth quest needs two fails for seven or more players', () {
    for (final count in [6, 7, 10]) {
      final game = setup(count: count);
      // Two successes and a failed third quest keep the game in progress.
      succeed(game);
      succeed(game);
      final evil = game.roles.indexWhere((r) => r.isEvil);
      approve(
          game,
          [evil, ...List.generate(count, (i) => i).where((i) => i != evil)]
              .take(game.requiredTeam));
      while (game.phase == GamePhase.quest) {
        game.playQuest(game.questActor != evil);
      }
      game.continueQuest();
      expect(game.failsRequired, count >= 7 ? 2 : 1);
      approve(
          game,
          [evil, ...List.generate(count, (i) => i).where((i) => i != evil)]
              .take(game.requiredTeam));
      while (game.phase == GamePhase.quest) {
        game.playQuest(game.questActor != evil);
      }
      expect(game.history.last.succeeded, count >= 7);
    }
  });

  test('three successes lead to assassination, with either ending', () {
    for (final hit in [true, false]) {
      final game = setup();
      succeed(game);
      succeed(game);
      succeed(game);
      expect(game.phase, GamePhase.assassination);
      final target = game.roles.indexWhere(
          (r) => hit ? r == Role.merlin : !r.isEvil && r != Role.merlin);
      game.assassinate(target);
      expect(game.winner, hit ? '邪惡' : '正義');
      expect(() => game.vote(true), throwsStateError);
    }
  });

  test('invalid teams cannot advance the game', () {
    final game = setup();
    expect(() => game.proposeTeam([0, 0]), throwsArgumentError);
    expect(() => game.proposeTeam([0, 99]), throwsArgumentError);
    expect(game.phase, GamePhase.team);
  });
}
