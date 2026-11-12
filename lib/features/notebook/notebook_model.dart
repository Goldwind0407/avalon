import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:shared_preferences/shared_preferences.dart';
import '../game/discussion_model.dart';

enum SuspectedSide { good, evil }

class PlayerNote {
  const PlayerNote({this.text = '', this.side});
  final String text;
  final SuspectedSide? side;
}

abstract class NotebookStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class LocalNotebookStorage implements NotebookStorage {
  SharedPreferencesAsync? _instance;
  SharedPreferencesAsync get _preferences =>
      _instance ??= SharedPreferencesAsync();
  @override
  Future<String?> read(String key) async => _preferences.getString(key);
  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
}

/// Local notes; never derives marks from roles or sends content to Firebase.
class GameNotebook extends ChangeNotifier {
  GameNotebook({NotebookStorage? storage})
      : _storage = storage ?? LocalNotebookStorage();
  final NotebookStorage _storage;
  final _players = <String, PlayerNote>{};
  final _quests = <int, String>{};
  String? opening;
  List<ProposalRecord> proposals = const [];
  Future<void>? _binding;
  String? _key;
  bool loading = false, _disposed = false, _loadFailed = false;
  bool get canEdit => !loading && !_loadFailed;
  String? error;
  int _generation = 0;
  Future<void> _writes = Future.value();
  static const maxLength = 1000;
  PlayerNote player(String uid) => _players[uid] ?? const PlayerNote();
  String quest(int index) => _quests[index] ?? '';
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> bind(String scope) {
    final key = 'avalon.notebook.v1/$scope';
    if (_key == key && !_loadFailed) return _binding ?? Future.value();
    return _binding = _load(key);
  }

  Future<void> _load(String key) async {
    _key = key;
    final generation = ++_generation;
    _players.clear();
    _quests.clear();
    opening = null;
    proposals = const [];
    loading = true;
    _loadFailed = false;
    error = null;
    _notify();
    try {
      await _writes;
      final raw = await _storage.read(key);
      if (_disposed || generation != _generation) return;
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        opening = data['opening'] as String?;
        proposals = [
          for (final p in data['proposals'] as List? ?? const [])
            ProposalRecord.fromMap(Map<String, dynamic>.from(p as Map))
        ];
        for (final entry in (data['players'] as Map? ?? {}).entries) {
          final note = Map<String, dynamic>.from(entry.value as Map);
          _players[entry.key as String] = PlayerNote(
              text: _trim(note['text'] as String? ?? ''),
              side: switch (note['side']) {
                'good' => SuspectedSide.good,
                'evil' => SuspectedSide.evil,
                _ => null,
              });
        }
        for (final entry in (data['quests'] as Map? ?? {}).entries) {
          final index = int.tryParse(entry.key as String);
          if (index != null &&
              index >= 0 &&
              index < 5 &&
              entry.value is String) {
            _quests[index] = _trim(entry.value as String);
          }
        }
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _players.clear();
      _quests.clear();
      _loadFailed = true;
      error = '暫時無法讀取已存筆記，請關閉筆記本後重試';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  static String _trim(String text) =>
      text.characters.take(maxLength).toString();

  /// Receives only this player's opening knowledge and fully revealed ballots.
  Future<void> synchronize(String scope,
      {String? opening, required List<ProposalRecord> proposals}) async {
    await bind(scope);
    if (_disposed || _key != 'avalon.notebook.v1/$scope' || !canEdit) return;
    final nextOpening = this.opening ?? opening;
    if (nextOpening == this.opening &&
        jsonEncode(proposals.map((p) => p.toMap()).toList()) ==
            jsonEncode(this.proposals.map((p) => p.toMap()).toList())) {
      return;
    }
    this.opening = nextOpening;
    // An older stream snapshot must never erase an already received ballot.
    if (proposals.length >= this.proposals.length) {
      this.proposals = List.unmodifiable(proposals);
    }
    await _save();
  }

  Future<void> setPlayerText(String uid, String text) {
    if (!canEdit || _disposed) return Future.value();
    final old = player(uid);
    _players[uid] = PlayerNote(text: _trim(text), side: old.side);
    return _save();
  }

  Future<void> mark(String uid, SuspectedSide side) {
    if (!canEdit || _disposed) return Future.value();
    final old = player(uid);
    _players[uid] =
        PlayerNote(text: old.text, side: old.side == side ? null : side);
    return _save();
  }

  Future<void> setQuestText(int index, String text) {
    if (!canEdit || _disposed || index < 0 || index >= 5) return Future.value();
    _quests[index] = _trim(text);
    return _save();
  }

  Future<void> clear() {
    if (!canEdit || _disposed) return Future.value();
    _loadFailed = false;
    _players.clear();
    _quests.clear();
    return _save();
  }

  Future<void> _save() {
    final key = _key;
    if (key == null || _disposed) return Future.value();
    error = null;
    _notify();
    final generation = _generation;
    final value = jsonEncode({
      'opening': opening,
      'proposals': proposals.map((p) => p.toMap()).toList(),
      'players': {
        for (final entry in _players.entries)
          entry.key: {'text': entry.value.text, 'side': entry.value.side?.name}
      },
      'quests': {
        for (final entry in _quests.entries) '${entry.key}': entry.value
      },
    });
    return _writes = _writes.then((_) async {
      try {
        await _storage.write(key, value);
      } catch (_) {
        if (!_disposed && generation == _generation) {
          error = '筆記仍保留在本局，暫時無法儲存到手機';
          _notify();
        }
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
