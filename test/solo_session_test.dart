import 'dart:math';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';
import 'package:avalon_shadow_council/features/game/expansion_model.dart';
import 'package:avalon_shadow_council/features/game/game_model.dart';
import 'package:avalon_shadow_council/features/lobby/role_presets.dart';
import 'package:avalon_shadow_council/features/lobby/room_model.dart';
import 'package:avalon_shadow_council/features/solo/solo_session.dart';

Room soloRoom(int count, ExpansionSettings expansions) => Room(
    code: '',
    players: List.generate(count,
        (i) => Player(id: '$i', name: i == 0 ? '你' : '電腦$i', isReady: true)))
  ..specialRoles.addAll([for (final role in rolePreset(count)!) role.label])
  ..discussion = DiscussionSettings.recommended
  ..expansions = expansions;

void humanMove(SoloGameSession session, Random rng) {
  switch (session.phase) {
    case GamePhase.identity:
      session.confirmIdentity(0);
    case GamePhase.team:
      final seats = List.generate(session.players.length, (i) => i)
        ..shuffle(rng);
      final team = seats.take(session.requiredTeam).toList();
      session.proposeTeam(team,
          excalibur: session.expansions.excalibur
              ? team.firstWhere((s) => s != session.leader)
              : null);
    case GamePhase.discussion:
      session.expressOpinion(rng.nextBool());
    case GamePhase.vote:
      session.vote(0, session.rejections == 4 || rng.nextDouble() < .85);
    case GamePhase.voteResult:
      session.continueVote();
    case GamePhase.quest:
      session.playQuest(
          0,
          session.mustFail(0)
              ? false
              : session.evilNow(0)!
                  ? rng.nextBool()
                  : true);
    case GamePhase.questResult:
      session.continueQuest();
    case GamePhase.lady:
      session.useLady(List.generate(session.players.length, (i) => i)
          .firstWhere((s) => !session.ladyPast.contains(s)));
    case GamePhase.ladyResult:
      session.continueLady();
    case GamePhase.excalibur:
      session.useExcalibur(
          rng.nextBool() ? null : session.team.firstWhere((s) => s != 0));
    case GamePhase.excaliburResult:
      session.continueExcalibur();
    case GamePhase.assassination:
      session.assassinate(1);
    default:
      throw StateError('Unexpected human phase: ${session.phase}');
  }
}

class ClockedSoloSession extends SoloGameSession {
  ClockedSoloSession()
      : super(soloRoom(5, const ExpansionSettings()),
            random: Random(3), botDelay: const Duration(milliseconds: 1));
  int clock = DateTime.now().millisecondsSinceEpoch;
  @override
  int get nowMillis => clock;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final visited = <GamePhase>{};
  final rolesSeen = <Role>{};
  var games = 0;
  for (var count = 5; count <= 10; count++) {
    test(
        '$count seats: complete games for every supported expansion combination',
        () {
      fakeAsync((time) {
        for (final lady in [false, true]) {
          for (final sword in [false, true]) {
            for (final lancelot in count >= 7 ? [0, 1, 2] : [0]) {
              for (var seed = 0; seed < 12; seed++) {
                final room = soloRoom(
                    count,
                    ExpansionSettings(
                        lady: lady, excalibur: sword, lancelot: lancelot));
                expect(room.canStart, isTrue);
                final session = SoloGameSession(room,
                    random: Random(seed),
                    botDelay: const Duration(milliseconds: 1),
                    speechDuration: const Duration(milliseconds: 1));
                final rng = Random(seed + 1000);
                var steps = 0;
                rolesSeen.add(session.roleOf(0)!);
                while (session.phase != GamePhase.finished && steps++ < 500) {
                  visited.add(session.phase);
                  for (var s = 1; s < count; s++) {
                    expect(session.roleOf(s), isNull,
                        reason: 'No hidden BOT identity in the human view');
                    expect(session.knowledge(s), isEmpty);
                    expect(session.evilNow(s), isNull);
                  }
                  if (session.phase == GamePhase.vote) {
                    expect(session.votes, isEmpty);
                  }
                  if (session.hasPrivateInput ||
                      [GamePhase.voteResult, GamePhase.questResult]
                          .contains(session.phase)) {
                    humanMove(session, rng);
                  } else {
                    time.elapse(const Duration(milliseconds: 1));
                  }
                  time.flushMicrotasks();
                }
                expect(session.phase, GamePhase.finished,
                    reason:
                        '$count seats / lady=$lady sword=$sword lancelot=$lancelot seed=$seed');
                expect(session.winner, isNotNull);
                expect(session.history.length, lessThanOrEqualTo(5));
                expect(
                    session.statements
                        .where((s) => s.claimedEvil != null)
                        .every((s) => room.expansions.lady && s.target != null),
                    isTrue);
                for (var s = 0; s < count; s++) {
                  expect(session.roleOf(s), isNotNull);
                }
                session.dispose();
                time.flushMicrotasks();
                games++;
              }
            }
          }
        }
      });
    });
  }
  test('Mordred and Oberon can each be the human seat for a complete game', () {
    fakeAsync((time) {
      for (final wanted in [Role.mordred, Role.oberon]) {
        SoloGameSession? selected;
        for (var seed = 0; seed < 500; seed++) {
          final room =
              soloRoom(10, const ExpansionSettings(lady: true, excalibur: true))
                ..specialRoles.addAll(['莫德雷德', '奧伯倫']);
          final candidate = SoloGameSession(room,
              random: Random(seed),
              botDelay: const Duration(milliseconds: 1),
              speechDuration: const Duration(milliseconds: 1));
          if (candidate.roleOf(0) == wanted) {
            selected = candidate;
            break;
          }
          candidate.dispose();
        }
        final session = selected!;
        rolesSeen.add(session.roleOf(0)!);
        var steps = 0;
        while (session.phase != GamePhase.finished && steps++ < 2000) {
          visited.add(session.phase);
          if (session.hasPrivateInput ||
              [GamePhase.voteResult, GamePhase.questResult]
                  .contains(session.phase)) {
            humanMove(session, Random(steps));
          } else {
            time.elapse(const Duration(milliseconds: 1));
          }
          time.flushMicrotasks();
        }
        expect(session.phase, GamePhase.finished);
        session.dispose();
        time.flushMicrotasks();
        games++;
      }
    });
  });
  test('simulation exercises all playable stages and special human identities',
      () {
    expect(games, 674);
    expect(
        visited,
        containsAll(GamePhase.values.where(
            (p) => p != GamePhase.freeDiscussion && p != GamePhase.finished)));
    expect(
        rolesSeen,
        containsAll([
          Role.merlin,
          Role.percival,
          Role.assassin,
          Role.morgana,
          Role.mordred,
          Role.oberon,
          Role.lancelotGood,
          Role.lancelotEvil
        ]));
  });

