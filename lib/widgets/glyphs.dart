import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../models/wish.dart';

/// Hand-drawn line icons on a 24-unit grid. One consistent stroke and round
/// joins keep the set feeling like a single family, unlike stock icon packs.
enum GlyphKind {
  well,
  spark,
  constellation,
  sliders,
  briefcase,
  heart,
  leaf,
  plane,
  house,
  cup,
  coin,
  moon,
  check,
  chevronRight,
  chevronLeft,
  close,
  refresh,
  door,
  bell,
  sun,
  starPlus,
  chest,
  gear,
  trophy,
  shield,
  document,
  mail,
  share,
  download,
  trash,
  info,
  vibrate,
  lock,
  user,
}

extension CategoryGlyph on WishCategory {
  GlyphKind get glyph => switch (this) {
        WishCategory.career => GlyphKind.briefcase,
        WishCategory.love => GlyphKind.heart,
        WishCategory.health => GlyphKind.leaf,
        WishCategory.travel => GlyphKind.plane,
        WishCategory.home => GlyphKind.house,
        WishCategory.daily => GlyphKind.spark,
      };
}

extension StatusGlyph on WishStatus {
  GlyphKind get glyph => switch (this) {
        WishStatus.active => GlyphKind.spark,
        WishStatus.closer => GlyphKind.moon,
        WishStatus.granted => GlyphKind.spark,
        WishStatus.changed => GlyphKind.refresh,
        WishStatus.doorOpened => GlyphKind.door,
        WishStatus.letGo => GlyphKind.leaf,
      };
}

class Glyph extends StatelessWidget {
  final GlyphKind kind;
  final double size;
  final Color color;
  final double stroke;
  final bool filled;

  const Glyph(
    this.kind, {
    super.key,
    this.size = 22,
    this.color = Colors.white,
    this.stroke = 1.6,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _GlyphPainter(kind, color, stroke, filled)),
      );
}

/// A four-point star path centred at [c] with outer radius [r].
Path starPath(Offset c, double r, {double pinch = 0.16}) {
  final p = Path();
  final k = r * pinch;
  p.moveTo(c.dx, c.dy - r);
  p.quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy);
  p.quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r);
  p.quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy);
  p.quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r);
  p.close();
  return p;
}

class _GlyphPainter extends CustomPainter {
  final GlyphKind kind;
  final Color color;
  final double stroke;
  final bool filled;
  _GlyphPainter(this.kind, this.color, this.stroke, this.filled);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.scale(s);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    Paint shape() => filled ? fill : line;

