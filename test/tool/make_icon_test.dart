// Renders the app icon masters into assets/icon/. Run:
//   ICON=1 flutter test test/tool/make_icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manifestwell/theme.dart';
import 'package:manifestwell/widgets/glyphs.dart';

class _IconPainter extends CustomPainter {
  final bool background;
  final double scale;
  _IconPainter({required this.background, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;
    if (background) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0, -0.35),
            radius: 1.1,
            colors: [Color(0xFF2C2670), Color(0xFF12103A), MW.ink],
            stops: [0, 0.55, 1],
          ).createShader(rect),
      );
    }
    final c = Offset(s / 2, s / 2);
    Offset at(double x, double y) => c + (Offset(x * s, y * s) - c) * scale;

    // Small stars around the hero.
    for (final (x, y, r) in const [
      (0.2, 0.24, 0.020),
      (0.79, 0.27, 0.013),
      (0.72, 0.8, 0.017),
      (0.25, 0.74, 0.011),
      (0.86, 0.55, 0.009),
    ]) {
      canvas.drawPath(
        starPath(at(x, y), s * r * scale, pinch: 0.12),
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }

    final r = s * 0.30 * scale;
    final hero = c + Offset(0, s * 0.01);
    canvas.drawCircle(
      hero,
      r * 2.3,
      Paint()
        ..shader = RadialGradient(colors: [
          MW.gold.withValues(alpha: 0.5),
          MW.gold.withValues(alpha: 0.12),
          Colors.transparent,
        ], stops: const [0, 0.45, 1]).createShader(Rect.fromCircle(center: hero, radius: r * 2.3)),
    );
    final star = starPath(hero, r, pinch: 0.085);
    canvas.drawPath(
      star,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF0C4), MW.gold, MW.goldDeep],
          stops: [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: hero, radius: r)),
    );
    canvas.drawPath(
      starPath(hero, r * 0.38, pinch: 0.2),
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );
  }

  @override
  bool shouldRepaint(_IconPainter old) => false;
}

void main() {
  final enabled = Platform.environment.containsKey('ICON');

  Future<void> render(WidgetTester t, String file, {required bool background, required double scale}) async {
    final key = GlobalKey();
    await t.binding.setSurfaceSize(const Size(1024, 1024));
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: key,
        child: CustomPaint(
          size: const Size(1024, 1024),
          painter: _IconPainter(background: background, scale: scale),
        ),
      ),
    ));
    await t.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('assets/icon/$file').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('render icon masters', skip: !enabled, (t) async {
    // Full-bleed (iOS and legacy Android) and a padded, transparent
    // foreground that sits inside Android's adaptive-icon safe zone.
    await render(t, 'icon.png', background: true, scale: 1);
    await render(t, 'icon_foreground.png', background: false, scale: 0.72);
  });
}
