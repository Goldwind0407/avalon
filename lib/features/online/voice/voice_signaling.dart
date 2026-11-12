import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'voice_controller.dart';

class VoicePresence {
  const VoicePresence(this.uid, this.session);
  final String uid, session;
}

class VoiceSignal {
  const VoiceSignal(
      {this.id = '',
      required this.from,
      required this.fromSession,
      required this.to,
      required this.toSession,
      required this.attempt,
      required this.kind,
      required this.data,
      this.order = 0});
  final String id, from, fromSession, to, toSession, kind;
  final int attempt, order;
  final Map<String, dynamic> data;
}

/// Only connection metadata crosses Firestore; no audio or game secrets.
abstract class VoiceSignaling {
  Stream<List<VoicePresence>> presence();
  Stream<List<VoiceSignal>> inbox(String uid);
  Future<void> announce(VoicePresence me);
  Future<void> withdraw(VoicePresence me);
  Future<void> send(VoiceSignal signal);
  Future<void> consume(String id);
}

class FirestoreVoiceSignaling implements VoiceSignaling {
  FirestoreVoiceSignaling(this.code,
      {FirebaseFirestore? db, int Function()? now, Future<void>? clockReady})
      : _db = db ?? FirebaseFirestore.instance,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _clockReady = clockReady ?? Future.value();
  final String code;
  final FirebaseFirestore _db;
  final int Function() _now;
  final Future<void> _clockReady;
  String? _roomId;
  bool _announced = false;
  int _order = 0;
  DocumentReference<Map<String, dynamic>> get _room => _db.doc('rooms/$code');
  CollectionReference<Map<String, dynamic>> get _people =>
      _room.collection('voice');
  CollectionReference<Map<String, dynamic>> get _signals =>
      _room.collection('voiceSignals');

  @override
  Stream<List<VoicePresence>> presence() => Stream.multi((sink) {
        Map<String, dynamic>? room;
        List<QueryDocumentSnapshot<Map<String, dynamic>>>? people;
        void emit() {
          if (room == null || people == null) return;
          if (room!['voiceRoomId'] != _roomId) {
            sink.addError(const VoiceException('房間已變更，請重新加入語音'));
            return;
          }
          final members = List<String>.from(room!['playerUids'] as List);
          sink.add([
            for (final doc in people!)
              if (members.contains(doc.id) &&
                  doc.data()['roomId'] == _roomId &&
                  (doc.data()['expireAt'] as Timestamp).millisecondsSinceEpoch >
                      _now())
                VoicePresence(doc.id, doc.data()['session'] as String)
          ]);
        }

        final roomSub = _room.snapshots().listen((snapshot) {
          room = snapshot.data();
          if (room == null) {
            sink.addError(const VoiceException('房間已關閉'));
          } else {
            emit();
          }
        }, onError: sink.addError);
        final peopleSub = _people.snapshots().listen((snapshot) {
          people = snapshot.docs;
          emit();
        }, onError: sink.addError);
        // TTL deletion is asynchronous; expire crashed phones locally as well.
        final timer =
            Timer.periodic(const Duration(seconds: 15), (_) => emit());
        sink.onCancel = () async {
          timer.cancel();
          await Future.wait([roomSub.cancel(), peopleSub.cancel()]);
        };
      });

  @override
  Stream<List<VoiceSignal>> inbox(String uid) =>
      _signals.where('to', isEqualTo: uid).snapshots().map((snapshot) => [
            for (final doc in snapshot.docs)
              if (doc.data()['roomId'] == _roomId &&
                  (doc.data()['expireAt'] as Timestamp).millisecondsSinceEpoch >
                      _now())
                VoiceSignal(
                    id: doc.id,
                    from: doc.data()['from'] as String,
                    fromSession: doc.data()['fromSession'] as String,
                    to: doc.data()['to'] as String,
                    toSession: doc.data()['toSession'] as String,
                    attempt: doc.data()['attempt'] as int,
                    kind: doc.data()['kind'] as String,
                    data: Map<String, dynamic>.from(doc.data()['data'] as Map),
                    order: doc.data()['order'] as int)
          ]);

  @override
  Future<void> announce(VoicePresence me) async {
    if (_roomId == null) {
      await _clockReady;
      final room =
          (await _room.get(const GetOptions(source: Source.server))).data();
      _roomId = room?['voiceRoomId'] as String?;
      if (_roomId == null) throw const VoiceException('請更新伺服器並建立新房間後使用語音');
    }
    await _db.runTransaction((tx) async {
      final ref = _people.doc(me.uid);
      final current = await tx.get(ref);
      if (_announced && current.data()?['session'] != me.session) {
        throw const VoiceException('語音已中斷或在其他裝置開啟，請重新加入');
      }
      tx.set(ref, {
        'uid': me.uid,
        'session': me.session,
        'roomId': _roomId,
        'expireAt': Timestamp.fromMillisecondsSinceEpoch(_now() + 90000),
      });
    });
    _announced = true;
  }

  @override
  Future<void> withdraw(VoicePresence me) => _db.runTransaction((tx) async {
        final doc = _people.doc(me.uid);
        final current = await tx.get(doc);
        // A delayed disconnect must not erase a newer connection on this UID.
        if (current.data()?['session'] == me.session &&
            current.data()?['roomId'] == _roomId) {
          tx.delete(doc);
        }
      }).timeout(const Duration(seconds: 3));

  @override
  Future<void> send(VoiceSignal signal) async {
    await _signals.add({
      'from': signal.from,
      'fromSession': signal.fromSession,
      'to': signal.to,
      'toSession': signal.toSession,
      'roomId': _roomId,
      'attempt': signal.attempt,
      'kind': signal.kind,
      'data': signal.data,
      'order': _order++,
      'expireAt': Timestamp.fromMillisecondsSinceEpoch(_now() + 300000),
    });
  }

  @override
  Future<void> consume(String id) => _signals.doc(id).delete();
}
