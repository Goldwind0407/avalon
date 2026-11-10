import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Runs [builder] once with t going 0 → 1 over [duration], after [delay].
/// Rebuilding the parent does not restart it.
class Delayed extends StatelessWidget {
  const Delayed({
    super.key,
    required this.builder,
    this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 400),
  });
  final Widget Function(BuildContext context, double t, Widget? child) builder;
  final Widget? child;
  final Duration delay;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final total = delay + duration;
    final start = delay.inMilliseconds / max(1, total.inMilliseconds);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      child: child,
      builder: (context, v, child) => builder(
          context,
          start >= 1 ? 1.0 : ((v - start) / (1 - start)).clamp(0.0, 1.0),
          child),
    );
  }
}

/// Fades the child in while it slides (and optionally scales / turns) into
/// place.
class Appear extends StatelessWidget {
  const Appear({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.offset = const Offset(0, 14),
    this.scaleFrom = 1,
    this.turnFrom = 0,
  });
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset offset;
  final double scaleFrom;
  final double turnFrom;

  @override
  Widget build(BuildContext context) => Delayed(
        delay: delay,
        duration: duration,
        child: child,
        builder: (context, t, child) {
          final e = Curves.easeOutCubic.transform(t);
          return Opacity(
            opacity: e,
            child: Transform.translate(
              offset: offset * (1 - e),
              child: Transform.rotate(
                angle: turnFrom * (1 - e),
                child: Transform.scale(
                    scale: scaleFrom + (1 - scaleFrom) * e, child: child),
              ),
            ),
          );
        },
      );
}

/// Slams the child down like a rubber stamp: it starts large, hits the
/// surface, and settles with a small squash. [onLand] fires at the hit.
class StampIn extends StatefulWidget {
  const StampIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.angle = 0,
    this.onLand,
  });
  final Widget child;
  final Duration delay;
  final double angle;
  final VoidCallback? onLand;
  @override
  State<StampIn> createState() => _StampInState();
}

class _StampInState extends State<StampIn> with SingleTickerProviderStateMixin {
  static const _ms = 480;
  late final double _start;
  late final AnimationController _c;
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    final total = widget.delay.inMilliseconds + _ms;
    _start = widget.delay.inMilliseconds / total;
    _c = AnimationController(
        vsync: this, duration: Duration(milliseconds: total))
      ..addListener(_tick)
      ..forward();
  }

  double get _t => ((_c.value - _start) / (1 - _start)).clamp(0.0, 1.0);

  void _tick() {
    if (!_landed && _t >= .55) {
      _landed = true;
      widget.onLand?.call();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final t = _t;
          final hit = (t / .55).clamp(0.0, 1.0);
          final settle = ((t - .55) / .45).clamp(0.0, 1.0);
          final scale = hit < 1
              ? lerpDouble(2.8, .92, Curves.easeInCubic.transform(hit))!
              : .92 + .08 * Curves.easeOutBack.transform(settle);
          return Opacity(
            opacity: (t / .2).clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: widget.angle,
              child: Transform.scale(scale: scale, child: child),
            ),
          );
        },
      );
}

/// Shrinks slightly while a finger is down, like pressing a real button.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down && widget.enabled ? .95 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// Shakes its child when [ShakerState.shake] is called (a thump on the table).
class Shaker extends StatefulWidget {
  const Shaker({super.key, required this.child});
  final Widget child;
  @override
  State<Shaker> createState() => ShakerState();
}

class ShakerState extends State<Shaker> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 480), value: 1);
  double _strength = 0;

  void shake([double strength = 8]) {
    _strength = strength;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          // Always the same widget structure: wrapping the child only while
          // shaking would rebuild everything below from scratch on each shake.
          final t = _c.value;
          final d = (1 - t) * (1 - t) * _strength;
          return Transform.translate(
              offset: Offset(sin(t * pi * 9) * d, cos(t * pi * 7) * d * .6),
              child: child);
        },
      );
}

/// Gentle idle motion: the child bobs, and with [tilt] also sways in 3D as
/// if held in a hand.
class Floaty extends StatefulWidget {
  const Floaty(
      {super.key, required this.child, this.amplitude = 4, this.tilt = false});
  final Widget child;
  final double amplitude;
  final bool tilt;
  @override
  State<Floaty> createState() => _FloatyState();
}

