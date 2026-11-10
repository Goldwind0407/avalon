import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/assets.dart';
import '../../core/ambient_motion.dart';
import '../../core/theme.dart';
import 'effects.dart';

const cardAspect = 2 / 3;

/// Decode artwork at (roughly) the size it is shown, not at full resolution.
/// A 1080×1620 card is ~7 MB once decoded; a seat-sized copy is a few KB.
/// Rounded up to 64 px steps so similar sizes share one cache entry.
int decodeWidth(BuildContext context, double logicalWidth) {
  final px = logicalWidth * MediaQuery.devicePixelRatioOf(context);
  return max(64, (px / 64).ceil() * 64);
}

/// Image asset decoded at display size.
Image artImage(BuildContext context, String asset,
        {required double width, double? height, BoxFit fit = BoxFit.contain}) =>
    Image.asset(asset,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: decodeWidth(context, width),
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true);

/// A face-up card image (all card art is 2:3 with rounded transparent corners).
class GameCard extends StatelessWidget {
  const GameCard(this.asset,
      {super.key, required this.width, this.elevation = 6});
  final String asset;
  final double width;
  final double elevation;
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: width / cardAspect,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * .06),
          boxShadow: elevation <= 0
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .55),
                      blurRadius: elevation * 1.8,
                      offset: Offset(0, elevation * .7)),
                ],
        ),
        child: artImage(context, asset,
            width: width, height: width / cardAspect, fit: BoxFit.cover),
      );
}

/// Which deck a face-down card belongs to.
enum CardDeck {
  /// Character cards (and the face-down vote cards in front of each seat).
  role,

  /// Quest success / fail cards.
  quest,
}

/// Back of a card. Role cards show the sword, quest cards the crown banner.
class CardBack extends StatelessWidget {
  const CardBack(
      {super.key,
      required this.width,
      this.elevation = 6,
      this.deck = CardDeck.role});
  final double width;
  final double elevation;
  final CardDeck deck;
  @override
  Widget build(BuildContext context) => GameCard(
      deck == CardDeck.quest ? Assets.cardBackQuest : Assets.cardBackRole,
      width: width,
      elevation: elevation);
}

/// The two faces of a card turned by [angle] (0 = back, π = front) in 3D.
Widget flipFace(
    {required double angle, required Widget front, required Widget back}) {
  final lift = sin(angle.clamp(0.0, pi));
  return Transform(
    alignment: Alignment.center,
    transform: Matrix4.identity()
      ..setEntry(3, 2, .0012)
      ..rotateY(angle)
      ..scaleByDouble(1 + .1 * lift, 1 + .1 * lift, 1, 1),
    child: angle > pi / 2
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(pi),
            child: front)
        : back,
  );
}

/// Card that turns over in 3D whenever [faceUp] changes.
/// With [flipOnMount] it appears face down and turns over after [delay].
/// Turning back face down is immediate and quicker.
class FlipCard extends StatefulWidget {
  const FlipCard({
    super.key,
    required this.front,
    required this.back,
    required this.faceUp,
    this.delay = Duration.zero,
    this.flipOnMount = false,
    this.duration = const Duration(milliseconds: 700),
    this.onRevealed,
  });
  final Widget front;
  final Widget back;
  final bool faceUp;
  final bool flipOnMount;
  final Duration delay;
  final Duration duration;

  /// Fires when the face-up animation has fully finished.
  final VoidCallback? onRevealed;
  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: const Duration(milliseconds: 360),
      value: widget.faceUp && !widget.flipOnMount ? 1 : 0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener(_onStatus);
    if (widget.flipOnMount && widget.faceUp) _turn(true);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && widget.faceUp) {
      widget.onRevealed?.call();
    }
  }

  void _turn(bool up) {
    _timer?.cancel();
    if (!up) {
      _c.reverse();
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void didUpdateWidget(FlipCard old) {
    super.didUpdateWidget(old);
    if (old.faceUp != widget.faceUp) _turn(widget.faceUp);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => flipFace(
            angle: Curves.easeInOutCubic.transform(_c.value) * pi,
            front: widget.front,
            back: widget.back),
      );
}

/// Board-game piece with a soft shadow that follows its silhouette.
class Token extends StatelessWidget {
  const Token(this.asset, {super.key, required this.size, this.elevation = 4});
  final String asset;
  final double size;
  final double elevation;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            left: elevation * .4,
            top: elevation * .9,
            right: -elevation * .4,
            bottom: -elevation * .9,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                  sigmaX: elevation * .7, sigmaY: elevation * .7),
              child: Image.asset(asset,
                  fit: BoxFit.contain,
                  cacheWidth: decodeWidth(context, size),
                  gaplessPlayback: true,
                  color: Colors.black.withValues(alpha: .7),
                  colorBlendMode: BlendMode.srcIn),
            ),
          ),
          Positioned.fill(
              child: artImage(context, asset, width: size, height: size)),
        ]),
      );
}

