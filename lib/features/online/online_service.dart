import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../firebase_options.dart';
import '../game/game_session.dart';
import '../../core/web_page.dart';

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
  bool _checked = false;

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
      // once a run: an account saved earlier may no longer be usable (say,
      // one from the local test servers); it is replaced before anyone
      // is given its id
      if (!_checked && auth.currentUser != null) {
        _checked = true;
        await _renewDeadAccount();
      }
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      return user!.uid;
    } on FirebaseException catch (e) {
      _starting = null;
      throw GameMoveException('無法連線：${e.message ?? e.code}');
    }
  }

  /// Sign-in errors that mean the saved account can no longer be used (it
  /// was removed, or it came from the local test servers). A network
  /// error is not one: the account is fine, the phone is offline.
  static const _deadAccount = {
    'user-not-found',
    'user-disabled',
    'invalid-user-token',
    'user-token-expired',
    'invalid-credential',
    'invalid-api-key',
  };

  /// When the saved account turns out to be unusable, starts a new one.
  /// Returns whether it did (then the call is worth trying again).
  Future<bool> _renewDeadAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await user.getIdToken(true);
      return false;
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) debugPrint('account check: ${e.code} ${e.message}');
      // some come back as "unknown" with the reason only in the message
      final message = e.message ?? '';
      if (!_deadAccount.contains(e.code) &&
          !RegExp(r'INVALID_REFRESH_TOKEN|USER_NOT_FOUND|TOKEN_EXPIRED|USER_DISABLED|INVALID_ID_TOKEN')
              .hasMatch(message)) {
        return false;
      }
      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance.signInAnonymously();
      return true;
    } catch (_) {
      return false;
    }
  }

  String? get uid =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;

  // ───────────── Google sign-in (online play needs it) ─────────────

  /// The project's web client id (google-services.json, client_type 3):
  /// Android needs it to be given an id token Firebase accepts.
  static const googleWebClientId = String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
      defaultValue: _projectWebClientId);

  /// The project's iOS client (GoogleService-Info.plist CLIENT_ID).
  static const googleIosClientId =
      '1041864366616-e8ta8flfofc0qtqhrmk5onl38pacpmsd.apps.googleusercontent.com';

  static const _projectWebClientId =
      '1041864366616-9plva6mu2o1907fidh4531jbdvl6a0si.apps.googleusercontent.com';

  Future<void>? _googleReady;

  /// Whether this phone is signed in with a Google account.
  Future<bool> hasGoogle() async {
    try {
      // no Firebase to be had (no network at start, tests): not signed in
      await (_starting ??= _start()).timeout(const Duration(seconds: 5));
    } catch (_) {
      _starting = null;
      return false;
    }
    return _withGoogle(FirebaseAuth.instance.currentUser);
  }

  static bool _withGoogle(User? user) =>
      user != null &&
      user.providerData.any((p) => p.providerId == 'google.com');

  /// The Google account signed in, for the player to see which one.
  String? get googleAccount {
    if (Firebase.apps.isEmpty) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (!_withGoogle(user)) return null;
    return user!.email ?? user.displayName;
  }

  /// The name on the Google account, to start the nickname from.
  String? get googleName {
    if (Firebase.apps.isEmpty) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    // a linked account keeps its own (empty) name: the Google one has it
    for (final p in user.providerData) {
      if (p.providerId == 'google.com' && (p.displayName ?? '').isNotEmpty) {
        return p.displayName;
      }
    }
    return user.displayName;
  }

  /// Signs in with Google. An anonymous account already on this phone is
  /// turned into the Google one, so its seats are kept; if that Google
  /// account is in use already, this phone becomes it. Returns the id, or
  /// null when the player backed out.
  Future<String?> signInWithGoogle() async {
    try {
      await (_starting ??= _start());
      final auth = FirebaseAuth.instance;
      final current = auth.currentUser;
      if (kIsWeb && pageIsolated) {
        // the game page cannot hear back from Google's window: the sign-in
        // page does it, and the game opens again at online play
        openSignInPage();
        return null;
      }
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        if (current != null && current.isAnonymous) {
          try {
            await current.linkWithPopup(provider);
          } on FirebaseAuthException catch (e) {
            if (!_alreadyUsed(e)) rethrow;
            await auth.signInWithPopup(provider);
          }
        } else {
          await auth.signInWithPopup(provider);
        }
        return auth.currentUser?.uid;
      }
      final google = GoogleSignIn.instance;
      await (_googleReady ??= google.initialize(
          // iOS needs its own client (also in Info.plist with its URL scheme)
          clientId: defaultTargetPlatform == TargetPlatform.iOS
              ? googleIosClientId
              : null,
          serverClientId:
              googleWebClientId.isEmpty ? null : googleWebClientId));
      final GoogleSignInAccount account;
      try {
        account = await google.authenticate();
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled ||
            e.code == GoogleSignInExceptionCode.interrupted) {
          return null;
        }
        rethrow;
      }
      final credential = GoogleAuthProvider.credential(
          idToken: account.authentication.idToken);
      if (current != null && current.isAnonymous) {
        try {
          await current.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          if (!_alreadyUsed(e)) rethrow;
          await auth.signInWithCredential(e.credential ?? credential);
        }
      } else {
        await auth.signInWithCredential(credential);
      }
      _checked = true;
      return auth.currentUser?.uid;
    } on FirebaseAuthException catch (e) {
      throw GameMoveException('Google 登入失敗：${e.message ?? e.code}');
    } on GoogleSignInException catch (e) {
      throw GameMoveException('Google 登入失敗：${e.description ?? e.code.name}');
    } on FirebaseException catch (e) {
      throw GameMoveException('Google 登入失敗：${e.message ?? e.code}');
    }
  }

  static bool _alreadyUsed(FirebaseAuthException e) => const {
        'credential-already-in-use',
        'email-already-in-use',
        'provider-already-linked',
      }.contains(e.code);

  /// Signs this phone out of its Google account (back to a fresh start).
  Future<void> signOutGoogle() async {
    try {
      if (!kIsWeb) await GoogleSignIn.instance.signOut();
    } catch (_) {/* not signed in there */}
    await FirebaseAuth.instance.signOut();
  }

  /// Calls one of the game server's functions (functions/src/index.ts).
  /// The rooms where this account still has a seat, most recent first.
  Future<List<MyRoom>> myRooms() async {
    await signIn();
    final found = await call('myRooms', const {});
    return [
      for (final r in found['rooms'] as List? ?? const [])
        if (r is Map)
          MyRoom(
              code: '${r['code']}',
              status: '${r['status']}',
              players: (r['players'] as num?)?.toInt() ?? 0,
              host: '${r['host'] ?? ''}',
              finished: r['finished'] == true)
    ];
  }

  Future<Map<String, dynamic>> call(
      String name, Map<String, Object?> data) async {
    await signIn();
    Future<Map<String, dynamic>> once() async {
      final result = await _functions
          .httpsCallable(name)
          .call({'protocolVersion': 5, ...data});
      return Map<String, dynamic>.from(result.data as Map? ?? const {});
    }

    try {
      try {
        return await once();
      } on FirebaseFunctionsException catch (e) {
        if (kDebugMode) {
          debugPrint('callable $name: ${e.code} ${e.message} ${e.details}');
        }
        // the phone could not even present who it is: the saved account
        // may be one the server does not know; with a new one, once more
        if (e.code != 'internal' &&
            e.code != 'unknown' &&
            e.code != 'unauthenticated') {
          rethrow;
        }
        if (!await _renewDeadAccount()) rethrow;
        return await once();
      }
    } on FirebaseFunctionsException catch (e) {
      throw GameMoveException(_readable(e));
    } on FirebaseException catch (e) {
      throw GameMoveException('連線發生錯誤：${e.message ?? e.code}');
    }
  }

  /// The server's own message, or plain words for a failure on the phone
  /// (whose text is a Java exception nobody should have to read).
  static String _readable(FirebaseFunctionsException e) {
    final message = e.message;
    if (message == null ||
        message.contains('Exception') ||
        message.contains('underlying tasks')) {
      return e.code == 'unavailable' || e.code == 'deadline-exceeded'
          ? '連不上伺服器，請檢查網路後再試'
          : '連線發生錯誤，請稍後再試';
    }
    return message;
  }

  Stream<Map<String, dynamic>?> room(String code) => FirebaseFirestore.instance
      .doc('rooms/$code')
      .snapshots()
      .where((s) => s.exists || !s.metadata.isFromCache)
      .map((s) => s.data());

  /// Tells the server this phone is here (rooms/{code}/presence/{uid}); a
  /// player not heard from for a minute is played for until they are back.
  /// [now] is the server's time as this phone reckons it.
  Future<void> beat(String code, String uid, int now) =>
      FirebaseFirestore.instance.doc('rooms/$code/presence/$uid').set({
        'at': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromMillisecondsSinceEpoch(
            now + const Duration(days: 1).inMilliseconds),
      });

  /// A finished game, whole, as the server kept it for the players
  /// (rooms/{code}/reviews/{roomId}-{gen}); null when there is none.
  /// Reviews kept before rooms had their own ids are under the deal number
  /// alone, and are still found there.
  Future<Map<String, dynamic>?> review(
      String code, String? roomId, int gen) async {
    Future<Map<String, dynamic>?> at(String id) async {
      try {
        return (await FirebaseFirestore.instance
                .doc('rooms/$code/reviews/$id')
                .get(const GetOptions(source: Source.server)))
            .data();
      } on FirebaseException catch (e) {
        // not one of those who played it (or not there): nothing to show
        if (e.code == 'permission-denied') return null;
        rethrow;
      }
    }

    final kept = roomId == null ? null : await at('$roomId-$gen');
    return kept ?? await at('$gen');
  }

  /// This player's own role. Nobody else can read it (firestore.rules).
  Stream<Map<String, dynamic>?> mine(String code, String uid) =>
      FirebaseFirestore.instance
          .doc('rooms/$code/private/$uid')
          .snapshots()
          .map((s) => s.data());
}

/// A room where the player still has a seat (see [OnlineService.myRooms]).
class MyRoom {
  const MyRoom(
      {required this.code,
      required this.status,
      required this.players,
      required this.host,
      required this.finished});
  final String code, status, host;
  final int players;
  final bool finished;
}
