import 'dart:math';
import 'package:flutter/material.dart';

/// Dark walnut table top filling the whole screen.
class WoodTable extends StatelessWidget {
  const WoodTable({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        const RepaintBoundary(child: CustomPaint(painter: _WoodPainter())),
        child,
      ]);
}

class _WoodPainter extends CustomPainter {
  const _WoodPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4A2E1C), Color(0xFF341F12), Color(0xFF442A19)],
          ).createShader(rect));
    final rng = Random(11);
    const planks = 6;
    final plankH = size.height / planks;
    for (var p = 0; p < planks; p++) {
      final top = p * plankH;
      final plank = Rect.fromLTWH(0, top, size.width, plankH);
      // every plank has its own tone
      final tone = rng.nextDouble();
      canvas.drawRect(
          plank,
          Paint()
            ..color = (tone > .5 ? const Color(0xFFB07A4A) : Colors.black)
                .withValues(alpha: .03 + rng.nextDouble() * .06));
      // grain: long wavy strokes
      for (var g = 0; g < 46; g++) {
        final y0 = top + rng.nextDouble() * plankH;
        final amp = 1 + rng.nextDouble() * 4;
        final freq = .002 + rng.nextDouble() * .006;
        final phase = rng.nextDouble() * pi * 2;
        final path = Path()..moveTo(0, y0);
        for (double x = 0; x <= size.width; x += 12) {
          path.lineTo(x, y0 + sin(x * freq + phase) * amp);
        }
        final light = rng.nextBool();
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = .5 + rng.nextDouble() * 1.4
              ..color =
                  (light ? const Color(0xFFC08A55) : const Color(0xFF1A0E07))
                      .withValues(alpha: .05 + rng.nextDouble() * .12));
      }
      // seam between planks + a butt joint somewhere along the plank
      canvas.drawLine(
          Offset(0, top),
          Offset(size.width, top),
          Paint()
            ..color = Colors.black.withValues(alpha: .55)
            ..strokeWidth = 2);
      canvas.drawLine(
          Offset(0, top + 2),
          Offset(size.width, top + 2),
          Paint()
            ..color = const Color(0xFFD9A46C).withValues(alpha: .07)
            ..strokeWidth = 1);
      final jx = size.width * (.15 + rng.nextDouble() * .7);
      canvas.drawLine(
          Offset(jx, top),
          Offset(jx, top + plankH),
          Paint()
            ..color = Colors.black.withValues(alpha: .45)
            ..strokeWidth = 1.6);
    }
    // warm light from above, dark edges
    canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, -.2),
            radius: 1.0,
            colors: [
              const Color(0xFFFFD9A0).withValues(alpha: .10),
              Colors.transparent,
              Colors.black.withValues(alpha: .62),
            ],
            stops: const [0, .55, 1],
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Green leather play mat with stitched edge, lying on the table.
class LeatherMat extends StatelessWidget {
  const LeatherMat({super.key, required this.child, this.radius = 22});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: .6),
                blurRadius: 24,
                offset: const Offset(0, 10)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: CustomPaint(
            painter: _MatPainter(radius),
            // keep animated content from repainting the leather texture
            child: RepaintBoundary(child: child),
          ),
        ),
      );
}

class _MatPainter extends CustomPainter {
  const _MatPainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            radius: .9,
            colors: [Color(0xFF24493A), Color(0xFF173226), Color(0xFF0E2119)],
            stops: [0, .6, 1],
          ).createShader(rect));
    // pebbled leather grain
    final rng = Random(5);
    final dots = Paint();
    final count = (size.width * size.height / 90).clamp(0, 9000).toInt();
    for (var i = 0; i < count; i++) {
      dots.color = (rng.nextBool() ? Colors.white : Colors.black)
          .withValues(alpha: rng.nextDouble() * .05);
      canvas.drawCircle(
          Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
          .6 + rng.nextDouble() * 1.3,
          dots);
    }
    // stitching
    final inset = radius * .45;
    final stitch = RRect.fromRectAndRadius(
        rect.deflate(inset), Radius.circular(radius - inset));
    final path = Path()..addRRect(stitch);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD8C08A).withValues(alpha: .55);
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
    // raised edge
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1.5), Radius.circular(radius)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.black.withValues(alpha: .45));
  }

  @override
  bool shouldRepaint(covariant _MatPainter oldDelegate) =>
      oldDelegate.radius != radius;
}