/// Soft breathing ring, used to mark the current quest (gold) or the last
/// chance on the vote track (red).
class PulseRing extends StatefulWidget {
  const PulseRing(
      {super.key, required this.diameter, this.color = AvalonTheme.gold});
  final double diameter;
  final Color color;
  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AmbientMotionScope.of(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
            child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = Curves.easeInOut.transform(_c.value);
            return Container(
              width: widget.diameter,
              height: widget.diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: widget.color.withValues(alpha: .55 + .4 * v),
                    width: max(1.5, widget.diameter * .025)),
                boxShadow: [
                  BoxShadow(
                      color: widget.color.withValues(alpha: .25 + .35 * v),
                      blurRadius: widget.diameter * (.12 + .1 * v),
                      spreadRadius: widget.diameter * .01),
                ],
              ),
            );
          },
        )),
      );
}

/// Dark leather plaque with a gold rim, used for banners and buttons on the table.
BoxDecoration plaqueDecoration({bool highlight = false, double radius = 12}) =>
    BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A2416), Color(0xFF1E120A)]),
      border: Border.all(
          color: highlight
              ? AvalonTheme.gold
              : AvalonTheme.gold.withValues(alpha: .45),
          width: highlight ? 2 : 1.2),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: .55),
            blurRadius: 10,
            offset: const Offset(0, 4)),
        if (highlight)
          BoxShadow(
              color: AvalonTheme.gold.withValues(alpha: .45), blurRadius: 14),
      ],
    );

/// Gold button that looks like an embossed brass plate. It dips when
/// pressed and catches the light once when it becomes available.
class TableButton extends StatelessWidget {
  const TableButton(this.label,
      {super.key,
      required this.onPressed,
      this.primary = true,
      this.scale = 1});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final double scale;
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10 * scale),
        child: Ink(
          padding: EdgeInsets.symmetric(
              horizontal: 22 * scale, vertical: 10 * scale),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10 * scale),
            gradient: primary
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                        Color(0xFFF3D9A0),
                        Color(0xFFC9A05A),
                        Color(0xFF9C7535)
                      ])
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF3A2416), Color(0xFF22140B)]),
            border: Border.all(
                color: primary
                    ? const Color(0xFFFFEBC0)
                    : AvalonTheme.gold.withValues(alpha: .6)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .5),
                  blurRadius: 8,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: primary ? const Color(0xFF2A1708) : AvalonTheme.gold)),
        ),
      ),
    );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: enabled ? 1 : .45,
      child: Pressable(
        enabled: enabled,
        child: enabled && primary
            ? ShineSweep(
                radius: 10 * scale,
                delay: const Duration(milliseconds: 150),
                child: button)
            : button,
      ),
    );
  }
}

/// Plays a quick "thump" (scale up and back) each time [count] increases.
class Bump extends StatelessWidget {
  const Bump({super.key, required this.count, required this.child});
  final int count;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        // a new end value restarts the animation; 0 means "never bumped"
        tween: Tween(begin: count.toDouble(), end: count.toDouble()),
        duration: const Duration(milliseconds: 320),
        child: child,
        builder: (context, v, child) {
          final t = v - v.floorToDouble();
          return Transform.scale(
              scale: 1 + .09 * sin(pi * Curves.easeOut.transform(t)),
              child: child);
        },
      );
}

enum SeatVote { none, hidden, approve, reject }

