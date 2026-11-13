import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'match_archive.dart';

abstract class MatchStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class LocalMatchStorage implements MatchStorage {
  SharedPreferencesAsync? _instance;
  SharedPreferencesAsync get _preferences =>
      _instance ??= SharedPreferencesAsync();
  @override
  Future<String?> read(String key) => _preferences.getString(key);
  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
  @override
  Future<void> remove(String key) => _preferences.remove(key);
}

/// For tests, and for a device whose storage cannot be used.
class MemoryMatchStorage implements MatchStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}

/// Finished solo games, on this device only. A short index answers "what
/// happened lately"; the full record of a game is read only when opened.
/// Storage trouble never reaches the game: a save that fails is a game that
/// is not remembered.
class MatchRepository {
  MatchRepository({MatchStorage? storage, this.limit = 40})
      : _storage = storage ?? LocalMatchStorage();

  /// The one the app uses; tests pass their own.
  static final shared = MatchRepository();
  final MatchStorage _storage;

  /// Older games are forgotten beyond this many.
  final int limit;
  static const _indexKey = 'avalon.solo.matches.v1';
  static String _matchKey(String id) => 'avalon.solo.match.v1/$id';
  Future<void> _queue = Future.value();

  /// One write at a time, so two saves cannot overwrite each other's index.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<MatchSummary>> _read() async {
    try {
      final text = await _storage.read(_indexKey);
      if (text == null) return [];
      final summaries = <MatchSummary>[];
      for (final entry in jsonDecode(text) as List) {
        try {
          summaries.add(MatchSummary.fromMap(Map<String, dynamic>.from(entry)));
        } catch (_) {
          // one unreadable entry does not lose the others
        }
      }
      return summaries;
    } catch (_) {
      return [];
    }
  }

  /// Newest first.
  Future<List<MatchSummary>> summaries() => _serial(_read);

  /// Saving the same game twice keeps one copy.
  Future<void> save(MatchArchive match) => _serial(() async {
        try {
          final list = await _read();
          if (list.any((s) => s.id == match.id)) return;
          await _storage.write(_matchKey(match.id), jsonEncode(match.toMap()));
          list.insert(0, match.summary);
          for (final old in list.skip(limit)) {
            await _storage.remove(_matchKey(old.id));
          }
          await _storage.write(_indexKey,
              jsonEncode([for (final s in list.take(limit)) s.toMap()]));
        } catch (_) {}
      });

  Future<MatchArchive?> load(String id) => _serial(() async {
        try {
          final text = await _storage.read(_matchKey(id));
          if (text == null) return null;
          return MatchArchive.fromMap(
              Map<String, dynamic>.from(jsonDecode(text) as Map));
        } catch (_) {
          return null;
        }
      });

  Future<void> delete(String id) => _serial(() async {
        try {
          final list = await _read();
          await _storage.remove(_matchKey(id));
          await _storage.write(
              _indexKey,
              jsonEncode([
                for (final s in list)
                  if (s.id != id) s.toMap()
              ]));
        } catch (_) {}
      });

  Future<void> clear() => _serial(() async {
        try {
          for (final s in await _read()) {
            await _storage.remove(_matchKey(s.id));
          }
          await _storage.remove(_indexKey);
        } catch (_) {}
      });
}
