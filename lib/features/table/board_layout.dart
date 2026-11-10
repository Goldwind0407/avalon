import 'dart:ui';

/// Where the printed circles sit on each scoreboard image, measured in the
/// boards' own 1440 × 1080 pixel space (the boards are 4:3). Every board was
/// painted separately, so each player count has its own coordinates.
class BoardLayout {
  const BoardLayout(this.quests, this.slots, this.votes);

  /// Centres of the five quest bubbles.
  final List<Offset> quests;

  /// Centres of the small circles beside each quest bubble, where the
  /// success / fail score marker is placed.
  final List<Offset> slots;

  /// Centres of the five vote-track bubbles.
  final List<Offset> votes;

  static const basis = Size(1440, 1080);
  static const questRadius = 122.0;
  static const slotRadius = 54.0;
  static const voteRadius = 88.0;

  Offset slot(int quest) => slots[quest];

  static BoardLayout forPlayers(int players) => _layouts[players.clamp(5, 10)]!;

  static const _layouts = {
    5: BoardLayout(
      [
        Offset(161, 505),
        Offset(439, 496),
        Offset(707, 503),
        Offset(984, 499),
        Offset(1263, 499)
      ],
      [
        Offset(264, 623),
        Offset(548, 628),
        Offset(819, 627),
        Offset(1082, 630),
        Offset(1354, 625)
      ],
      [
        Offset(153, 899),
        Offset(352, 898),
        Offset(553, 894),
        Offset(745, 902),
        Offset(936, 890)
      ],
    ),
    6: BoardLayout(
      [
        Offset(162, 527),
        Offset(440, 523),
        Offset(710, 532),
        Offset(983, 524),
        Offset(1259, 532)
      ],
      [
        Offset(246, 637),
        Offset(524, 641),
        Offset(798, 642),
        Offset(1071, 654),
        Offset(1341, 654)
      ],
      [
        Offset(162, 908),
        Offset(364, 907),
        Offset(559, 901),
        Offset(750, 909),
        Offset(934, 900)
      ],
    ),
    7: BoardLayout(
      [
        Offset(184, 502),
        Offset(451, 498),
        Offset(714, 498),
        Offset(970, 508),
        Offset(1251, 505)
      ],
      [
        Offset(274, 612),
        Offset(537, 604),
        Offset(804, 618),
        Offset(1080, 610),
        Offset(1323, 601)
      ],
      [
        Offset(161, 881),
        Offset(361, 883),
        Offset(553, 882),
        Offset(742, 886),
        Offset(933, 881)
      ],
    ),
    8: BoardLayout(
      [
        Offset(185, 472),
        Offset(455, 479),
        Offset(720, 478),
        Offset(988, 469),
        Offset(1260, 469)
      ],
      [
        Offset(275, 584),
        Offset(541, 599),
        Offset(810, 592),
        Offset(1076, 599),
        Offset(1346, 603)
      ],
      [
        Offset(150, 900),
        Offset(345, 900),
        Offset(538, 897),
        Offset(728, 902),
        Offset(918, 898)
      ],
    ),
    9: BoardLayout(
      [
        Offset(186, 491),
        Offset(448, 506),
        Offset(720, 506),
        Offset(993, 493),
        Offset(1257, 492)
      ],
      [
        Offset(272, 611),
        Offset(540, 612),
        Offset(810, 612),
        Offset(1075, 617),
        Offset(1339, 618)
      ],
      [
        Offset(160, 905),
        Offset(352, 894),
        Offset(549, 901),
        Offset(734, 906),
        Offset(924, 897)
      ],
    ),
    10: BoardLayout(
      [
        Offset(184, 487),
        Offset(454, 496),
        Offset(718, 495),
        Offset(989, 483),
        Offset(1262, 484)
      ],
      [
        Offset(282, 609),
        Offset(532, 618),
        Offset(804, 611),
        Offset(1071, 615),
        Offset(1344, 610)
      ],
      [
        Offset(157, 892),
        Offset(346, 892),
        Offset(534, 889),
        Offset(722, 897),
        Offset(912, 890)
      ],
    ),
  };
}
