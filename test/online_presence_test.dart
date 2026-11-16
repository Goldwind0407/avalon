import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
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
      time.elapse(const Duration(seconds: 7));
      expect(nudges(server), 0);
      time.elapse(const Duration(seconds: 2));
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
}