    switch (kind) {
      case GlyphKind.spark:
        canvas.drawPath(starPath(const Offset(12, 12), 10, pinch: 0.12), shape());
      case GlyphKind.well:
        // A wishing well: pitched roof, two posts, rope, stone wall.
        canvas.drawPath(
            Path()
              ..moveTo(3.5, 7)
              ..lineTo(12, 2.4)
              ..lineTo(20.5, 7),
            line);
        canvas.drawLine(const Offset(6, 6), const Offset(6, 13), line);
        canvas.drawLine(const Offset(18, 6), const Offset(18, 13), line);
        canvas.drawLine(const Offset(12, 5), const Offset(12, 10), line);
        canvas.drawCircle(const Offset(12, 11), 1.1, fill);
        canvas.drawPath(
            Path()
              ..moveTo(4, 13)
              ..lineTo(20, 13)
              ..lineTo(20, 19)
              ..quadraticBezierTo(20, 21, 18, 21)
              ..lineTo(6, 21)
              ..quadraticBezierTo(4, 21, 4, 19)
              ..close(),
            line);
      case GlyphKind.constellation:
        const pts = [Offset(4, 17), Offset(10, 11), Offset(15, 14.5), Offset(20, 6)];
        canvas.drawPoints(PointMode.polygon, pts, line..strokeWidth = stroke * 0.7);
        for (final p in pts) {
          canvas.drawCircle(p, 1.9, fill);
        }
      case GlyphKind.sliders:
        canvas.drawLine(const Offset(4, 8), const Offset(6.6, 8), line);
        canvas.drawLine(const Offset(11.4, 8), const Offset(20, 8), line);
        canvas.drawCircle(const Offset(9, 8), 2.4, line);
        canvas.drawLine(const Offset(4, 16), const Offset(12.6, 16), line);
        canvas.drawLine(const Offset(17.4, 16), const Offset(20, 16), line);
        canvas.drawCircle(const Offset(15, 16), 2.4, line);
      case GlyphKind.briefcase:
        canvas.drawRRect(
            RRect.fromLTRBR(3, 8, 21, 20, const Radius.circular(2.4)), shape());
        final handle = Path()
          ..moveTo(9, 8)
          ..lineTo(9, 6.6)
          ..cubicTo(9, 5.7, 9.7, 5, 10.6, 5)
          ..lineTo(13.4, 5)
          ..cubicTo(14.3, 5, 15, 5.7, 15, 6.6)
          ..lineTo(15, 8);
        canvas.drawPath(handle, line);
        if (!filled) canvas.drawLine(const Offset(3, 13), const Offset(21, 13), line);
      case GlyphKind.heart:
        final p = Path()
          ..moveTo(12, 20)
          ..cubicTo(5, 15, 3, 11.5, 3, 8.8)
          ..cubicTo(3, 6.4, 4.8, 4.6, 7.1, 4.6)
          ..cubicTo(9.2, 4.6, 11, 5.8, 12, 7.6)
          ..cubicTo(13, 5.8, 14.8, 4.6, 16.9, 4.6)
          ..cubicTo(19.2, 4.6, 21, 6.4, 21, 8.8)
          ..cubicTo(21, 11.5, 19, 15, 12, 20)
          ..close();
        canvas.drawPath(p, shape());
      case GlyphKind.leaf:
        final p = Path()
          ..moveTo(5, 19)
          ..cubicTo(5, 10, 10, 5, 19, 5)
          ..cubicTo(19, 14, 14, 19, 5, 19)
          ..close();
        canvas.drawPath(p, shape());
        canvas.drawLine(const Offset(5, 19), const Offset(13, 11), line);
      case GlyphKind.plane:
        final p = Path()
          ..moveTo(3, 11)
          ..lineTo(21, 3)
          ..lineTo(14, 21)
          ..lineTo(11, 13)
          ..close();
        canvas.drawPath(p, shape());
        canvas.drawLine(const Offset(11, 13), const Offset(21, 3), line);
      case GlyphKind.house:
        final p = Path()
          ..moveTo(4, 11)
          ..lineTo(12, 4)
          ..lineTo(20, 11)
          ..lineTo(20, 19)
          ..quadraticBezierTo(20, 20, 19, 20)
          ..lineTo(5, 20)
          ..quadraticBezierTo(4, 20, 4, 19)
          ..close();
        if (filled) {
          canvas.drawPath(
              Path.combine(PathOperation.difference, p,
                  Path()..addRect(const Rect.fromLTRB(10, 14.5, 14, 21))),
              fill);
        } else {
          canvas.drawPath(p, line);
          canvas.drawPath(
              Path()
                ..moveTo(10, 20)
                ..lineTo(10, 14.5)
                ..lineTo(14, 14.5)
                ..lineTo(14, 20),
              line);
        }
      case GlyphKind.cup:
        final p = Path()
          ..moveTo(5, 9.5)
          ..lineTo(16, 9.5)
          ..lineTo(16, 14)
          ..cubicTo(16, 16.8, 13.8, 19, 11, 19)
          ..lineTo(10, 19)
          ..cubicTo(7.2, 19, 5, 16.8, 5, 14)
          ..close();
        canvas.drawPath(p, shape());
        canvas.drawPath(
            Path()
              ..moveTo(16, 10.5)
              ..lineTo(17.4, 10.5)
              ..cubicTo(18.8, 10.5, 20, 11.5, 20, 12.7)
              ..cubicTo(20, 14, 18.8, 15, 17.4, 15)
              ..lineTo(16, 15),
            line);
        canvas.drawPath(
            Path()
              ..moveTo(8.4, 3.8)
              ..cubicTo(7.6, 5, 9.2, 5.6, 8.4, 6.9),
            line);
        canvas.drawPath(
            Path()
              ..moveTo(12.4, 3.8)
              ..cubicTo(11.6, 5, 13.2, 5.6, 12.4, 6.9),
            line);
      case GlyphKind.coin:
        canvas.drawCircle(const Offset(12, 12), 8.4, shape());
        canvas.drawPath(starPath(const Offset(12, 12), 3.6, pinch: 0.2),
            filled ? (Paint()..color = const Color(0xFF0A0919)) : fill);
      case GlyphKind.moon:
        final p = Path()
          ..moveTo(19.5, 14.6)
          ..arcToPoint(const Offset(9.4, 4.5),
              radius: const Radius.circular(8.6), clockwise: true)
          ..arcToPoint(const Offset(19.5, 14.6),
              radius: const Radius.circular(7), clockwise: false)
          ..close();
        canvas.drawPath(p, shape());
      case GlyphKind.check:
        canvas.drawPath(
            Path()
              ..moveTo(5, 12.8)
              ..lineTo(9.8, 17.5)
              ..lineTo(19, 7),
            line);
      case GlyphKind.chevronRight:
        canvas.drawPath(
            Path()
              ..moveTo(9, 5)
              ..lineTo(16, 12)
              ..lineTo(9, 19),
            line);
      case GlyphKind.chevronLeft:
        canvas.drawPath(
            Path()
              ..moveTo(15, 5)
              ..lineTo(8, 12)
              ..lineTo(15, 19),
            line);
      case GlyphKind.close:
        canvas.drawLine(const Offset(6, 6), const Offset(18, 18), line);
        canvas.drawLine(const Offset(18, 6), const Offset(6, 18), line);
      case GlyphKind.refresh:
        const a0 = -math.pi / 2 + 0.55;
        const sweep = 1.5 * math.pi;
        canvas.drawArc(Rect.fromCircle(center: const Offset(12, 12), radius: 7.2),
            a0, sweep, false, line);
        const end = a0 + sweep;
        final e = Offset(12 + 7.2 * math.cos(end), 12 + 7.2 * math.sin(end));
        final back = end + math.pi / 2 + math.pi; // tangent reversed
        for (final d in const [0.55, -0.55]) {
          canvas.drawLine(
              e, e + Offset(math.cos(back + d), math.sin(back + d)) * 4, line);
        }
      case GlyphKind.door:
        canvas.drawPath(
            Path()
              ..moveTo(6, 20)
              ..lineTo(6, 6)
              ..cubicTo(6, 4.9, 6.9, 4, 8, 4)
              ..lineTo(16, 4)
              ..cubicTo(17.1, 4, 18, 4.9, 18, 6)
              ..lineTo(18, 20),
            line);
        canvas.drawLine(const Offset(3.5, 20), const Offset(20.5, 20), line);
        canvas.drawCircle(const Offset(15, 12.4), 1, fill);
      case GlyphKind.bell:
        final p = Path()
          ..moveTo(6, 16)
          ..lineTo(6, 11)
          ..arcToPoint(const Offset(18, 11),
              radius: const Radius.circular(6), clockwise: true)
          ..lineTo(18, 16)
          ..lineTo(19.6, 18)
          ..lineTo(4.4, 18)
          ..close();
        canvas.drawPath(p, shape());
        canvas.drawLine(const Offset(10, 21), const Offset(14, 21), line);
      case GlyphKind.starPlus:
        final star = Path();
        const c = Offset(10.5, 14);
        for (var i = 0; i < 10; i++) {
          final rad = i.isEven ? 8.6 : 3.8;
          final a = -math.pi / 2 + i * math.pi / 5;
          final pt = c + Offset(math.cos(a), math.sin(a)) * rad;
          i == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
        }
        star.close();
        canvas.drawPath(star, shape()..strokeJoin = StrokeJoin.round);
        canvas.drawLine(const Offset(19, 2.5), const Offset(19, 8.5), line);
        canvas.drawLine(const Offset(16, 5.5), const Offset(22, 5.5), line);
      case GlyphKind.chest:
        final body = Path()
          ..moveTo(3, 20)
          ..lineTo(3, 9)
          ..cubicTo(3, 5.6, 7, 4, 12, 4)
          ..cubicTo(17, 4, 21, 5.6, 21, 9)
          ..lineTo(21, 20)
          ..close();
        if (filled) {
          canvas.drawPath(
              Path.combine(PathOperation.difference, body,
                  Path()..addOval(Rect.fromCircle(center: const Offset(12, 13.2), radius: 2.1))),
              fill);
        } else {
          canvas.drawPath(body, line);
          canvas.drawLine(const Offset(3, 13), const Offset(21, 13), line);
          canvas.drawCircle(const Offset(12, 13.2), 2.1, line);
        }
      case GlyphKind.gear:
        final gear = Path();
        var first = true;
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          for (final (off, rad) in const [(-0.36, 7.4), (-0.2, 10.2), (0.2, 10.2), (0.36, 7.4)]) {
            final pt = const Offset(12, 12) + Offset(math.cos(a + off), math.sin(a + off)) * rad;
            first ? gear.moveTo(pt.dx, pt.dy) : gear.lineTo(pt.dx, pt.dy);
            first = false;
          }
        }
        gear.close();
        final hole = Path()..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 3.2));
        if (filled) {
          canvas.drawPath(Path.combine(PathOperation.difference, gear, hole), fill);
        } else {
          canvas.drawPath(gear, line);
          canvas.drawPath(hole, line);
        }
      case GlyphKind.trophy:
        final cup = Path()
          ..moveTo(7, 4)
          ..lineTo(17, 4)
          ..lineTo(17, 9)
          ..cubicTo(17, 12, 14.8, 14.2, 12, 14.2)
          ..cubicTo(9.2, 14.2, 7, 12, 7, 9)
          ..close();
        canvas.drawPath(cup, shape());
        canvas.drawPath(
            Path()
              ..moveTo(7, 6)
              ..lineTo(4.4, 6)
              ..cubicTo(4.4, 9.4, 5.6, 10.8, 7.6, 11.2),
            line);
        canvas.drawPath(
            Path()
              ..moveTo(17, 6)
              ..lineTo(19.6, 6)
              ..cubicTo(19.6, 9.4, 18.4, 10.8, 16.4, 11.2),
            line);
        canvas.drawLine(const Offset(12, 14.2), const Offset(12, 17.4), line);
        canvas.drawLine(const Offset(8.5, 20), const Offset(15.5, 20), line);
        canvas.drawLine(const Offset(9.5, 17.4), const Offset(14.5, 17.4), line);
      case GlyphKind.sun:
        canvas.drawCircle(const Offset(12, 12), 4, shape());
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawLine(
            Offset(12 + 7 * math.cos(a), 12 + 7 * math.sin(a)),
            Offset(12 + 9.4 * math.cos(a), 12 + 9.4 * math.sin(a)),
            line,
          );
        }
      case GlyphKind.shield:
        final body = Path()
          ..moveTo(12, 2.8)
          ..lineTo(19, 5.6)
          ..lineTo(19, 11.5)
          ..cubicTo(19, 16, 16, 19.6, 12, 21.2)
          ..cubicTo(8, 19.6, 5, 16, 5, 11.5)
          ..lineTo(5, 5.6)
          ..close();
        canvas.drawPath(body, shape());
        canvas.drawPath(
            Path()
              ..moveTo(8.8, 12)
              ..lineTo(11, 14.2)
              ..lineTo(15.2, 9.6),
            filled ? (Paint()..color = const Color(0xFF160F3A)..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round) : line);
      case GlyphKind.document:
        final page = Path()
          ..moveTo(7, 3)
          ..lineTo(14, 3)
          ..lineTo(19, 8)
          ..lineTo(19, 21)
          ..lineTo(7, 21)
          ..close();
        canvas.drawPath(page, shape());
        final ink = filled ? (Paint()..color = const Color(0xFF160F3A)..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round) : line;
        canvas.drawPath(
            Path()
              ..moveTo(14, 3)
              ..lineTo(14, 8)
              ..lineTo(19, 8),
            ink);
        canvas.drawLine(const Offset(9.8, 13), const Offset(16.2, 13), ink);
        canvas.drawLine(const Offset(9.8, 16.6), const Offset(14.2, 16.6), ink);
      case GlyphKind.mail:
        final env = RRect.fromRectAndRadius(
            const Rect.fromLTRB(3, 5.5, 21, 18.5), const Radius.circular(2.6));
        canvas.drawRRect(env, shape());
        canvas.drawPath(
            Path()
              ..moveTo(3.8, 7.2)
              ..lineTo(12, 13.2)
              ..lineTo(20.2, 7.2),
            filled ? (Paint()..color = const Color(0xFF160F3A)..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round) : line);
      case GlyphKind.share:
        canvas.drawPath(
            Path()
              ..moveTo(8, 10)
              ..lineTo(6, 10)
              ..lineTo(6, 20)
              ..lineTo(18, 20)
              ..lineTo(18, 10)
              ..lineTo(16, 10),
            line);
        canvas.drawLine(const Offset(12, 3.6), const Offset(12, 14), line);
        canvas.drawPath(
            Path()
              ..moveTo(8.4, 7)
              ..lineTo(12, 3.4)
              ..lineTo(15.6, 7),
            line);
      case GlyphKind.download:
        canvas.drawPath(
            Path()
              ..moveTo(5, 15)
              ..lineTo(5, 19.5)
              ..lineTo(19, 19.5)
              ..lineTo(19, 15),
            line);
        canvas.drawLine(const Offset(12, 4), const Offset(12, 15), line);
        canvas.drawPath(
            Path()
              ..moveTo(8, 11.2)
              ..lineTo(12, 15.2)
              ..lineTo(16, 11.2),
            line);
      case GlyphKind.trash:
        canvas.drawLine(const Offset(4.5, 6.5), const Offset(19.5, 6.5), line);
        canvas.drawPath(
            Path()
              ..moveTo(9.5, 6.5)
              ..lineTo(9.5, 4)
              ..lineTo(14.5, 4)
              ..lineTo(14.5, 6.5),
            line);
        canvas.drawPath(
            Path()
              ..moveTo(6.5, 9.2)
              ..lineTo(7.6, 19.6)
              ..quadraticBezierTo(7.7, 20.7, 8.9, 20.7)
              ..lineTo(15.1, 20.7)
              ..quadraticBezierTo(16.3, 20.7, 16.4, 19.6)
              ..lineTo(17.5, 9.2),
            line);
        canvas.drawLine(const Offset(10.2, 11.5), const Offset(10.2, 17.2), line);
        canvas.drawLine(const Offset(13.8, 11.5), const Offset(13.8, 17.2), line);
      case GlyphKind.info:
        canvas.drawCircle(const Offset(12, 12), 9, line);
        canvas.drawCircle(const Offset(12, 7.9), 1.15, fill);
        canvas.drawLine(const Offset(12, 11.2), const Offset(12, 16.6), line);
      case GlyphKind.vibrate:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTRB(8, 3.5, 16, 20.5), const Radius.circular(2.4)),
            shape());
        canvas.drawLine(const Offset(11, 17.6), const Offset(13, 17.6),
            filled ? (Paint()..color = const Color(0xFF160F3A)..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round) : line);
        for (final dx in const [-1.0, 1.0]) {
          final x = 12 + dx * 6.4;
          canvas.drawPath(
              Path()
                ..moveTo(x, 8.6)
                ..lineTo(x + dx * 1.7, 12)
                ..lineTo(x, 15.4),
              line);
        }
      case GlyphKind.lock:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTRB(5.5, 10.5, 18.5, 20.8), const Radius.circular(2.6)),
            shape());
        canvas.drawPath(
            Path()
              ..moveTo(8.6, 10.5)
              ..lineTo(8.6, 8)
              ..arcToPoint(const Offset(15.4, 8),
                  radius: const Radius.circular(3.4), clockwise: true)
              ..lineTo(15.4, 10.5),
            line);
      case GlyphKind.user:
        canvas.drawCircle(const Offset(12, 8.4), 3.7, shape());
        canvas.drawPath(
            Path()
              ..moveTo(4.8, 20.2)
              ..cubicTo(4.8, 15.8, 8, 14, 12, 14)
              ..cubicTo(16, 14, 19.2, 15.8, 19.2, 20.2),
            line);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.kind != kind || old.color != color || old.stroke != stroke || old.filled != filled;
}
