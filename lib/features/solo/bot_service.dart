import 'bot_difficulty.dart';
import 'bot_style.dart';
import 'bot_table.dart';
import 'persona/bot_persona.dart';

// What the computer players' server does with a request, apart from HTTP
// (bot_server/bin/server.dart). No Flutter here.

/// A request the service cannot make sense of.
class BotRequestError implements Exception {
  const BotRequestError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Keeps the computer players of every table that is being played, and
/// answers the referee's "what do they do now?".
///
/// A table lives in memory for as long as its game is asked about. If the
/// server is restarted in the middle of a game the table is made again from
/// the next request: the record, the cards and what each seat was shown all
/// come with it, so the game goes on; only what a computer had in mind and
/// not yet said or done (how it meant to vote, lines it used recently) is
/// thought out afresh.
class BotService {
  BotService({this.keep = const Duration(hours: 3), this.limit = 500});

  /// A table not asked about for this long is forgotten.
  final Duration keep;

  /// Most tables kept at once (the least recently asked about goes first).
  final int limit;
  final _tables = <String, ({BotTable table, DateTime used, String shape})>{};
  int get tables => _tables.length;

  /// `{room, gen, seed, level, players: [{name, bot, persona}], state,
  /// cards, talk}` in, `{say: [...], moves: [...]}` out. See [BotTable.step]
  /// and [TableState.fromServer] for the parts.
  Map<String, dynamic> step(Map request, {DateTime? now}) {
    final at = now ?? DateTime.now();
    T need<T>(String key) {
      final value = request[key];
      if (value is! T) throw BotRequestError('缺少或錯誤的欄位：$key');
      return value;
    }

    final room = need<String>('room');
    final generation = need<int>('gen');
    final seed = need<int>('seed');
    final level = BotDifficulty.values
        .where((d) => d.name == request['level'])
        .firstOrNull;
    if (level == null) throw const BotRequestError('難度不正確');
    final players = need<List>('players');
    final state = need<Map>('state');
    if (players.length != (state['roles'] as List?)?.length) {
      throw const BotRequestError('玩家數與牌局不符');
    }
    final styles = <int, BotStyle>{
      for (final (seat, p) in players.indexed)
        // computers, and people away for now (played for until back)
        if (p is Map && (p['bot'] == true || p['away'] == true))
          seat: BotPersona.byId(p['persona'] as String?)?.style ??
              BotStyle.balanced
    };
    if (styles.isEmpty) return {'say': const [], 'moves': const []};

    _tables.removeWhere((_, t) => at.difference(t.used) > keep);
    final key = '$room/$generation';
    // the deal's seed and the level, in case the same room and deal number
    // ever come back as another table
    final shape = '$seed/${level.name}';
    var entry = _tables.remove(key);
    if (entry == null || entry.shape != shape) {
      entry = (
        table: BotTable(bots: styles, difficulty: level, seed: seed),
        used: at,
        shape: shape
      );
    }
    // who is played for may change during a game: someone goes away, or
    // comes back and takes the seat again
    entry.table.seat(styles);
    _tables[key] = (table: entry.table, used: at, shape: shape);
    while (_tables.length > limit) {
      _tables.remove(_tables.keys.first);
    }

    final TableState table;
    try {
      table = TableState.fromServer(state,
          generation: generation,
          names: [for (final p in players) '${(p as Map)['name']}'],
          cards: request['cards'] as Map?);
    } catch (e) {
      throw BotRequestError('牌局資料無法讀取：$e');
    }
    final result = entry.table.step(table, [
      for (final line in request['talk'] as List? ?? const [])
        if (line is Map) line
    ], players: [
      for (final p in players)
        if (p is Map) p
    ], past: [
      for (final game in request['past'] as List? ?? const [])
        if (game is Map) game
    ]);
    return {'say': result.say, 'moves': result.moves};
  }
}