class _FloatyState extends State<Floaty> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 5200))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final a = _c.value * 2 * pi;
          final m = Matrix4.identity()
            ..translateByDouble(0, sin(a) * widget.amplitude, 0, 1);
          if (widget.tilt) {
            m
              ..setEntry(3, 2, .0012)
              ..rotateY(sin(a + 1) * .07)
              ..rotateX(cos(a) * .03);
          } else {
            m.rotateZ(sin(a + .6) * .012);
          }
          return Transform(
              alignment: Alignment.center, transform: m, child: child);
        },
      );
}

/// A streak of light that sweeps once across the child (a glossy card
/// catching the light).
class ShineSweep extends StatelessWidget {
  const ShineSweep({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 750),
    this.radius = 0,
  });
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double radius;

  @override
  Widget build(BuildContext context) => Stack(children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Delayed(
                delay: delay,
                duration: duration,
                builder: (context, t, _) => t <= 0 || t >= 1
                    ? const SizedBox.shrink()
                    : CustomPaint(painter: _ShinePainter(t)),
              ),
            ),
          ),
        ),
      ]);
}

class _ShinePainter extends CustomPainter {
  const _ShinePainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final band = w * .6;
    final x = lerpDouble(-w * .6, w * 1.7, Curves.easeInOut.transform(t))!;
    final rect = Rect.fromLTWH(x, -h * .1, band, h * 1.2);
    canvas
      ..save()
      ..skew(-.4, 0)
      ..drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: .5),
              Colors.white.withValues(alpha: 0),
            ]).createShader(rect))
      ..restore();
  }

  @override
  bool shouldRepaint(_ShinePainter old) => old.t != t;
}

/// Flash, expanding ring and rays of light. [t] runs 0 → 1.
class BurstPainter extends CustomPainter {
  const BurstPainter(this.color, this.t);
  final Color color;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final e = Curves.easeOutCubic.transform(t);
    final fade = (1 - t) * (1 - t);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: .75 * fade),
            color.withValues(alpha: .25 * fade),
            color.withValues(alpha: 0),
          ], stops: const [
            0,
            .45,
            1
          ]).createShader(Rect.fromCircle(center: c, radius: r)));
    final rays = Paint()
      ..color = Colors.white.withValues(alpha: .35 * fade)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * .02;
    for (var i = 0; i < 14; i++) {
      final a = i * 2 * pi / 14 + .2;
      final d = Offset(cos(a), sin(a));
      canvas.drawLine(c + d * r * (.28 + .3 * e),
          c + d * r * (.4 + .55 * e) * (i.isEven ? 1 : .8), rays);
    }
    canvas.drawCircle(
        c,
        r * (.3 + .65 * e),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * .05 * (1 - t)
          ..color = Color.lerp(color, Colors.white, .5)!
              .withValues(alpha: .9 * (1 - t)));
  }

  @override
  bool shouldRepaint(BurstPainter old) => old.t != t || old.color != color;
}

/// One-shot burst of light. Place it with `Positioned.fill` behind something;
/// it overflows its box to [size].
class GlowBurst extends StatelessWidget {
  const GlowBurst({
    super.key,
    required this.color,
    required this.size,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 950),
  });
  final Color color;
  final double size;
  final Duration delay;
  final Duration duration;
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: OverflowBox(
          minWidth: size,
          maxWidth: size,
          minHeight: size,
          maxHeight: size,
          child: Delayed(
            delay: delay,
            duration: duration,
            builder: (context, t, _) => t <= 0 || t >= 1
                ? const SizedBox.shrink()
                : CustomPaint(painter: BurstPainter(color, t)),
          ),
        ),
      );
}

enum ParticleKind {
  /// Slow motes of dust in warm candle light (ambient, over the table).
  dust,

  /// Glowing embers rising from below (evil).
  ember,

  /// Golden sparkles drifting down (good).
  spark,
}

/// Lightweight looping particle field, sized by its parent.
class Particles extends StatefulWidget {
  const Particles(
      {super.key, required this.kind, this.count = 30, this.seed = 7});
  final ParticleKind kind;
  final int count;
  final int seed;
  @override
  State<Particles> createState() => _ParticlesState();
}

class _Particle {
  _Particle(Random r)
      : x = r.nextDouble(),
        y = r.nextDouble(),
        speed = .5 + r.nextDouble(),
        size = 1 + r.nextDouble() * 1.6,
        phase = r.nextDouble() * 2 * pi,
        hue = r.nextDouble();
  final double x, y, speed, size, phase, hue;
}

