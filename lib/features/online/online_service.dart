import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';
import '../game/game_session.dart';

/// Talks to the Firebase project: sign-in, the game server's functions and
/// the room documents.
///
/// To play against the local emulators (no Blaze plan needed), run the app
/// with `--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2` (Android emulator)
/// or the computer's LAN address (real phones on the same Wi-Fi).
class OnlineService {
  OnlineService._();
  static final instance = OnlineService._();

  static const _emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
  static const region = 'asia-east1';

  Future<void>? _starting;

  Future<void> _start() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
    }
    if (_emulatorHost.isNotEmpty) {
      await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
      _functions.useFunctionsEmulator(_emulatorHost, 5001);
    }
  }

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: region);

  /// Signs in anonymously (once per install) and returns this player's id.
  /// The same id comes back after restarting the app, so players keep
  /// their seat when they rejoin a room.
  Future<String> signIn() async {
    try {
      await (_starting ??= _start());
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      return user!.uid;
    } on FirebaseException catch (e) {
      _starting = null;
      throw GameMoveException('無法連線：${e.message ?? e.code}');
    }
  }

  String? get uid =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;

  /// Calls one of the game server's functions (functions/src/index.ts).
  Future<Map<String, dynamic>> call(
      String name, Map<String, Object?> data) async {
    await signIn();
    try {
      final result = await _functions.httpsCallable(name).call(data);
      return Map<String, dynamic>.from(result.data as Map? ?? const {});
    } on FirebaseFunctionsException catch (e) {
      throw GameMoveException(e.message ?? '連線發生錯誤，請再試一次');
    } on FirebaseException catch (e) {
      throw GameMoveException('連線發生錯誤：${e.message ?? e.code}');
    }
  }

  Stream<Map<String, dynamic>?> room(String code) => FirebaseFirestore.instance
      .doc('rooms/$code')
      .snapshots()
      .map((s) => s.data());

  /// This player's own role. Nobody else can read it (firestore.rules).
  Stream<Map<String, dynamic>?> mine(String code, String uid) =>
      FirebaseFirestore.instance
          .doc('rooms/$code/private/$uid')
          .snapshots()
          .map((s) => s.data());
}
