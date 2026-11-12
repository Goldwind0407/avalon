/// How well a computer player reasons and acts. Like a style, a level never
/// gives a seat more information: it changes what is made of it.
enum BotDifficulty {
  novice('新手', '憑直覺玩，不太記票，壞人容易被看穿',
      reasoning: .55,
      voteEvidence: 0,
      claimTrust: .2,
      remembersClaims: false,
      rolePlay: 0,
      noise: 2.2,
      slip: .05,
      blend: .4,
      stacking: .15,
      assassinNoise: .7),
  normal('一般', '會推理、記票，也會演一點戲'),
  expert('高手', '推理嚴謹，偽裝和配合都更到位',
      reasoning: .9,
      voteEvidence: 1.5,
      claimTrust: .6,
      rolePlay: 1.6,
      noise: .5,
      blend: 1.1,
      stacking: .6,
      assassinNoise: .2);

  const BotDifficulty(this.label, this.description,
      {this.reasoning = .75,
      this.voteEvidence = 1,
      this.claimTrust = .5,
      this.remembersClaims = true,
      this.rolePlay = 1,
      this.noise = 1,
      this.slip = 0,
      this.blend = 1,
      this.stacking = .5,
      this.assassinNoise = .45});
  final String label, description;

  /// How far the worked-out share of possible deals replaces gut feeling
  /// (certain conclusions are always drawn).
  final double reasoning;

  /// Weight of "who approved the team that failed", and of Lady claims.
  final double voteEvidence, claimTrust;

  /// Claims from earlier quests are still taken into account.
  final bool remembersClaims;

  /// Scales the acting: Merlin's disguise, Percival following Merlin,
  /// Morgana posing as Merlin, hiding when a Fail would point at one seat.
  final double rolePlay;

  /// Scales the randomness of team choices; chance that a good vote slips.
  final double noise, slip;

  /// Evil: scales going along with clean teams; cost of each surplus ally
  /// on the team; randomness of the Assassin's pick.
  final double blend, stacking, assassinNoise;
}
