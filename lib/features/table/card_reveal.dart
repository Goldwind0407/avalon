import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'components.dart';
import 'effects.dart';

/// One face-down card to be turned over in a [CardReveal].
class RevealItem {
  const RevealItem({
    required this.front,
    required this.back,
    required this.glow,
    this.shock = false,
    this.label,
  });
  final Widget Function(double width) front;
  final Widget Function(double width) back;

  /// Colour of the light that bursts out when the card is turned.
  final Color glow;

  /// A bad surprise: the table shakes when this card is turned.
  final bool shock;
  final String? label;
}

/// The dramatic public reveal: the cards are gathered, shuffled, laid out
/// in a row and turned over one at a time (with a longer pause before the
/// last one), then the verdict is stamped below.
///
/// The whole sequence is one timeline, so it always plays the same way;
/// tapping anywhere skips to the end.
class CardReveal extends StatefulWidget {
  const CardReveal({
    super.key,
    required this.items,
    required this.cardWidth,
    required this.scale,
    required this.caption,
    required this.verdict,
    required this.verdictColor,
    required this.detail,
    required this.button,
    required this.onContinue,
    this.shuffle = true,
    this.particles = ParticleKind.spark,
    this.onReveal,
    this.onVerdict,
  });
  final List<RevealItem> items;
  final double cardWidth;
  final double scale;
  final String caption;
  final String verdict;
  final Color verdictColor;
  final String detail;
  final String button;

  /// Null while someone else decides when to go on (online: the leader).
  final VoidCallback? onContinue;
  final bool shuffle;
  final ParticleKind particles;

  /// A card has just shown its face.
  final void Function(RevealItem item)? onReveal;
  final VoidCallback? onVerdict;
  @override
  State<CardReveal> createState() => _CardRevealState();
}

