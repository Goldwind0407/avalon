import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/assets.dart';
import '../table/effects.dart';

/// Opening animation: the Goldwind signature is written onto parchment,
/// the little star pops in, a glint of gold runs along the ink, then the app
/// fades in. Tapping anywhere skips it.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.next});

  /// The screen that follows (the home screen).
  final WidgetBuilder next;

  /// Same colour as the native launch screens (Android colors.xml,
  /// iOS LaunchScreen.storyboard), so starting the app has no flash.
  static const parchment = Color(0xFFEEE3CD);

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  // timeline, in milliseconds
  static const _writeFrom = 350.0, _writeTo = 2050.0;
  static const _starFrom = 1950.0, _starTo = 2650.0;
  static const _shineFrom = 2450.0, _shineTo = 3350.0;
  static const _total = 3900.0;

  /// Where the star sits in the signature artwork (1997 × 788).
  static const _sigSize = Size(1997, 788);
  static const _star = Rect.fromLTWH(1025, 466, 279, 249);

  late final AnimationController _c = AnimationController(
      vsync: this, duration: Duration(milliseconds: _total.round()))
    ..addListener(_tick)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _leave();
    });
  bool _starLanded = false, _left = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // decode the artwork before it is needed
    precacheImage(const AssetImage(Assets.signature), context);
    precacheImage(const AssetImage(Assets.signatureStar), context);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _seg(double from, double to) =>
      ((_c.value * _total - from) / (to - from)).clamp(0.0, 1.0);

  void _tick() {
    if (!_starLanded && _c.value * _total >= _starFrom + 260) {
      _starLanded = true;
      HapticFeedback.lightImpact();
    }
  }

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 750),
      pageBuilder: (context, _, __) => widget.next(context),
      transitionsBuilder: (context, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeInOut),
        child: child,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: IntroScreen.parchment,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _leave,
          child: Stack(fit: StackFit.expand, children: [
            const RepaintBoundary(child: CustomPaint(painter: _PaperPainter())),
            LayoutBuilder(builder: (context, c) {
              final width = min(c.maxWidth * .62, c.maxHeight * 1.55);
              return Center(
                child: SizedBox(
                  width: width,
                  height: width * _sigSize.height / _sigSize.width,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => _signature(width),
                  ),
                ),
              );
            }),
          ]),
        ),
      );

  Widget _signature(double width) {
    final k = width / _sigSize.width;
    final write = Curves.easeInOutSine.transform(_seg(_writeFrom, _writeTo));
    final starT = _seg(_starFrom, _starTo);
    final shine = _seg(_shineFrom, _shineTo);
    // whole piece settles in slightly, like a sheet being laid down
    final settle = Curves.easeOutCubic.transform(_seg(0, 900));
    const edge = .08; // softness of the pen edge
    final image = Image.asset(Assets.signature,
        width: width, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
    return Transform.scale(
      scale: 1.04 - .04 * settle,
      child: Stack(clipBehavior: Clip.none, children: [
        // ink written from left to right
        Positioned.fill(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => LinearGradient(
              begin: const Alignment(-1, -.15),
              end: const Alignment(1, .15),
              colors: const [Colors.white, Colors.white, Color(0x00FFFFFF)],
              stops: [0, write * (1 + edge), write * (1 + edge) + edge]
                  .map((v) => (v - edge).clamp(0.0, 1.0))
                  .toList(),
            ).createShader(r),
            child: image,
          ),
        ),
        // a glint of gold that runs along the ink, only where there is ink
        if (shine > 0 && shine < 1)
          Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) {
                final x =
                    lerpDouble(-.3, 1.3, Curves.easeInOut.transform(shine))!;
                return LinearGradient(
                  begin: const Alignment(-1, -.4),
                  end: const Alignment(1, .4),
                  colors: const [
                    Color(0x00F2C14E),
                    Color(0x8CFFD978),
                    Color(0x00F2C14E),
                  ],
                  stops: [
                    (x - .12).clamp(0.0, 1.0),
                    x.clamp(0.0, 1.0),
                    (x + .12).clamp(0.0, 1.0),
                  ],
                ).createShader(r);
              },
              child: image,
            ),
          ),
        // the star pops in once the line is drawn
        if (starT > 0)
          Positioned(
            left: _star.left * k,
            top: _star.top * k,
            width: _star.width * k,
            height: _star.height * k,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: GlowBurst(
                  color: const Color(0xFFE8B84A),
                  size: _star.width * k * 3.2,
                  delay: const Duration(milliseconds: 180),
                  duration: const Duration(milliseconds: 900),
                ),
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: (starT * 4).clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: -.9 * (1 - Curves.easeOutBack.transform(starT)),
                    child: Transform.scale(
                      scale: Curves.elasticOut.transform(starT),
                      child: Image.asset(Assets.signatureStar,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium),
                    ),
                  ),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Warm parchment with a soft vignette and a little fibre.
class _PaperPainter extends CustomPainter {
  const _PaperPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            radius: 1.1,
            colors: [Color(0xFFF5ECDA), Color(0xFFEEE3CD), Color(0xFFD9C7A3)],
            stops: [0, .55, 1],
          ).createShader(rect));
    final rng = Random(3);
    final fibre = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 260; i++) {
      final p =
          Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height);
      final a = rng.nextDouble() * pi;
      final l = 4 + rng.nextDouble() * 14;
      fibre
        ..strokeWidth = .6 + rng.nextDouble() * .8
        ..color = const Color(0xFF8A6A3A)
            .withValues(alpha: .03 + rng.nextDouble() * .05);
      canvas.drawLine(p, p + Offset(cos(a), sin(a)) * l, fibre);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
