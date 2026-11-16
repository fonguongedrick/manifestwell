import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/responsive_helper.dart';
import 'glyphs.dart';

/// Which nebula sits behind a screen.
enum SkyImage {
  /// Portrait blue-violet nebula: the everyday sky.
  nebula('assets/images/nebula.jpg', Alignment.center),

  /// Violet spiral galaxy: onboarding and quiet moments.
  spiral('assets/images/spiral.jpg', Alignment(0.05, 0)),

  /// Pink-violet galaxy: the paywall and celebrations.
  galaxy('assets/images/galaxy.jpg', Alignment(0.2, -0.2));

  final String asset;
  final Alignment focus;
  const SkyImage(this.asset, this.focus);
}

/// The night sky behind every screen: a real nebula photograph tinted down so
/// glass and text stay legible, a few twinkling stars, and optionally the moon
/// and constellation from the brand sample. Honors "reduce motion".
class Backdrop extends StatelessWidget {
  final Widget child;
  final SkyImage image;
  final bool moon;

  /// 0 shows the photograph as-is, 1 is the darkest tint.
  final double tint;

  const Backdrop({
    super.key,
    required this.child,
    this.image = SkyImage.nebula,
    this.moon = false,
    this.tint = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      Image.asset(image.asset, fit: BoxFit.cover, alignment: image.focus, gaplessPlayback: true),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              MW.indigo.withValues(alpha: 0.30 * tint),
              MW.ink.withValues(alpha: 0.58 * tint),
              MW.inkDeep.withValues(alpha: 0.86 * tint),
            ],
            stops: const [0, 0.5, 1],
          ),
        ),
      ),
      if (moon) const Positioned(top: 0, right: 0, child: IgnorePointer(child: _MoonAndConstellation())),
      const RepaintBoundary(child: Starfield()),
      Center(
        child: ConstrainedBox(
          // Phones fill the screen; tablets get a comfortable reading column.
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.isMobile(context) ? double.infinity : 560,
          ),
          child: child,
        ),
      ),
    ]);
  }
}

class _MoonAndConstellation extends StatelessWidget {
  const _MoonAndConstellation();

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          width: 260,
          height: 330,
          child: CustomPaint(painter: _SkyPainter()),
        ),
      );
}

class _SkyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Moon, top right.
    final c = Offset(size.width - 52, 56);
    const r = 40.0;
    canvas.drawCircle(
      c,
      r * 2.6,
      Paint()
        ..shader = RadialGradient(colors: [
          MW.lilac.withValues(alpha: 0.5),
          MW.violet.withValues(alpha: 0.12),
          Colors.transparent,
        ], stops: const [0.25, 0.6, 1]).createShader(Rect.fromCircle(center: c, radius: r * 2.6)),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 1.1,
          colors: [Color(0xFFF6F2FF), Color(0xFFC4C0F2), Color(0xFF857FCB)],
          stops: [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // A few soft craters.
    for (final (dx, dy, cr) in const [(-12.0, -8.0, 7.0), (10.0, 6.0, 9.0), (-4.0, 17.0, 5.0), (14.0, -14.0, 4.0)]) {
      canvas.drawCircle(c + Offset(dx, dy), cr, Paint()..color = const Color(0xFF6F69B8).withValues(alpha: 0.18));
    }

    // Constellation below the moon.
    final pts = [
      Offset(size.width * 0.18, 172),
      Offset(size.width * 0.38, 146),
      Offset(size.width * 0.52, 186),
      Offset(size.width * 0.7, 168),
      Offset(size.width * 0.78, 218),
      Offset(size.width * 0.9, 250),
    ];
    final line = Paint()
      ..strokeWidth = 0.9
      ..color = Colors.white.withValues(alpha: 0.35);
    for (var i = 0; i < pts.length - 1; i++) {
      canvas.drawLine(pts[i], pts[i + 1], line);
    }
    for (var i = 0; i < pts.length; i++) {
      final big = i == 1 || i == 4;
      if (big) {
        canvas.drawPath(starPath(pts[i], 7, pinch: 0.12), Paint()..color = Colors.white.withValues(alpha: 0.95));
      } else {
        canvas.drawCircle(pts[i], 2.2, Paint()..color = Colors.white.withValues(alpha: 0.85));
      }
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => false;
}

class Starfield extends StatefulWidget {
  const Starfield({super.key});

  @override
  State<Starfield> createState() => _StarfieldState();
}

class _StarfieldState extends State<Starfield> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 60));
  static final _stars = _makeStars();

  /// Only a handful of sparkles: the nebula photograph already carries the
  /// dense field, so this layer just adds life.
  static List<_Star> _makeStars() {
    final r = math.Random(21);
    return List.generate(14, (i) => _Star(
          x: 0.06 + r.nextDouble() * 0.88,
          y: 0.04 + r.nextDouble() * 0.92,
          radius: 2.2 + r.nextDouble() * 2.0,
          phase: r.nextDouble() * math.pi * 2,
          cycles: 3 + r.nextInt(6),
        ));
  }

  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduced) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(size: Size.infinite, painter: _StarPainter(_c, _stars, _reduced)),
      );
}

class _Star {
  final double x, y, radius, phase;
  final int cycles;
  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.cycles,
  });
}

class _StarPainter extends CustomPainter {
  final Animation<double> t;
  final List<_Star> stars;
  final bool frozen;
  _StarPainter(this.t, this.stars, this.frozen) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in stars) {
      final tw = frozen ? 0.8 : 0.5 + 0.5 * math.sin(t.value * math.pi * 2 * s.cycles + s.phase);
      final a = 0.25 + 0.65 * tw;
      final c = Offset(s.x * size.width, s.y * size.height);
      canvas.drawCircle(
        c,
        s.radius * 3.4,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withValues(alpha: 0.28 * a),
            Colors.transparent,
          ]).createShader(Rect.fromCircle(center: c, radius: s.radius * 3.4)),
      );
      canvas.drawPath(
        starPath(c, s.radius * 1.5, pinch: 0.1),
        Paint()..color = Colors.white.withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.frozen != frozen;
}
