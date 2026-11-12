import 'dart:math';
import 'package:flutter/material.dart';

const notebookInk = Color(0xFF39291D);
const notebookGold = Color(0xFF94703B);

/// Static vector parchment: no animation loop, textures or full-size bitmaps.
class NotebookPainter extends CustomPainter {
  const NotebookPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final unit = size.height / 500;
    final cover = RRect.fromRectAndRadius(
        rect.deflate(2 * unit), Radius.circular(12 * unit));
    canvas.drawShadow(Path()..addRRect(cover), Colors.black, 12 * unit, true);
    canvas.drawRRect(cover, Paint()..color = const Color(0xFF55391F));
    canvas.drawRRect(
        cover.deflate(4 * unit), Paint()..color = const Color(0xFFB08B53));
    final paper = rect.deflate(9 * unit);
    final middle = size.width / 2;
    for (var side = 0; side < 2; side++) {
      final page = Rect.fromLTRB(side == 0 ? paper.left : middle, paper.top,
          side == 0 ? middle : paper.right, paper.bottom);
      canvas.drawRect(
          page,
          Paint()
            ..shader = LinearGradient(
              colors: side == 0
                  ? const [
                      Color(0xFFD3B67B),
                      Color(0xFFF6E8BE),
                      Color(0xFFEBD5A1),
                      Color(0xFFC2A168)
                    ]
                  : const [
                      Color(0xFFB99A64),
                      Color(0xFFF1DFB0),
                      Color(0xFFF5E6BF),
                      Color(0xFFD8BB83)
                    ],
              stops: const [0, .13, .86, 1],
            ).createShader(page));
      final random = Random(41 + side);
      canvas.save();
      canvas.clipRect(page);
      for (var i = 0; i < 1500; i++) {
        canvas.drawCircle(
            Offset(page.left + random.nextDouble() * page.width,
                page.top + random.nextDouble() * page.height),
            (.2 + random.nextDouble() * 1.4) * unit,
            Paint()
              ..color = const Color(0xFF856139)
                  .withValues(alpha: .025 + random.nextDouble() * .045));
      }
      for (var y = page.top + 79 * unit;
          y < page.bottom - 31 * unit;
          y += 23 * unit) {
        canvas.drawLine(
            Offset(page.left + 34 * unit, y),
            Offset(page.right - 34 * unit, y),
            Paint()
              ..strokeWidth = .6 * unit
              ..color = notebookGold.withValues(alpha: .14));
      }
      canvas.restore();
      final frame = page.deflate(17 * unit);
      canvas.drawRect(
          frame,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8 * unit
            ..color = notebookGold.withValues(alpha: .52));
      for (final corner in [0, 1, 2, 3]) {
        canvas.save();
        canvas.translate(corner.isEven ? frame.left : frame.right,
            corner < 2 ? frame.top : frame.bottom);
        canvas.scale(corner.isEven ? 1 : -1, corner < 2 ? 1 : -1);
        _corner(canvas, unit);
        canvas.restore();
      }
      // A faint crossed-sword watermark, kept behind all text.
      canvas.save();
      canvas.translate(page.center.dx, page.center.dy + 20 * unit);
      final ink = Paint()
        ..color = notebookGold.withValues(alpha: .075)
        ..strokeWidth = 7 * unit
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(-45 * unit, 50 * unit), Offset(45 * unit, -50 * unit), ink);
      canvas.drawLine(
          Offset(45 * unit, 50 * unit), Offset(-45 * unit, -50 * unit), ink);
      canvas.drawLine(Offset(-39 * unit, 25 * unit),
          Offset(-17 * unit, 46 * unit), ink..strokeWidth = 4 * unit);
      canvas.drawLine(
          Offset(39 * unit, 25 * unit), Offset(17 * unit, 46 * unit), ink);
      canvas.restore();
    }
    final fold = Rect.fromCenter(
        center: rect.center, width: 24 * unit, height: paper.height);
    canvas.drawRect(
        fold,
        Paint()
          ..shader = LinearGradient(colors: [
            Colors.transparent,
            const Color(0xFF5F452B).withValues(alpha: .25),
            const Color(0xFFFFF4CB).withValues(alpha: .24),
            Colors.transparent,
          ], stops: const [
            0,
            .48,
            .54,
            1
          ]).createShader(fold));
  }

  void _corner(Canvas canvas, double unit) {
    canvas.scale(unit);
    final paint = Paint()
      ..color = notebookGold.withValues(alpha: .65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(
        Path()
          ..moveTo(0, 76)
          ..lineTo(0, 0)
          ..lineTo(76, 0),
        paint..strokeWidth = 2);
    canvas.drawPath(
        Path()
          ..moveTo(5, 62)
          ..lineTo(5, 5)
          ..lineTo(62, 5),
        paint..strokeWidth = .8);
    for (var i = 0; i < 4; i++) {
      final d = 12.0 + i * 12;
      canvas.drawPath(
          Path()
            ..moveTo(d + 15, 8)
            ..cubicTo(d + 3, 9, d + 8, 24, d - 1, 20)
            ..cubicTo(d - 10, 12, d + 6, 5, d + 5, 13),
          paint);
      canvas.drawPath(
          Path()
            ..moveTo(8, d + 15)
            ..cubicTo(9, d + 3, 24, d + 8, 20, d - 1)
            ..cubicTo(12, d - 10, 5, d + 6, 13, d + 5),
          paint);
    }
    canvas.drawPath(
        Path()
          ..moveTo(12, 12)
          ..quadraticBezierTo(43, 10, 24, 24)
          ..quadraticBezierTo(10, 43, 12, 12),
        paint);
    canvas.drawCircle(const Offset(15, 15), 2.5, Paint()..color = notebookGold);
  }

  @override
  bool shouldRepaint(covariant NotebookPainter oldDelegate) => false;
}
