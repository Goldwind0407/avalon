import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/notebook/notebook_model.dart';
import 'package:avalon_shadow_council/features/online/online_session.dart';
import 'notebook_model_test.dart' show MemoryNotebookStorage;
import 'online_table_test.dart' show FakeServer;

void main() {
  test('opening info and complete proposals save without ever opening notebook',
      () async {
    final storage = MemoryNotebookStorage();
    final book = GameNotebook(storage: storage);
    final server = FakeServer();
    final session = OnlineGameSession(
        code: '123456',
        uid: 'me',
        room: server.rooms.stream,
        mine: server.mine.stream,
        call: server.call,
        notebook: book);
    Future<void> flush() async {
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    server.mine.add({
      'gen': 0,
      'seat': 1,
      'role': 'merlin',
      'visible': [0, 2]
    });
    server.room({});
    await flush();
    expect(book.opening, isNull, reason: 'stale deal must not save a card');
    server.mine.add({
      'gen': 1,
      'seat': 1,
      'role': 'percival',
      'visible': [0, 3]
    });
    await flush();
    expect(book.opening, contains('派西維爾'));
    expect(book.opening, contains('1 號 【騎士0】'));
    expect(book.opening, contains('4 號 【騎士3】'));
    expect(book.opening, isNot(contains('3 號 【騎士2】')));
    server.room({
      'phase': 'vote',
      'voted': [0, 1, 2, 3]
    });
    await flush();
    expect(book.proposals, isEmpty);
    final record = {
      'quest': 1,
      'attempt': 1,
      'leader': 0,
      'team': [1, 3],
      'votes': [false, false, true, false, true],
      'approved': false
    };
    server.room({
      'phase': 'team',
      'leader': 1,
      'rejections': 1,
      'proposals': [record]
    });
    await flush();
    expect(book.proposals.single.approved, isFalse);
    final scope = session.notebookScope;
    session.dispose();
    final reopened = GameNotebook(storage: storage);
    await reopened.bind(scope);
    expect(reopened.opening, contains('派西維爾'));
    expect(reopened.proposals.single.leader, 0);
    expect(reopened.proposals.single.votes, [false, false, true, false, true]);
    reopened.dispose();
    await server.rooms.close();
    await server.mine.close();
  });
}
