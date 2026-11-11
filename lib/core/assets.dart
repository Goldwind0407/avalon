import '../features/game/game_model.dart';

/// Paths of the bundled artwork (see assets/images/**).
class Assets {
  static const _roles = 'assets/images/roles';
  static const _cards = 'assets/images/cards';
  static const _tokens = 'assets/images/tokens';

  /// [variant] picks one of the alternative artworks for roles that can
  /// appear several times in one game (loyal servants, minions).
  static String role(Role role, int variant) => switch (role) {
        Role.merlin => '$_roles/merlin.webp',
        Role.percival => '$_roles/percival.webp',
        Role.loyal => '$_roles/loyal_servant_${variant % 5 + 1}.webp',
        Role.assassin => '$_roles/assassin.webp',
        Role.morgana => '$_roles/morgana.webp',
        Role.mordred => '$_roles/mordred.webp',
        Role.oberon => '$_roles/oberon.webp',
        Role.minion => '$_roles/minion_${variant % 3 + 1}.webp',
        Role.lancelotGood => '$_roles/lancelot_good.webp',
        Role.lancelotEvil => '$_roles/lancelot_evil.webp',
      };

  // ── expansions ──
  static const ladyOfTheLake = '$_roles/lady_of_the_lake.webp';
  static const loyaltySwitch = '$_cards/lancelot_switch.webp';
  static const loyaltyNoSwitch = '$_cards/lancelot_no_switch.webp';
  static const loyaltyBack = '$_cards/lancelot_switch_back.webp';
  static const excalibur = '$_tokens/excalibur.webp';

  static const loyaltyGood = '$_cards/loyalty_good.webp';
  static const loyaltyEvil = '$_cards/loyalty_evil.webp';
  static const questSuccess = '$_cards/quest_success.webp';
  static const questFail = '$_cards/quest_fail.webp';
  static const voteApprove = '$_cards/vote_approve.webp';
  static const voteReject = '$_cards/vote_reject.webp';
  static const cardBackRole = '$_cards/card_back_role.webp';
  static const cardBackQuest = '$_cards/card_back_quest.webp';
  static const cardBackVote = '$_cards/card_back_vote.webp';

  static const teamToken = '$_tokens/team_token.webp';
  static const leaderToken = '$_tokens/leader_token.webp';
  static const roundMarker = '$_tokens/round_marker.webp';
  static const voteTrackMarker = '$_tokens/vote_track_marker.webp';
  static const scoreGood = '$_tokens/score_good.webp';
  static const scoreEvil = '$_tokens/score_evil.webp';

  /// Opening animation: the Goldwind signature, with its star separate so
  /// it can pop in on its own.
  static const signature = 'assets/images/brand/signature.webp';
  static const signatureStar = 'assets/images/brand/signature_star.webp';

  static const logoGood = 'assets/images/logos/logo_good.webp';
  static const logoEvil = 'assets/images/logos/logo_evil.webp';

  static String board(int players) =>
      'assets/images/boards/board_${players.clamp(5, 10)}p.webp';
}