/// A player's place at the table: name plaque plus fixed spots for the
/// pieces in front of them (team shield, vote card, leader crown). The
/// spots carry keys so pieces can fly to and from them.
class SeatPlate extends StatelessWidget {
  const SeatPlate({
    super.key,
    required this.number,
    required this.name,
    required this.scale,
    required this.tokensOnRight,
    this.isLeader = false,
    this.onTeam = false,
    this.highlight = false,
    this.vote = SeatVote.none,
    this.voteDelay = Duration.zero,
    this.onVoteRevealed,
    this.bump = 0,
    this.plateKey,
    this.crownKey,
    this.shieldKey,
    this.voteKey,
    this.onTap,
  });
  final int number;
  final String name;
  final double scale;
  final bool tokensOnRight;
  final bool isLeader;
  final bool onTeam;
  final bool highlight;
  final SeatVote vote;
  final Duration voteDelay;
  final VoidCallback? onVoteRevealed;
  final int bump;
  final Key? plateKey, crownKey, shieldKey, voteKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final plate = GestureDetector(
      onTap: onTap,
      child: Pressable(
        enabled: onTap != null,
        child: Bump(
          count: bump,
          child: AnimatedContainer(
            key: plateKey,
            duration: const Duration(milliseconds: 220),
            width: 112 * s,
            height: 46 * s,
            padding: EdgeInsets.symmetric(horizontal: 6 * s),
            decoration: plaqueDecoration(highlight: highlight, radius: 10 * s),
            child: Row(children: [
              Container(
                width: 26 * s,
                height: 26 * s,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                      colors: [Color(0xFFF0D59A), Color(0xFFA67C3A)]),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: .5),
                        blurRadius: 3)
                  ],
                ),
                child: Text('$number',
                    style: TextStyle(
                        fontSize: 13 * s,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2A1708))),
              ),
              SizedBox(width: 6 * s),
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13 * s,
                        color: const Color(0xFFF2E6CC),
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    );
    final shield = SizedBox(
      key: shieldKey,
      width: 30 * s,
      height: 30 * s,
      child: AnimatedSwitcher(
        duration: Duration.zero,
        reverseDuration: const Duration(milliseconds: 180),
        transitionBuilder: (child, a) =>
            ScaleTransition(scale: a, child: child),
        child: onTeam
            ? Token(Assets.teamToken,
                key: const ValueKey('shield'), size: 30 * s, elevation: 3)
            : const SizedBox.shrink(),
      ),
    );
    final voteCard = SizedBox(
      key: voteKey,
      width: 26 * s,
      height: 39 * s,
      child: vote == SeatVote.none
          ? null
          : FlipCard(
              faceUp: vote == SeatVote.approve || vote == SeatVote.reject,
              flipOnMount: true,
              delay: voteDelay,
              onRevealed: onVoteRevealed,
              back: CardBack(width: 26 * s, elevation: 3),
              front: GameCard(
                  vote == SeatVote.reject
                      ? Assets.voteReject
                      : Assets.voteApprove,
                  width: 26 * s,
                  elevation: 3),
            ),
    );
    final gap = SizedBox(width: 3 * s);
    final pieces = SizedBox(
      width: 62 * s,
      height: 46 * s,
      child: Row(
          mainAxisAlignment:
              tokensOnRight ? MainAxisAlignment.start : MainAxisAlignment.end,
          children: tokensOnRight
              ? [shield, gap, voteCard]
              : [voteCard, gap, shield]),
    );
    return SizedBox(
      width: 178 * s,
      height: 56 * s,
      child: Stack(clipBehavior: Clip.none, children: [
        Align(
          alignment: Alignment.center,
          child: Row(
              mainAxisSize: MainAxisSize.min,
              children: tokensOnRight
                  ? [plate, SizedBox(width: 4 * s), pieces]
                  : [pieces, SizedBox(width: 4 * s), plate]),
        ),
        Positioned(
          top: -10 * s,
          left: tokensOnRight ? -6 * s : null,
          right: tokensOnRight ? null : -6 * s,
          child: SizedBox(
            key: crownKey,
            width: 30 * s,
            height: 30 * s,
            child: isLeader
                ? Token(Assets.leaderToken, size: 30 * s, elevation: 3)
                : null,
          ),
        ),
      ]),
    );
  }
}
