import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A stone well seen from slightly above, painted in layers: wall, rim, inner
/// lip, then dark water that picks up light from the orb as it approaches.
///
/// [glow] 0..1 is how close the orb is; [ripple] 0..1 drives expanding rings
/// across the water; [bloom] 0..1 is the flash as the wish lands.
class WellPainter extends CustomPainter {
  final double glow;
  final double ripple;
  final double bloom;
  final double phase;
  WellPainter({this.glow = 0, this.ripple = 0, this.bloom = 0, this.phase = 0});

  /// Height of a well that is [width] wide.
  static double heightFor(double width) => width * 0.36 + width * 0.13;

  /// Center of the water surface, in the painter's own coordinates.
  static Offset waterCenter(Size s) => Offset(s.width / 2, s.width * 0.36 / 2);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final eh = w * 0.36; // height of the rim ellipse
    final th = w * 0.13; // wall thickness

    final top = Rect.fromLTWH(0, 0, w, eh);
    final bottom = top.shift(Offset(0, th));

    // Ground glow beneath the well.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w / 2, eh / 2 + th + eh * 0.12), width: w * 1.25, height: eh * 0.9),
      Paint()
        ..shader = RadialGradient(colors: [
          MW.violet.withValues(alpha: 0.22 + 0.2 * glow),
          Colors.transparent,
        ]).createShader(Rect.fromCenter(
            center: Offset(w / 2, eh / 2 + th + eh * 0.12), width: w * 1.25, height: eh * 0.9)),
    );

    // Wall: union of both ellipses and the band between them.
    final wall = Path.combine(
      PathOperation.union,
      Path()..addOval(bottom),
      Path.combine(
        PathOperation.union,
        Path()..addOval(top),
        Path()..addRect(Rect.fromLTRB(0, eh / 2, w, eh / 2 + th)),
      ),
    );
    canvas.drawPath(
      wall,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [Color(0xFF1B1750), Color(0xFF3B3480), Color(0xFF2A2468), Color(0xFF121038)],
          stops: const [0, 0.38, 0.7, 1],
        ).createShader(Rect.fromLTWH(0, 0, w, eh + th)),
    );
    // Shade the lower wall so it turns away from the light.
    canvas.drawPath(
      wall,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, MW.inkDeep.withValues(alpha: 0.55)],
          stops: const [0.45, 1],
        ).createShader(Rect.fromLTWH(0, 0, w, eh + th)),
    );

    // Stone courses: faint curved joints on the wall.
    final joint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.black.withValues(alpha: 0.22);
    for (final x in [0.16, 0.34, 0.52, 0.7, 0.88]) {
      final cx = w * x;
      final yTop = eh / 2 + math.sqrt(math.max(0, 1 - math.pow((cx - w / 2) / (w / 2), 2))) * eh / 2;
      canvas.drawLine(Offset(cx, yTop), Offset(cx, yTop + th), joint);
    }

    // Rim face.
    canvas.drawOval(
      top,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A52A8), Color(0xFF332D78)],
        ).createShader(top),
    );
    // Rim highlight along the far edge.
    canvas.drawArc(
      top.deflate(0.8),
      math.pi * 1.08,
      math.pi * 0.84,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.5),
          Colors.transparent,
        ]).createShader(top),
    );

    // Water.
    final water = Rect.fromLTRB(w * 0.07, eh * 0.15, w * 0.93, eh * 0.85);
    final center = water.center;
    canvas.save();
    canvas.clipPath(Path()..addOval(water));
    canvas.drawRect(
      water,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.2),
          colors: [Color(0xFF14113A), Color(0xFF05040E)],
        ).createShader(water),
    );
    // Light from the orb, pooling on the surface.
    final lit = (glow * 0.8 + bloom).clamp(0.0, 1.0);
    canvas.drawRect(
      water,
      Paint()
        ..shader = RadialGradient(colors: [
          MW.goldBright.withValues(alpha: 0.75 * lit),
          MW.gold.withValues(alpha: 0.28 * lit),
          MW.water.withValues(alpha: 0.10 * lit),
          Colors.transparent,
        ], stops: const [0, 0.3, 0.6, 1]).createShader(water),
    );
    // Reflected stars.
    final rng = math.Random(3);
    for (var i = 0; i < 9; i++) {
      final p = Offset(
        water.left + rng.nextDouble() * water.width,
        water.top + rng.nextDouble() * water.height,
      );
      final tw = 0.5 + 0.5 * math.sin(phase * math.pi * 2 * (1 + i % 3) + i);
      canvas.drawCircle(p, 0.5 + rng.nextDouble() * 0.8,
          Paint()..color = Colors.white.withValues(alpha: 0.18 + 0.3 * tw));
    }
    // Ripples spread from the point of entry.
    for (var k = 0; k < 3; k++) {
      final p = ((ripple - k * 0.16) / (1 - k * 0.16)).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final e = Curves.easeOutCubic.transform(p);
      canvas.drawOval(
        Rect.fromCenter(center: center, width: water.width * 1.1 * e, height: water.height * 1.1 * e),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * (1 - p) + 0.4
          ..color = Colors.white.withValues(alpha: 0.75 * (1 - p)),
      );
    }
    canvas.restore();

    // Inner lip: a dark shadow just inside the stone gives the water depth.
    canvas.drawOval(
      water,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawOval(
      water.inflate(1.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = Colors.white.withValues(alpha: 0.14),
    );

    // Bloom of light rising off the surface as the wish lands.
    if (bloom > 0) {
      final r = w * 0.55;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            MW.goldBright.withValues(alpha: 0.5 * bloom),
            Colors.transparent,
          ]).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(WellPainter old) =>
      old.glow != glow || old.ripple != ripple || old.bloom != bloom || old.phase != phase;
}

/// Concentric circular ripples, used behind finished states.
class RingsPainter extends CustomPainter {
  final double progress;
  final Color color;
  RingsPainter(this.progress, {this.color = MW.goldBright});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    for (var i = 0; i < 4; i++) {
      final p = ((progress - i * 0.14) / (1 - i * 0.14)).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      canvas.drawCircle(
        c,
        maxR * Curves.easeOutCubic.transform(p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 * (1 - p) + 0.3
          ..color = color.withValues(alpha: 0.55 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(RingsPainter old) => old.progress != progress;
}
