import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'glyphs.dart';

/// A breathing orb of light with a few motes drifting around it. Moonlight by
/// default; gold once the day's golden orb has been earned.
class GlowOrb extends StatefulWidget {
  final double size;
  final bool golden;
  const GlowOrb({super.key, this.size = 120, this.golden = false});

  @override
  State<GlowOrb> createState() => _GlowOrbState();
}

class _GlowOrbState extends State<GlowOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));
  bool _frozen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _frozen = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_frozen) {
      _c.value = 0.25;
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
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(painter: OrbPainter(_c, widget.golden)),
      );
}

class OrbPainter extends CustomPainter {
  final Animation<double> t;
  final bool golden;
  OrbPainter(this.t, this.golden) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final breathe = 0.5 + 0.5 * math.sin(t.value * math.pi * 2);
    final tone = golden ? MW.gold : MW.violet;

    // Outer halo, deliberately larger than the widget.
    final haloR = r * (2.1 + 0.25 * breathe);
    canvas.drawCircle(
      c,
      haloR,
      Paint()
        ..shader = RadialGradient(colors: [
          tone.withValues(alpha: 0.42 + 0.14 * breathe),
          tone.withValues(alpha: 0.12),
          Colors.transparent,
        ], stops: const [0.18, 0.5, 1]).createShader(Rect.fromCircle(center: c, radius: haloR)),
    );

    // Faint orbit ring.
    canvas.drawCircle(
      c,
      r * 1.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = tone.withValues(alpha: 0.18),
    );

    // Core.
    final coreR = r * (0.96 + 0.04 * breathe);
    final colors = golden
        ? const [Colors.white, MW.goldBright, MW.gold, MW.goldDeep]
        : const [Colors.white, Color(0xFFEDE8FF), Color(0xFFB9ACFF), Color(0xFF6D5DE0)];
    canvas.drawCircle(
      c,
      coreR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.28, -0.34),
          radius: 1.05,
          colors: colors,
          stops: const [0, 0.3, 0.68, 1],
        ).createShader(Rect.fromCircle(center: c, radius: coreR)),
    );

    // Specular glint.
    canvas.drawCircle(
      c + Offset(-coreR * 0.3, -coreR * 0.36),
      coreR * 0.16,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, coreR * 0.09),
    );

    // Drifting motes.
    for (var i = 0; i < 3; i++) {
      final dir = i.isEven ? 1 : -1;
      final a = t.value * math.pi * 2 * dir * (1 + i * 0.5) + i * 2.1;
      final rad = r * (1.5 + 0.1 * i);
      final p = c + Offset(math.cos(a), math.sin(a) * 0.82) * rad;
      canvas.drawPath(
        starPath(p, r * (0.09 + 0.02 * i), pinch: 0.1),
        Paint()..color = (golden ? MW.goldBright : Colors.white).withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(OrbPainter old) => old.golden != golden;
}

/// One-shot rise of four-point stars. Replay by changing [trigger].
class StarBurst extends StatefulWidget {
  final int trigger;
  const StarBurst({super.key, required this.trigger});

  @override
  State<StarBurst> createState() => _StarBurstState();
}

class _StarBurstState extends State<StarBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didUpdateWidget(StarBurst old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(size: Size.zero, painter: _BurstPainter(_c)),
      );
}

class _BurstPainter extends CustomPainter {
  final Animation<double> t;
  _BurstPainter(this.t) : super(repaint: t);

  static final _rng = math.Random(5);
  static final _parts = List.generate(14, (i) {
    // Mostly upward fan, with a few wide ones for depth.
    final a = -math.pi / 2 + (i / 13 - 0.5) * (i.isEven ? 2.1 : 3.0) + (_rng.nextDouble() - 0.5) * 0.3;
    return (
      angle: a,
      speed: 60.0 + _rng.nextDouble() * 70,
      size: 2.6 + _rng.nextDouble() * 4.2,
      color: i % 3 == 0 ? Colors.white : (i % 3 == 1 ? MW.goldBright : MW.gold),
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    if (v == 0 || v == 1) return;
    final secs = v * 1.2;
    for (final p in _parts) {
      final pos = Offset(math.cos(p.angle) * p.speed * secs,
          math.sin(p.angle) * p.speed * secs + 70 * secs * secs);
      final alpha = (1 - math.pow(v, 1.6)).toDouble();
      canvas.drawPath(
        starPath(pos, p.size * (1 - 0.5 * v), pinch: 0.12),
        Paint()
          ..color = p.color.withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => false;
}