class _ParticlesState extends State<Particles>
    with SingleTickerProviderStateMixin {
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker;
  late final List<_Particle> _ps;

  @override
  void initState() {
    super.initState();
    final r = Random(widget.seed);
    _ps = List.generate(widget.count, (_) => _Particle(r));
    _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6)
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: SizedBox.expand(
            child:
                CustomPaint(painter: _ParticlePainter(widget.kind, _ps, _time)),
          ),
        ),
      );
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.kind, this.ps, this.time) : super(repaint: time);
  final ParticleKind kind;
  final List<_Particle> ps;
  final ValueNotifier<double> time;

  static double _fract(double v) => v - v.floorToDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value, w = size.width, h = size.height;
    final unit = size.shortestSide / 390;
    final paint = Paint();
    switch (kind) {
      case ParticleKind.dust:
        // candle light breathing over the table
        final flicker = .05 + .018 * sin(t * 2.3) + .012 * sin(t * 5.1 + 1.3);
        final rect = Offset.zero & size;
        canvas.drawRect(
            rect,
            Paint()
              ..shader = RadialGradient(
                  center: const Alignment(0, -.3),
                  radius: .95,
                  colors: [
                    const Color(0xFFFFC27A).withValues(alpha: flicker),
                    const Color(0x00FFC27A),
                  ]).createShader(rect));
        for (final p in ps) {
          final a = .09 + .09 * sin(t * .7 * p.speed + p.phase);
          if (a <= 0) continue;
          paint.color = const Color(0xFFFFE9C4).withValues(alpha: a);
          canvas.drawCircle(
              Offset((p.x + .03 * sin(t * .21 * p.speed + p.phase)) * w,
                  _fract(p.y - t * .006 * p.speed) * h),
              p.size * unit,
              paint);
        }
      case ParticleKind.ember:
        for (final p in ps) {
          final life = _fract(p.y + t * .09 * p.speed);
          final a = sin(pi * life) * (.65 + .35 * sin(t * 9 + p.phase));
          if (a <= 0) continue;
          final r = p.size * unit * (1.5 - .7 * life);
          paint
            ..color = Color.lerp(
                    const Color(0xFFFFB347), const Color(0xFFFF3B1F), p.hue)!
                .withValues(alpha: a.clamp(0.0, 1.0))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .9);
          canvas.drawCircle(
              Offset(
                  (p.x +
                          .04 * sin(t * 1.3 + p.phase) +
                          .05 * life * (p.hue - .5)) *
                      w,
                  (1.05 - life * 1.15) * h),
              r,
              paint);
        }
      case ParticleKind.spark:
        for (final p in ps) {
          final life = _fract(p.y + t * .06 * p.speed);
          final twinkle = .5 + .5 * sin(t * 5 * p.speed + p.phase);
          final a = sin(pi * life) * twinkle;
          if (a <= .02) continue;
          final c = Offset(
              (p.x + .03 * sin(t * .9 + p.phase)) * w, (-.05 + life * 1.1) * h);
          final r = p.size * unit * (1.6 + 1.6 * twinkle);
          paint.color =
              Color.lerp(const Color(0xFFFFD98A), Colors.white, p.hue * .7)!
                  .withValues(alpha: a.clamp(0.0, 1.0));
          // four-point star
          final path = Path()
            ..moveTo(c.dx, c.dy - r)
            ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
            ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
            ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
            ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
          canvas.drawPath(path, paint);
        }
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.kind != kind;
}

/// Blurs and dims whatever is behind it, fading in and out with [visible].
/// Pass the content only while visible; the scrim itself fades out empty.
class BlurScrim extends StatelessWidget {
  const BlurScrim({
    super.key,
    required this.visible,
    this.child,
    this.sigma = 12,
    this.dim = .62,
  });
  final bool visible;
  final Widget? child;
  final double sigma;
  final double dim;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: visible ? 1 : 0),
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOut,
        child: child,
        builder: (context, v, child) {
          if (v <= 0) return const SizedBox.shrink();
          return IgnorePointer(
            ignoring: !visible,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: sigma * v, sigmaY: sigma * v),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: dim * v),
                  child: child ?? const SizedBox.expand(),
                ),
              ),
            ),
          );
        },
      );
}