  test('paused, restarted and disposed sessions cannot execute old BOT actions',
      () {
    fakeAsync((time) {
      final session = SoloGameSession(soloRoom(5, const ExpansionSettings()),
          random: Random(4));
      expect(session.isSolo, isTrue);
      expect(session.hasOwnSeat, isTrue);
      expect(session.isOnline, isFalse);
      session.confirmIdentity(0);
      session.pauseAutomation(true);
      time.elapse(const Duration(seconds: 5));
      expect(session.confirmedSeats, {0});
      session.pauseAutomation(false);
      time.elapse(const Duration(milliseconds: 450));
      expect(session.confirmedSeats, {0, 1});
      session.restart();
      time.flushMicrotasks();
      expect(session.generation, 2);
      expect(session.statements, isEmpty);
      time.elapse(const Duration(seconds: 5));
      expect(session.phase, GamePhase.identity);
      expect(session.confirmedSeats, isEmpty);
      session.dispose();
      time.elapse(const Duration(minutes: 2));
      time.flushMicrotasks();
    });
  });

  test('a human cannot send a BOT ballot or skip a private BOT reveal',
      () async {
    final session = SoloGameSession(soloRoom(5, const ExpansionSettings()),
        random: Random(2));
    expect(() => session.confirmIdentity(1), throwsA(isA<Exception>()));
    await session.confirmIdentity(0);
    expect(() => session.vote(1, true), throwsA(isA<Exception>()));
    expect(session.latestReveal, isNull);
    session.dispose();
  });

  test('long reading pauses preserve the remaining speech time', () {
    fakeAsync((time) {
      final session = ClockedSoloSession();
      session.confirmIdentity(0);
      time.elapse(const Duration(milliseconds: 5));
      if (session.phase == GamePhase.team) session.proposeTeam([0, 1]);
      expect(session.phase, GamePhase.discussion);
      final deadline = session.speechDeadline!;
      final version = session.speechVersion;
      session.pauseAutomation(true);
      session.clock += 90000;
      // Repeated lifecycle/dialog notifications must not overwrite the pause.
      session.pauseAutomation(true);
      time.elapse(const Duration(seconds: 90));
      expect(session.speechVersion, version);
      session.pauseAutomation(false);
      expect(session.speechDeadline, deadline + 90000);
      session.pauseAutomation(false);
      expect(session.speechDeadline, deadline + 90000);
      session.dispose();
      time.flushMicrotasks();
    });
  });
}