class _CardRevealState extends State<CardReveal>
    with SingleTickerProviderStateMixin {
  static const _gatherEnd = 380.0, _flipMs = 540.0;
  late final double _shuffleEnd, _spreadEnd, _verdictAt, _controlsAt, _total;
  late final List<double> _anticStart, _flipStart, _reveal;
  late final List<bool> _fired;
  late final AnimationController _c;
  bool _verdictFired = false, _skipped = false;

  @override
  void initState() {
    super.initState();
    final n = widget.items.length;
    final shuffle = widget.shuffle && n > 1;
    _shuffleEnd = _gatherEnd + (shuffle ? 950 : 0);
    _spreadEnd = _shuffleEnd + (n > 1 ? 480 : 0);
    var t = _spreadEnd + 320;
    _anticStart = [];
    _flipStart = [];
    _reveal = [];
    for (var i = 0; i < n; i++) {
      final last = i == n - 1;
      // the last card is held a moment longer
      final antic = last ? (n == 1 ? 1300.0 : 950.0) : 320.0;
      _anticStart.add(t);
      _flipStart.add(t + antic);
      _reveal.add(t + antic + _flipMs / 2);
      t += antic + _flipMs + (last ? 0 : 240);
    }
    _fired = List.filled(n, false);
    _verdictAt = t + 380;
    _controlsAt = _verdictAt + 650;
    _total = _controlsAt + 500;
    _c = AnimationController(
        vsync: this, duration: Duration(milliseconds: _total.round()))
      ..addListener(_tick)
      ..forward();
  }

  void _tick() {
    if (_skipped) return;
    final t = _c.value * _total;
    for (var i = 0; i < _fired.length; i++) {
      if (!_fired[i] && t >= _reveal[i]) {
        _fired[i] = true;
        widget.onReveal?.call(widget.items[i]);
      }
    }
    if (!_verdictFired && t >= _verdictAt + 260) {
      _verdictFired = true;
      widget.onVerdict?.call();
    }
  }

  void _skip() {
    if (!_c.isAnimating) return;
    _skipped = true;
    _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _seg(double a, double b) {
    final t = _c.value * _total;
    return b <= a ? (t >= b ? 1 : 0) : ((t - a) / (b - a)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale, w = widget.cardWidth, h = w / cardAspect;
    final n = widget.items.length;
    final gap = 18 * s;
    final rowW = max(n * (w + gap), w * 2.8);
    final labelH = widget.items.any((i) => i.label != null) ? 24 * s : 0.0;
    const ink = Color(0xFFEDE3CC);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final gather = Curves.easeOutBack.transform(_seg(0, _gatherEnd));
          final u = _seg(_gatherEnd, _shuffleEnd);
          final spread =
              Curves.easeInOutCubic.transform(_seg(_shuffleEnd, _spreadEnd));
          final vp = _seg(_verdictAt, _verdictAt + 460);
          final hit = (vp / .56).clamp(0.0, 1.0);
          final settle = ((vp - .56) / .44).clamp(0.0, 1.0);
          final verdictScale = hit < 1
              ? lerpDouble(2.8, .93, Curves.easeInCubic.transform(hit))!
              : .93 + .07 * Curves.easeOutBack.transform(settle);
          final cp = Curves.easeOutCubic
              .transform(_seg(_controlsAt, _controlsAt + 450));
          return Stack(fit: StackFit.expand, children: [
            Opacity(
              opacity: Curves.easeOut
                  .transform(_seg(_verdictAt + 200, _verdictAt + 1000)),
              child: Particles(kind: widget.particles, count: 36),
            ),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Opacity(
                    opacity: _seg(0, 320),
                    child: Text(widget.caption,
                        style: TextStyle(
                            fontSize: 14 * s,
                            color: const Color(0xFFACB2CF),
                            letterSpacing: 1)),
                  ),
                  SizedBox(height: 10 * s),
                  SizedBox(
                    width: rowW,
                    height: h * 1.2 + labelH,
                    child: Stack(clipBehavior: Clip.none, children: [
                      for (var i = 0; i < n; i++)
                        _card(i, n, w, h, gap, rowW, s, gather, u, spread),
                    ]),
                  ),
                  SizedBox(height: 6 * s),
                  Opacity(
                    opacity: (vp * 4).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: verdictScale,
                      child: Text(widget.verdict,
                          style: TextStyle(
                              fontSize: 28 * s,
                              height: 1.2,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4 * s,
                              color: widget.verdictColor,
                              shadows: [
                                Shadow(
                                    color: widget.verdictColor
                                        .withValues(alpha: .8),
                                    blurRadius: 22 * s),
                                const Shadow(blurRadius: 4),
                              ])),
                    ),
                  ),
                  Opacity(
                    opacity: cp,
                    child: Transform.translate(
                      offset: Offset(0, 12 * s * (1 - cp)),
                      child: Column(children: [
                        Text(widget.detail,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13 * s, color: ink)),
                        SizedBox(height: 10 * s),
                        IgnorePointer(
                          ignoring: cp < .5,
                          child: TableButton(widget.button,
                              scale: s, onPressed: widget.onContinue),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _card(int i, int n, double w, double h, double gap, double rowW,
      double s, double gather, double u, double spread) {
    final item = widget.items[i];
    final last = i == n - 1;
    final a = _seg(_anticStart[i], _flipStart[i]);
    final f = _seg(_flipStart[i], _flipStart[i] + _flipMs);
    final post = _seg(_reveal[i], _reveal[i] + 800);
    final down = Curves.easeOut.transform(
        _seg(_flipStart[i] + _flipMs, _flipStart[i] + _flipMs + 320));
    // picked up before it is turned, put down afterwards
    final lift = a <= 0 ? 0.0 : Curves.easeOut.transform(a) * (1 - down);
    final wave = 2 * pi * (u * 2 + i / n), env = sin(pi * u);
    final mid = i - (n - 1) / 2;
    final x = mid * (w + gap) * spread + w * .62 * sin(wave) * env;
    final y = h * .13 - 5 * s * i * (1 - spread) - 12 * s * lift;
    var turn = .07 * sin(wave) * env + mid * .045 * (1 - spread);
    if (a > 0 && a < 1) turn += .03 * sin(a * pi * (last ? 10 : 6)) * (1 - a);
    var scale = gather * (1 + .08 * lift);
    // heartbeat while the last card is held
    if (last && a > 0 && f <= 0) scale *= 1 + .035 * sin(a * pi * 5).abs();
    return Positioned(
      left: rowW / 2 + x - w / 2,
      top: y,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Transform.rotate(
          angle: turn,
          child: Transform.scale(
            scale: scale,
            child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (post > 0 && post < 1)
                    Positioned.fill(
                      child: OverflowBox(
                        minWidth: w * 3.6,
                        maxWidth: w * 3.6,
                        minHeight: w * 3.6,
                        maxHeight: w * 3.6,
                        child:
                            CustomPaint(painter: BurstPainter(item.glow, post)),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(w * .06),
                      boxShadow: post <= 0
                          ? null
                          : [
                              BoxShadow(
                                  color:
                                      item.glow.withValues(alpha: .75 * post),
                                  blurRadius: 26 * s,
                                  spreadRadius: 2 * s)
                            ],
                    ),
                    child: flipFace(
                        angle: pi * Curves.easeInOutCubic.transform(f),
                        front: item.front(w),
                        back: item.back(w)),
                  ),
                ]),
          ),
        ),
        if (item.label != null)
          Padding(
            padding: EdgeInsets.only(top: 6 * s),
            child: Opacity(
              opacity: gather.clamp(0.0, 1.0),
              child: Text(item.label!,
                  style: TextStyle(
                      fontSize: 13 * s, color: const Color(0xFFEDE3CC))),
            ),
          ),
      ]),
    );
  }
}
