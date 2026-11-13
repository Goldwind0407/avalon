import 'dart:math';
import '../bot_style.dart';

/// A computer player who comes back game after game: the same name and the
/// same way of playing, whatever role the deal hands them this time.
class BotPersona {
  const BotPersona(this.id, this.name, this.style, this.bio);

  /// Stable key for saved games; never shown.
  final String id;
  final String name;
  final BotStyle style;

  /// One line the player reads before the game.
  final String bio;

  /// Everyone who can sit at the table (a 10-player game needs nine).
  static const cast = [
    BotPersona('chen', '老陳', BotStyle.cautious, '想清楚才投票，很少第一個表態。'),
    BotPersona('yu', '小魚', BotStyle.impulsive, '想到什麼說什麼，隊伍差不多就讓它過。'),
    BotPersona('pei', '佩佩', BotStyle.follower, '相信誰就跟誰，很重視隊長的說法。'),
    BotPersona('zhe', '阿哲', BotStyle.logical, '只看紀錄，會把每一張票對過一遍。'),
    BotPersona('mia', '米亞', BotStyle.actor, '很會演，拿到壞人牌也看不出來。'),
    BotPersona('kai', '阿凱', BotStyle.aggressive, '講話直接，懷疑誰就當面點名。'),
    BotPersona('rong', '蓉蓉', BotStyle.logical, '話不多，開口通常有憑有據。'),
    BotPersona('wei', '大衛', BotStyle.actor, '笑笑的，什麼牌都說自己是好人。'),
    BotPersona('hu', '小虎', BotStyle.impulsive, '容易被說服，也容易衝動反對。'),
  ];

  static BotPersona? byId(String? id) {
    for (final p in cast) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// [count] different people for one table, with as many different ways of
  /// playing as the table has room for.
  static List<BotPersona> deal(int count, Random random) {
    final order = [...cast]..shuffle(random);
    final picked = <BotPersona>[];
    // one of each style first, then whoever is left
    for (final p in order) {
      if (picked.every((q) => q.style != p.style)) picked.add(p);
    }
    for (final p in order) {
      if (!picked.contains(p)) picked.add(p);
    }
    return picked.take(count).toList()..shuffle(random);
  }
}
