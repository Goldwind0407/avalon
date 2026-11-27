/// The numbers the computers' balance rests on, in one place so simulated
/// games can tune them (test/tune_test.dart).
///
/// A value may differ between small tables (up to six players) and large
/// ones, or at one table size: `name@8` before `name@small` / `name@large`
/// before `name`, before the default in
/// the code. [tuned] holds what the last tuning settled on; a tuning run
/// tries other values through [override].
class BotTuning {
  BotTuning._();

  /// Settled by test/tune_test.dart (2026-11-27: 4 rounds of 1800 games,
  /// then 2 of 2400 with a quarter of them silent and each size apart with
  /// and without Lancelot, then 3 for Lancelot's own factors and the sizes),
  /// aiming at good winning 47% everywhere, the first quest failing 20% and
  /// the Assassin finding Merlin 35%. Checked on 6000 fresh games against
  /// the code's own numbers: good wins 42% → 47%, first quests failed
  /// 32% → 27%, Merlin found 44% → 41%, the miss under a third.
  static const tuned = <String, double>{
    'merlinCover@small': 5.8819,
    'merlinCover@7': 8.424,
    'merlinCover@8': 7.2676,
    'merlinCover@9': 10.8607,
    'merlinCover@10': 9.0228,
    'merlinVoiceInsight@small': 0.1166,
    'merlinVoiceInsight@large': 0.1179,
    'assassinNoise@small': 1.3236,
    'assassinNoise@7': 1.7379,
    'assassinNoise@8': 1.2726,
    'assassinNoise@9': 0.7927,
    'assassinNoise@10': 0.9729,
    'evilPush@small': 0.963,
    'evilPush@7': 1.1575,
    'evilPush@8': 1.2635,
    'evilPush@9': 0.7757,
    'evilPush@10': 1.1818,
    'voteEvidence@small': 1.2019,
    'voteEvidence@7': 1.3001,
    'voteEvidence@8': 1.4602,
    'voteEvidence@9': 0.941,
    'voteEvidence@10': 1.0506,
    'doubt@small': 0.0826,
    'doubt@large': -0.016,
    'questConceal@small': 0.2118,
    'questConceal@large': 0.1511,
    'evilLeaderCover@small': 0.566,
    'evilLeaderCover@large': 0.4359,
    'firstQuestCover': 0.5486,
    'firstQuestCoverLarge': 0.5053,
    'lastChanceRisk': 3.4294,
    'tableDoubtWeight': 1.4481,
    'lancelotConceal': 0.5391,
    'lonelyFail': 0.2203,
    'switchAge': 0.5506,
    'ladyCorroboration': 0.6,
    'callWeight': 0.0917,
    'lieLowShare': 1.4602,
    'earlyShare': 0.5871,
    'lieLowQ1': 0.5367,
    'lieLowQ2': 0.2212,
    'lieLowPair': 0.9259,
    'earlyCut': 0.2493,
    'hiddenShare': 1.593,
    'guideShare': 1.3344,
    'hiddenCover': 1.3111,
    'guideCover': 0.4203,
    'voteEvidence@Lan': 0.8801,
    'evilPush@Lan': 1.3254,
    'merlinCover@Lan': 0.9519,
    'assassinNoise@Lan': 1.2744,
    'questConceal@Lan': 1.18,
    'evilLeaderCover@Lan': 1.0506,
  };

  static final _override = <String, double>{};

  /// Simulations only: these values instead of [tuned] (empty restores it).
  static void override(Map<String, double> values) => _override
    ..clear()
    ..addAll(values);

  /// [name]'s value at a table of [players] (default [fallback]).
  ///
  /// At a table with Lancelot, the Lady of the Lake or Excalibur,
  /// `name@Lan`, `name@Lady`, `name@Sword` (where set) scale the value:
  /// those games play differently enough to need their own balance.
  static double of(String name, double fallback, int players,
      {bool lancelot = false, bool lady = false, bool excalibur = false}) {
    final size = players <= 6 ? 'small' : 'large';
    var value = fallback;
    for (final key in ['$name@$players', '$name@$size', name]) {
      if (_override[key] ?? tuned[key] case final v?) {
        value = v;
        break;
      }
    }
    double factor(String tag) =>
        _override['$name@$tag'] ?? tuned['$name@$tag'] ?? 1;
    if (lancelot) value *= factor('Lan');
    if (lady) value *= factor('Lady');
    if (excalibur) value *= factor('Sword');
    return value;
  }

  /// Every name the tuning may set, with the code's value (a factor of 1 for
  /// those that scale a level's own setting).
  static const names = <String, double>{
    'merlinCover': 6.0,
    'merlinVoiceInsight': .1,
    'assassinNoise': 1.0, // × the level's own
    'evilPush': 1.0, // × the push table
    'evilLeaderCover': .6,
    'questConceal': .16,
    'firstQuestCover': .7,
    'firstQuestCoverLarge': .45,
    'voteEvidence': 1.0, // × the level's own
    'doubt': 0.0, // + the level's own
    'lastChanceRisk': 4.0,
    'tableDoubtWeight': 1.0,
    'lancelotConceal': .6,
    'lonelyFail': .25,
    'switchAge': .4,
    'ladyCorroboration': .6,
    'callWeight': .08,
    // this game's tactics (see BotTactic)
    'lieLowShare': 1.0, // × the style's chance
    'earlyShare': 1.0,
    'lieLowQ1': .3,
    'lieLowQ2': .15,
    'lieLowPair': .8,
    'earlyCut': .35,
    'hiddenShare': 1.0,
    'guideShare': 1.0,
    'hiddenCover': 1.5,
    'guideCover': .5,
  };
}