/// Banner that sweeps across the table to announce something, then leaves.
class Announcement extends StatelessWidget {
  const Announcement({
    super.key,
    required this.title,
    required this.subtitle,
    required this.scale,
    this.delay = Duration.zero,
  });
  final String title;
  final String subtitle;
  final double scale;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE7C47B);
    final s = scale;
    return Delayed(
      delay: delay,
      duration: const Duration(milliseconds: 2100),
      builder: (context, t, _) {
        if (t <= 0 || t >= 1) return const SizedBox.shrink();
        final enter = Curves.easeOutCubic.transform((t / .2).clamp(0.0, 1.0));
        final leave =
            Curves.easeInCubic.transform(((t - .8) / .2).clamp(0.0, 1.0));
        final line = BoxDecoration(
            gradient: LinearGradient(colors: [
          gold.withValues(alpha: 0),
          gold.withValues(alpha: .9),
          gold.withValues(alpha: 0)
        ]));
        return Opacity(
          opacity: enter * (1 - leave),
          child: Center(
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 12 * s),
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                Colors.black.withValues(alpha: 0),
                Colors.black.withValues(alpha: .82),
                Colors.black.withValues(alpha: .82),
                Colors.black.withValues(alpha: 0),
              ], stops: const [
                0,
                .25,
                .75,
                1
              ])),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FractionallySizedBox(
                    widthFactor: .2 + .4 * enter,
                    child: Container(height: 1.4 * s, decoration: line)),
                SizedBox(height: 8 * s),
                Transform.translate(
                  offset: Offset(40 * s * (1 - enter) - 40 * s * leave, 0),
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 30 * s,
                          fontWeight: FontWeight.bold,
                          letterSpacing: (6 + 10 * (1 - enter)) * s,
                          color: gold,
                          shadows: [
                            Shadow(
                                color: gold.withValues(alpha: .6),
                                blurRadius: 18 * s)
                          ])),
                ),
                SizedBox(height: 2 * s),
                Transform.translate(
                  offset: Offset(-40 * s * (1 - enter) + 40 * s * leave, 0),
                  child: Text(subtitle,
                      style: TextStyle(
                          fontSize: 13 * s, color: const Color(0xFFE8DCC0))),
                ),
                SizedBox(height: 8 * s),
                FractionallySizedBox(
                    widthFactor: .2 + .4 * enter,
                    child: Container(height: 1.4 * s, decoration: line)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// On-screen rectangle of the widget holding [key], or null if not laid out.
Rect? rectOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return Rect.fromPoints(box.localToGlobal(Offset.zero),
      box.localToGlobal(box.size.bottomRight(Offset.zero)));
}

/// A piece travelling across the table from one place to another.
class Flight {
  const Flight({
    required this.from,
    required this.to,
    required this.builder,
    this.duration = const Duration(milliseconds: 600),
    this.delay = Duration.zero,
    this.arc = 0,
    this.turns = 0,
    this.onDone,
  });

  /// Start and end rectangles in global coordinates; the piece's width is
  /// interpolated between the two.
  final Rect from, to;
  final Widget Function(double width) builder;
  final Duration duration;
  final Duration delay;

  /// Height of the arc in pixels (negative = upwards).
  final double arc;
  final double turns;
  final VoidCallback? onDone;
}

class _ActiveFlight {
  _ActiveFlight(this.flight, this.from, this.to, this.controller, this.start);
  final Flight flight;
  final Rect from, to;
  final AnimationController controller;
  final double start;
}

/// Transparent layer on top of the table in which pieces fly.
class FlightLayer extends StatefulWidget {
  const FlightLayer({super.key});
  @override
  State<FlightLayer> createState() => FlightLayerState();
}

class FlightLayerState extends State<FlightLayer>
    with TickerProviderStateMixin {
  final _active = <_ActiveFlight>[];

  void launch(Flight f) {
    final box = context.findRenderObject() as RenderBox;
    Rect local(Rect r) => Rect.fromPoints(
        box.globalToLocal(r.topLeft), box.globalToLocal(r.bottomRight));
    final total = f.delay + f.duration;
    final c = AnimationController(vsync: this, duration: total);
    final a = _ActiveFlight(f, local(f.from), local(f.to), c,
        f.delay.inMilliseconds / max(1, total.inMilliseconds));
    c.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      setState(() => _active.remove(a));
      c.dispose();
      f.onDone?.call();
    });
    setState(() => _active.add(a));
    c.forward();
  }

  @override
  void dispose() {
    for (final a in _active) {
      a.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Stack(children: [
          for (final a in _active)
            AnimatedBuilder(
              animation: a.controller,
              builder: (context, _) {
                final v = a.controller.value;
                if (v < a.start) return const SizedBox.shrink();
                final t = a.start >= 1 ? 1.0 : (v - a.start) / (1 - a.start);
                final e = Curves.easeInOutCubic.transform(t);
                final c = Offset.lerp(a.from.center, a.to.center, e)! +
                    Offset(0, a.flight.arc * sin(pi * e));
                final w = lerpDouble(a.from.width, a.to.width, e)!;
                return Positioned(
                  left: c.dx,
                  top: c.dy,
                  child: FractionalTranslation(
                    translation: const Offset(-.5, -.5),
                    child: Transform.rotate(
                      angle: a.flight.turns * 2 * pi * e,
                      // built once at its starting size and scaled, so the
                      // artwork is not re-decoded at every size on the way
                      child: Transform.scale(
                          scale: (1 + .14 * sin(pi * e)) * w / a.from.width,
                          child: a.flight.builder(a.from.width)),
                    ),
                  ),
                );
              },
            ),
        ]),
      );
}

