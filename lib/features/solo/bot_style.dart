import 'dart:math';

/// How a computer player likes to play. A style only shifts preferences;
/// it never gives a seat more information than its role allows.
enum BotStyle {
  /// Neutral numbers, used by tests and as the reference for the others.
  balanced('均衡型', '沒有特別偏好'),

  cautious('謹慎型', '不輕易贊成，只派最信任的人',
      trusting: -.05,
      noise: .03,
      blend: 1.2,
      conceal: .08,
      frame: .15,
      disguise: .2),
  impulsive('衝動型', '容易贊成，選隊比較隨興',
      trusting: .08,
      noise: .16,
      selfBias: .14,
      blend: .9,
      conceal: -.04,
      frame: .4,
      disguise: .15),
  follower('跟票型', '信任的隊長說什麼就跟什麼',
      trusting: .03, follow: 2.2, selfBias: .04, frame: .25, disguise: .3),
  logical('邏輯型', '照紀錄推理，立場很少變',
      noise: .02, follow: .8, frame: .3, disguise: .3),
  actor('演技型', '當邪惡時前期裝好人，關鍵局才破壞',
      blend: 1.5, conceal: .2, frame: .25, disguise: .45),
  aggressive('激進型', '當邪惡時有機會就破壞、栽贓',
      trusting: -.02, blend: .5, conceal: -.12, frame: .65, disguise: .15);

  const BotStyle(this.label, this.description,
      {this.trusting = 0,
      this.follow = 1,
      this.noise = .06,
      this.selfBias = .08,
      this.blend = 1,
      this.conceal = 0,
      this.frame = .35,
      this.disguise = 0});
  final String label, description;

  /// Good: added to how much extra risk a proposed team may carry.
  final double trusting;

  /// Good: how strongly trust in the leader sways the vote.
  final double follow;

  /// Leader: random variation between similar teams, and the pull towards
  /// putting oneself on the team.
  final double noise, selfBias;

  /// Evil: how readily a team that cannot be sabotaged is approved, and how
  /// much more (or less) often a Success is played to stay hidden.
  final double blend, conceal;

  /// Evil Lady holder: chance to call a good player evil.
  final double frame;

  /// Merlin: chance to vote like an ordinary servant when that differs from
  /// what his knowledge says.
  final double disguise;

  /// The styles computer players are dealt (never [balanced]).
  static const playable = [
    cautious,
    impulsive,
    follower,
    logical,
    actor,
    aggressive
  ];

  /// A style for each of [seats] bots, as varied as possible.
  static List<BotStyle> deal(int seats, Random random) {
    final order = [...playable]..shuffle(random);
    return [for (var i = 0; i < seats; i++) order[i % order.length]];
  }
}
