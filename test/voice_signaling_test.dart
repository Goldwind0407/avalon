// Firestore interfaces are faked only at the SDK boundary in these unit tests.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/online/voice/voice_signaling.dart';

class RecordingFirestore extends Fake implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{
    'rooms/123456': {'voiceRoomId': 'current-room'},
  };
  int reads = 0;
  @override
  DocumentReference<Map<String, dynamic>> doc(String path) =>
      RecordingDocument(this, path);
  @override
  Future<T> runTransaction<T>(TransactionHandler<T> handler,
          {Duration timeout = const Duration(seconds: 30),
          int maxAttempts = 5}) =>
      handler(RecordingTransaction(this));
}

class RecordingSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  RecordingSnapshot(this.value);
  final Map<String, dynamic>? value;
  @override
  Map<String, dynamic>? data() => value;
}

class RecordingDocument extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  RecordingDocument(this.db, this.path);
  final RecordingFirestore db;
  @override
  final String path;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
      [GetOptions? options]) async {
    db.reads++;
    return RecordingSnapshot(db.documents[path]);
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String name) =>
      RecordingCollection(db, '$path/$name');
}

class RecordingCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  RecordingCollection(this.db, this.path);
  final RecordingFirestore db;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      RecordingDocument(db, '$path/$id');
  @override
  Future<DocumentReference<Map<String, dynamic>>> add(
      Map<String, dynamic> data) async {
    final ref = doc('message');
    db.documents[ref.path] = data;
    return ref;
  }
}

class RecordingTransaction extends Fake implements Transaction {
  RecordingTransaction(this.db);
  final RecordingFirestore db;
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
          DocumentReference<T> ref) async =>
      RecordingSnapshot(db.documents[ref.path]) as DocumentSnapshot<T>;
  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    db.documents[ref.path] = Map<String, dynamic>.from(data as Map);
    return this;
  }

  @override
  Transaction delete(DocumentReference ref) {
    db.documents.remove(ref.path);
    return this;
  }
}

void main() {
  test(
      'presence waits for clock synchronization and signals use server-adjusted deadlines',
      () async {
    final db = RecordingFirestore();
    final clockReady = Completer<void>();
    var serverNow = 1700000000000;
    final signaling = FirestoreVoiceSignaling('123456',
        db: db, now: () => serverNow, clockReady: clockReady.future);
    final announcement =
        signaling.announce(const VoicePresence('me', 'my-session'));
    await Future<void>.value();
    expect(db.reads, 0,
        reason: 'Do not create a deadline using an unsynchronized phone clock');
    clockReady.complete();
    await announcement;
    expect(
        (db.documents['rooms/123456/voice/me']!['expireAt'] as Timestamp)
            .millisecondsSinceEpoch,
        serverNow + 90000);
    serverNow += 30000;
    await signaling.send(const VoiceSignal(
        from: 'me',
        fromSession: 'my-session',
        to: 'other',
        toSession: 'their-session',
        attempt: 1,
        kind: 'offer',
        data: {'sdp': 'offer'}));
    expect(
        (db.documents['rooms/123456/voiceSignals/message']!['expireAt']
                as Timestamp)
            .millisecondsSinceEpoch,
        serverNow + 300000);
  });

  test('a late withdrawal cannot delete a newer session on the same UID',
      () async {
    final db = RecordingFirestore();
    final signaling = FirestoreVoiceSignaling('123456', db: db);
    const me = VoicePresence('me', 'old-session');
    await signaling.announce(me);
    db.documents['rooms/123456/voice/me']!['session'] = 'new-session';
    await signaling.withdraw(me);
    expect(db.documents['rooms/123456/voice/me']!['session'], 'new-session');
  });
}