/// A marker on the board (must be a child of a [Stack]). When [center]
/// changes it is picked up, hops over and is put down again with a ripple.
/// With [dropIn] it is dropped onto the board from above when first shown.
class HopTo extends StatefulWidget {
  const HopTo({
    super.key,
    required this.center,
    required this.size,
    required this.child,
    this.delay = Duration.zero,
    this.lift = 0,
    this.dropIn = false,
    this.rippleColor,
    this.onLand,
  });
  final Offset center;
  final double size;
  final Widget child;
  final Duration delay;
  final double lift;
  final bool dropIn;
  final Color? rippleColor;
  final VoidCallback? onLand;
  @override
  State<HopTo> createState() => _HopToState();
}

class _HopToState extends State<HopTo> with SingleTickerProviderStateMixin {
  static const _moveMs = 640, _rippleMs = 420;
  late final AnimationController _c = AnimationController(vsync: this)
    ..addListener(_tick);
  late Offset _from = widget.center, _to = widget.center;
  double _d0 = 0, _m1 = .6;
  bool _landed = true, _dropping = false;

  @override
  void initState() {
    super.initState();
    if (widget.dropIn) {
      _dropping = true;
      _from = widget.center - Offset(0, widget.size * 1.2);
      _go();
    } else {
      _c.value = 1;
    }
  }

  void _go() {
    final d = widget.delay.inMilliseconds;
    final total = d + _moveMs + _rippleMs;
    _d0 = d / total;
    _m1 = (d + _moveMs) / total;
    _landed = false;
    _c
      ..duration = Duration(milliseconds: total)
      ..forward(from: 0);
  }

  double get _move => _landed && _c.value >= 1
      ? 1
      : ((_c.value - _d0) / (_m1 - _d0)).clamp(0.0, 1.0);

  double _ease(double m) => _dropping
      ? Curves.easeInCubic.transform(m)
      : Curves.easeInOutCubic.transform(m);

  Offset _position(double e) =>
      Offset.lerp(_from, _to, e)! - Offset(0, widget.lift * sin(pi * e));

  void _tick() {
    if (!_landed && _c.value >= _m1) {
      _landed = true;
      widget.onLand?.call();
    }
  }

  @override
  void didUpdateWidget(HopTo old) {
    super.didUpdateWidget(old);
    if (old.center != widget.center) {
      _from = _position(_ease(_move));
      _to = widget.center;
      _dropping = false;
      _go();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final m = _move;
          final e = _ease(m);
          final r = ((_c.value - _m1) / (1 - _m1)).clamp(0.0, 1.0);
          final pos = _position(e);
          var scale =
              _dropping ? lerpDouble(2.4, 1, e)! : 1 + .22 * sin(pi * e);
          scale *= 1 - .1 * sin(pi * r) * (1 - r);
          final size = widget.size;
          return Positioned(
            left: pos.dx - size / 2,
            top: pos.dy - size / 2,
            width: size,
            height: size,
            child: Stack(clipBehavior: Clip.none, children: [
              if (widget.rippleColor != null && r > 0 && r < 1)
                Positioned.fill(
                  child: IgnorePointer(
                    child: OverflowBox(
                      minWidth: size * 2.6,
                      maxWidth: size * 2.6,
                      minHeight: size * 2.6,
                      maxHeight: size * 2.6,
                      child: CustomPaint(
                          painter: _RipplePainter(widget.rippleColor!, r)),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Opacity(
                  opacity: _dropping ? (m / .25).clamp(0.0, 1.0) : 1,
                  child: Transform.scale(scale: scale, child: child),
                ),
              ),
            ]),
          );
        },
      );
}

class _RipplePainter extends CustomPainter {
  const _RipplePainter(this.color, this.t);
  final Color color;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final max = size.shortestSide / 2;
    final e = Curves.easeOutCubic.transform(t);
    for (final k in const [0.0, .25]) {
      final p = ((e - k) / (1 - k)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      canvas.drawCircle(
          c,
          max * (.36 + .64 * p),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max * .06 * (1 - p) + .5
            ..color = color.withValues(alpha: .85 * (1 - p)));
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.t != t;
}
