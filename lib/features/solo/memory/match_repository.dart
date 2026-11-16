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

  /// The index as stored, or null when it could not be read this time
  /// (storage trouble, or text that is not a list). Null is not "no games":
  /// nothing may be written over an index that could not be read.
  Future<_Index?> _read() async {
    final String? text;
    try {
      text = await _storage.read(_indexKey);
    } catch (_) {
      return null;
    }
    if (text == null) return _Index([], []); // first use: no games yet
    try {
      final summaries = <MatchSummary>[];
      final unreadable = <Object?>[];
      for (final entry in jsonDecode(text) as List) {
        try {
          summaries.add(MatchSummary.fromMap(Map<String, dynamic>.from(entry)));
        } catch (_) {
          // kept as it is, for a later version that can read it
          unreadable.add(entry);
        }
      }
      return _Index(summaries, unreadable);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(_Index index) => _storage.write(
      _indexKey,
      jsonEncode([
        for (final s in index.summaries) s.toMap(),
        ...index.unreadable,
      ]));

  /// Newest first. Games saved before the current way of summing up are
  /// worked out again from their full record, each on its own; one whose
  /// record cannot be read this time stays as it was, without its habit
  /// counts (so nothing stale is learned), and is tried again next time.
  Future<List<MatchSummary>> summaries() => _serial(() async {
        final index = await _read();
        if (index == null) return [];
        final list = index.summaries;
        final stored = List.of(list);
        var changed = false;
        for (var i = 0; i < list.length; i++) {
          if (list[i].version >= MatchSummary.currentVersion) continue;
          String? text;
          var readable = true;
          try {
            text = await _storage.read(_matchKey(list[i].id));
          } catch (_) {
            readable = false;
          }
          MatchArchive? match;
          if (text != null) {
            try {
              match = MatchArchive.fromMap(
                  Map<String, dynamic>.from(jsonDecode(text) as Map));
            } catch (_) {
              readable = false;
            }
          }
          if (match != null) {
            list[i] = match.summary;
            changed = true;
          } else if (readable) {
            // the record is gone for good: nothing left to learn from it
            list[i] = list[i].withTraits(const {});
            changed = true;
          } else {
            // try again next time; meanwhile its old counts are not used
            list[i] = list[i].withoutTraits();
          }
        }
        if (changed) {
          try {
            await _write(_Index([
              for (var i = 0; i < list.length; i++)
                // an entry still waiting keeps its stored form
                list[i].version >= MatchSummary.currentVersion
                    ? list[i]
                    : stored[i]
            ], index.unreadable));
          } catch (_) {}
        }
        return list;
      });

  /// Saving the same game twice keeps one copy. When the list of games
  /// cannot be read, nothing is written: a game not remembered is better
  /// than a history lost.
  Future<void> save(MatchArchive match) => _serial(() async {
        try {
          final index = await _read();
          if (index == null) return;
          final list = index.summaries;
          if (list.any((s) => s.id == match.id)) return;
          await _storage.write(_matchKey(match.id), jsonEncode(match.toMap()));
          list.insert(0, match.summary);
          // The list first: if it cannot be written, the old games it
          // still names must still be there. A record left behind by a
          // failed removal only takes up room.
          await _write(_Index(list.take(limit).toList(), index.unreadable));
          for (final old in list.skip(limit)) {
            try {
              await _storage.remove(_matchKey(old.id));
            } catch (_) {}
          }
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
          final index = await _read();
          if (index == null) return;
          await _write(_Index([
            for (final s in index.summaries)
              if (s.id != id) s
          ], index.unreadable));
          await _storage.remove(_matchKey(id));
        } catch (_) {}
      });

  Future<void> clear() => _serial(() async {
        try {
          final index = await _read();
          if (index == null) return;
          await _storage.remove(_indexKey);
          for (final s in index.summaries) {
            try {
              await _storage.remove(_matchKey(s.id));
            } catch (_) {}
          }
        } catch (_) {}
      });
}

/// The list of past games as stored: what this version can read, and
/// entries it cannot, kept as they are.
class _Index {
  _Index(this.summaries, this.unreadable);
  final List<MatchSummary> summaries;
  final List<Object?> unreadable;
}
