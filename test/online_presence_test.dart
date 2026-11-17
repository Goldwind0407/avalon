import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/game/player_speech.dart';
import 'package:avalon_shadow_council/features/online/online_session.dart';
import 'online_table_test.dart' show FakeServer;
import 'online_race_test.dart' show roomData, card;

/// The room as the phone in seat 1 ("me") sees it; seat 0 hosts.
Map<String, dynamic> room(
    {String phase = 'vote',
    List<int> voted = const [],
    List<int> away = const [],
    String host = 'u0'}) {
  final data = roomData(phase: phase);
  data['hostUid'] = host;
  data['away'] = away;
  (data['game'] as Map)['voted'] = voted;
  return data;
}

void main() {
  int nudges(FakeServer server) =>
      server.calls.where((c) => c.$1 == 'nudge').length;

  /// Runs [body] with a session that reports its presence.
  void withSession(
      void Function(FakeAsync time, FakeServer server, OnlineGameSession s,
              List<int> beats)
          body) {
    fakeAsync((time) {
      final server = FakeServer();
      final beats = <int>[];
      final session = OnlineGameSession(
          code: '123456',
          uid: 'me',
          room: server.rooms.stream,
          mine: server.mine.stream,
          call: server.call,
          beat: (now) async => beats.add(now));
      time.flushMicrotasks();
      body(time, server, session, beats);
      session.dispose();
      server.rooms.close();
      server.mine.close();
      time.flushMicrotasks();
    });
  }

  void feed(FakeAsync time, FakeServer server, Map<String, dynamic> data) {
    server.rooms.add(data);
    server.mine.add(card());
    time.flushMicrotasks();
  }

  test('the phone tells the server it is here, at once and every 20 seconds',
      () {
    withSession((time, server, session, beats) {
      expect(beats, hasLength(1));
      time.elapse(const Duration(seconds: 61));
      expect(beats, hasLength(4));
      // coming back to the app reports without waiting for the next beat
      session.reportPresence();
      expect(beats, hasLength(5));
    });
  });

  test('a game that stands still waiting for others gets the server asked', () {
    withSession((time, server, session, beats) {
      // everyone but seat 3 has voted; this phone is not the host
      feed(time, server, room(voted: [0, 1, 2, 4]));
      time.elapse(const Duration(seconds: 44));
      expect(nudges(server), 0);
      time.elapse(const Duration(seconds: 2));
      expect(nudges(server), 1);
      // still nothing moved: it asks again after the same wait
      time.elapse(const Duration(seconds: 46));
      expect(nudges(server), 2);
    });
  });

  test('the host asks first', () {
    withSession((time, server, session, beats) {
      feed(time, server, room(voted: [0, 1, 2, 4], host: 'me'));
      time.elapse(const Duration(seconds: 31));
      expect(nudges(server), 1);
    });
  });

  test('nobody is asked about while the game only waits for this player', () {
    withSession((time, server, session, beats) {
      feed(time, server, room(voted: [0, 2, 3, 4]));
      time.elapse(const Duration(minutes: 5));
      expect(nudges(server), 0);
    });
  });

  test('a player known to be away is played for after a short look', () {
    withSession((time, server, session, beats) {
      feed(time, server, room(voted: [0, 1, 2, 4], away: [3]));
      expect(session.awaySeats, {3});
      // played for like a computer: soon, the host's phone first
      expect(session.isComputer(3), isTrue);
      time.elapse(const Duration(seconds: 5));
      expect(nudges(server), 0);
      time.elapse(const Duration(milliseconds: 300));
      expect(nudges(server), 1);
    });
  });

  test('a player who finds himself played for takes the seat back at once', () {
    withSession((time, server, session, beats) {
      feed(time, server, room(away: [1]));
      expect(nudges(server), 1);
    });
  });

  test('a new move starts the wait again', () {
    withSession((time, server, session, beats) {
      feed(time, server, room(voted: [0, 1]));
      time.elapse(const Duration(seconds: 40));
      feed(time, server, room(voted: [0, 1, 2]));
      time.elapse(const Duration(seconds: 40));
      expect(nudges(server), 0);
      time.elapse(const Duration(seconds: 6));
      expect(nudges(server), 1);
    });
  });

  test('without presence reporting nothing is ever asked', () {
    fakeAsync((time) {
      final server = FakeServer();
      final session = OnlineGameSession(
          code: '123456',
          uid: 'me',
          room: server.rooms.stream,
          mine: server.mine.stream,
          call: server.call);
      feed(time, server, room(voted: [0, 1, 2, 4], away: [3]));
      time.elapse(const Duration(minutes: 5));
      expect(nudges(server), 0);
      session.dispose();
      server.rooms.close();
      server.mine.close();
      time.flushMicrotasks();
    });
  });

  // ── computers at the table ──

  /// Seats 2-4 are computers; seat 0 hosts unless [host] says otherwise.
  Map<String, dynamic> withBots(Map<String, dynamic> data,
      {List<Map<String, dynamic>> talk = const []}) {
    final players = data['players'] as List;
    data['players'] = [
      for (final (s, p) in players.indexed)
        s < 2
            ? p
            : <String, Object>{
                ...(p as Map).cast<String, Object>(),
                'bot': true,
                'persona': ['chen', 'yu', 'zhe'][s - 2]
              }
    ];
    data['talk'] = talk;
    return data;
  }

  test('a computer that is waited for is asked soon, by the host first', () {
    withSession((time, server, session, beats) {
      // seat 3 (a computer) has not voted; this phone hosts
      feed(time, server, withBots(room(voted: [0, 1, 2, 4], host: 'me')));
      expect(session.hasComputers, isTrue);
      expect(session.isComputer(3), isTrue);
      expect(session.isComputer(1), isFalse);
      time.elapse(const Duration(milliseconds: 1100));
      expect(nudges(server), 0);
      time.elapse(const Duration(milliseconds: 200));
      expect(nudges(server), 1);
    });
    withSession((time, server, session, beats) {
      // not the host: only if nothing has come of the host's asking
      feed(time, server, withBots(room(voted: [0, 1, 2, 4])));
      time.elapse(const Duration(seconds: 5));
      expect(nudges(server), 0);
      time.elapse(const Duration(milliseconds: 300));
      expect(nudges(server), 1);
    });
  });

  test('a computer speaks at once and is given time to be read', () {
    withSession((time, server, session, beats) {
      // leader 0, first to speak is seat 1 (me)... make seat 2 the speaker
      final data = withBots(room(phase: 'discussion', host: 'me'));
      (data['game'] as Map)
        ..['speechIndex'] = 1
        ..['speechVersion'] = 4;
      feed(time, server, data);
      expect(session.speaker, 2);
      expect(session.currentStatement, isNull);
      time.elapse(const Duration(milliseconds: 800));
      expect(nudges(server), 1, reason: 'asked for its line');
      // the line arrives: shown, and left on the table to be read
      final spoken = withBots(room(phase: 'discussion', host: 'me'), talk: [
        {
          'by': 2,
          'q': 1,
          'a': 1,
          'g': 1,
          'sv': 4,
          'bot': true,
          'text': '這隊我沒意見，先讓它出發。',
          'for': true
        },
        {'by': 1, 'q': 1, 'a': 1, 'g': 1, 'sv': 3, 'text': '我覺得3號可疑'},
      ]);
      (spoken['game'] as Map)
        ..['speechIndex'] = 1
        ..['speechVersion'] = 4;
      feed(time, server, spoken);
      expect(session.currentStatement, '這隊我沒意見，先讓它出發。');
      expect([for (final s in session.statements) s.text],
          ['這隊我沒意見，先讓它出發。', '我覺得3號可疑']);
      expect(session.statements.first.supportsTeam, isTrue);
      time.elapse(const Duration(milliseconds: 6900));
      expect(nudges(server), 1);
      time.elapse(const Duration(milliseconds: 200));
      expect(nudges(server), 2, reason: 'time to pass the turn on');
    });
  });

  test('a typed line and a quick opinion are sent as words', () {
    withSession((time, server, session, beats) {
      final data = withBots(room(phase: 'discussion'));
      (data['game'] as Map)['speechVersion'] = 2;
      feed(time, server, data);
      expect(session.speaker, 1);
      session.say(PlayerSpeech.parse('我懷疑3號', session.players, 1));
      time.flushMicrotasks();
      final said = server.calls.lastWhere((c) => c.$1 == 'say').$2;
      expect(said['text'], '我懷疑3號');
      expect(said['generation'], 1);
      session.expressOpinion(false);
      time.flushMicrotasks();
      expect(server.calls.where((c) => c.$1 == 'say').last.$2['text'],
          '這隊我不放心，想換個組合。');
      expect(server.calls.last.$2['move'], 'endSpeech');
    });
  });

  test('when the game is over the review is fetched once a deal', () {
    fakeAsync((time) {
      final server = FakeServer();
      final asked = <int>[];
      final session = OnlineGameSession(
          code: '123456',
          uid: 'me',
          room: server.rooms.stream,
          mine: server.mine.stream,
          call: server.call,
          loadReview: (gen) async {
            asked.add(gen);
            return {
              'gen': gen,
              'players': [
                for (var s = 0; s < 5; s++)
                  {'uid': FakeServer.uids[s], 'name': '玩家$s', 'bot': false}
              ],
              'state': {
                'phase': 'finished',
                'leader': 0,
                'rejections': 0,
                'team': [],
                'history': [
                  {
                    'team': [0, 1],
                    'fails': 0,
                    'succeeded': true
                  }
                ],
                'proposals': [
                  {
                    'quest': 1,
                    'attempt': 1,
                    'leader': 0,
                    'team': [0, 1],
                    'votes': [true, true, true, true, true]
                  }
                ],
                'roles': ['loyal', 'merlin', 'assassin', 'percival', 'morgana'],
                'winner': '正義',
                'result': '刺客選錯了',
                'cardLog': {
                  '0': {'1': true},
                  '1': {'1': true}
                },
              },
              'talk': [],
            };
          });
      feed(time, server, room(phase: 'identity'));
      expect(asked, isEmpty);
      expect(session.review, isNull);
      feed(time, server, room(phase: 'finished'));
      expect(asked, [1]);
      expect(session.review?.mySeat, 1);
      expect(session.review?.winner, '正義');
      feed(time, server, room(phase: 'finished'));
      expect(asked, [1], reason: 'once a deal');
      session.dispose();
      server.rooms.close();
      server.mine.close();
      time.flushMicrotasks();
    });
  });
}
