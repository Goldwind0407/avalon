import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/notebook/notebook_model.dart';
import 'package:avalon_shadow_council/features/game/discussion_model.dart';

class MemoryNotebookStorage implements NotebookStorage {
  final values = <String, String>{};
  bool failRead = false, failWrite = false;
  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('offline storage');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('disk full');
    values[key] = value;
  }
}

class DelayedNotebookStorage extends MemoryNotebookStorage {
  final pending = <String, Completer<String?>>{};
  @override
  Future<String?> read(String key) =>
      (pending[key] = Completer<String?>()).future;
}

void main() {
  test(
      'automatic opening and rejected ballots survive reopening and clearing manual notes',
      () async {
    final storage = MemoryNotebookStorage();
    final book = GameNotebook(storage: storage);
    final record = ProposalRecord(
        quest: 1,
        attempt: 1,
        leader: 2,
        team: [0, 3],
        votes: [true, false, false, false, true]);
    await book
        .synchronize('room/me/1', opening: '梅林\n2 號【小明】', proposals: [record]);
    await book.setPlayerText('u', '手動推理');
    await book.clear();
    await book.synchronize('room/me/1', opening: '不應覆蓋最初情報', proposals: []);
    book.dispose();
    final reopened = GameNotebook(storage: storage);
    await reopened.bind('room/me/1');
    expect(reopened.opening, '梅林\n2 號【小明】');
    expect(reopened.proposals.single.approved, isFalse);
    expect(reopened.proposals.single.votes, [true, false, false, false, true]);
    expect(reopened.player('u').text, isEmpty);
    await reopened.bind('room/me/2');
    expect(reopened.opening, isNull);
    expect(reopened.proposals, isEmpty);
    reopened.dispose();
  });
  test(
      'notes and manual marks survive reopening; UID, room and deal are isolated',
      () async {
    final storage = MemoryNotebookStorage();
    final first = GameNotebook(storage: storage);
    await first.bind('room-a/me/1');
    await first.setPlayerText('u1', '第一輪一直替隊長說話');
    await first.mark('u1', SuspectedSide.good);
    await first.setQuestText(0, '先觀察 2、4 號');
    final reopened = GameNotebook(storage: storage);
    await reopened.bind('room-a/me/1');
    expect(reopened.player('u1').text, '第一輪一直替隊長說話');
    expect(reopened.player('u1').side, SuspectedSide.good);
    expect(reopened.quest(0), '先觀察 2、4 號');
    for (final scope in ['room-a/other/1', 'room-b/me/1', 'room-a/me/2']) {
      await reopened.bind(scope);
      expect(reopened.player('u1').text, isEmpty);
      expect(reopened.player('u1').side, isNull);
      expect(reopened.quest(0), isEmpty);
    }
    await reopened.bind('room-a/me/1');
    await reopened.mark('u1', SuspectedSide.evil);
    expect(reopened.player('u1').side, SuspectedSide.evil);
    await reopened.mark('u1', SuspectedSide.evil);
    expect(reopened.player('u1').side, isNull);
    await reopened.clear();
    await first.bind('other');
    await first.bind('room-a/me/1');
    expect(first.player('u1').text, isEmpty);
    expect(first.quest(0), isEmpty);
    first.dispose();
    reopened.dispose();
  });

  test(
      'late loading cannot put another deal or player notes into the current book',
      () async {
    final storage = DelayedNotebookStorage();
    final notes = GameNotebook(storage: storage);
    final a = notes.bind('a');
    await Future<void>.delayed(Duration.zero);
    final b = notes.bind('b');
    await Future<void>.delayed(Duration.zero);
    storage.pending['avalon.notebook.v1/b']!
        .complete('{"players":{"u":{"text":"B"}}}');
    await b;
    storage.pending['avalon.notebook.v1/a']!
        .complete('{"players":{"u":{"text":"A"}}}');
    await a;
    expect(notes.player('u').text, 'B');
    notes.dispose();
  });

  test(
      'load errors can retry and do not overwrite existing notes with an empty book',
      () async {
    final storage = MemoryNotebookStorage()..failRead = true;
    final notes = GameNotebook(storage: storage);
    await notes.bind('a');
    expect(notes.error, isNotNull);
    await notes.setPlayerText('u', 'must not overwrite unread notes');
    expect(storage.values, isEmpty);
    storage.failRead = false;
    await notes.bind('a');
    await notes.setPlayerText('u', '已恢復');
    expect(notes.error, isNull);
    storage.failWrite = true;
    await notes.setPlayerText('u', '仍保留在記憶體');
    expect(notes.player('u').text, '仍保留在記憶體');
    expect(notes.error, isNotNull);
    notes.dispose();
  });
}
