// Renders the App Store and Google Play listing images from the real app, so
// they can never drift from what the app looks like. Opt-in:
//
//   STORE=1 flutter test test/store_shots_test.dart --update-goldens
//
// Output goes to store/<folder>/, then run store/finish.ps1 to strip the alpha
// channel (both stores reject screenshots with transparency).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:manifestwell/main.dart';
import 'package:manifestwell/models/wish.dart';
import 'package:manifestwell/state/app_state.dart';
import 'package:manifestwell/theme.dart';
import 'package:manifestwell/widgets/effects.dart';
import 'package:manifestwell/widgets/sheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fonts.dart';

/// The app is laid out at this logical size (a modern iPhone), then scaled
/// into the frame, so text and shapes stay vector-sharp at any output size.
const _inner = Size(430, 932);

class _Target {
  final String folder;
  final int w;
  final int h;

  /// Phone height as a share of the canvas height.
  final double phoneShare;
  const _Target(this.folder, this.w, this.h, this.phoneShare);
}

const _targets = [
  // App Store: iPhone 6.3" and 6.1" portrait.
  _Target('appstore_6.3in_1206x2622', 1206, 2622, 0.745),
  _Target('appstore_6.1in_1179x2556', 1179, 2556, 0.745),
  // Google Play phone: 9:16 (the stores allow at most 2:1).
  _Target('play_phone_1080x1920', 1080, 1920, 0.70),
];

class _Ctx {
  final WidgetTester t;
  final AppState state;
  final GlobalKey inner;
  final double scale;
  TestGesture? gesture;
  _Ctx(this.t, this.state, this.inner, this.scale);

  Future<void> tap(Finder f) async {
    await t.tap(f);
    await t.pumpAndSettle();
  }
}

class _Shot {
  final String file;
  final String title;
  final String subtitle;
  final Future<void> Function(_Ctx) run;

  /// Start with a lived-in Vault (a few granted wishes and one still glowing).
  final bool proof;
  const _Shot(this.file, this.title, this.subtitle, this.run, {this.proof = false});
}

/// A believable, anonymous demo Vault: made-up wishes with the luck they
/// would realistically have earned. Never any real person's data.
String _demoVault() {
  final now = DateTime.now();
  DateTime ago(int days) => now.subtract(Duration(days: days));
  final wishes = [
    Wish(
      id: 'demo_lease',
      text: 'Signed the lease on my townhouse',
      kind: WishKind.big,
      category: WishCategory.home,
      createdAt: ago(21),
      luck: 214,
      status: WishStatus.granted,
      note: 'The landlord called the same afternoon.',
      resolvedAt: ago(3),
      updatedAt: ago(3),
      isMine: true,
    ),
    Wish(
      id: 'demo_coat',
      text: 'Found twenty dollars in my winter coat',
      kind: WishKind.spark,
      category: WishCategory.daily,
      createdAt: ago(1),
      luck: 87,
      status: WishStatus.granted,
      tag: 'Windfall',
      resolvedAt: ago(1),
      updatedAt: ago(1),
      isMine: true,
    ),
    Wish(
      id: 'demo_coffee',
      text: 'Free iced coffee, the barista was kind',
      kind: WishKind.spark,
      category: WishCategory.daily,
      createdAt: ago(2),
      luck: 132,
      status: WishStatus.granted,
      tag: 'Treat',
      resolvedAt: ago(2),
      updatedAt: ago(2),
      isMine: true,
    ),
    Wish(
      id: 'demo_app',
      text: 'Launching my new app',
      kind: WishKind.big,
      category: WishCategory.career,
      createdAt: ago(10),
      luck: 56,
      updatedAt: ago(10),
      isMine: true,
    ),
  ];
  return jsonEncode([for (final w in wishes) w.toJson()]);
}

final _shots = <_Shot>[
  _Shot(
    '01_well',
    "Your wish joins\nthe world's well",
    'Anonymous, kind, and glowing with luck.',
    (c) async {
      // No demo wish of our own here: the Well should open on other people's
      // wishes, already glowing with luck.
      await c.t.pumpAndSettle();
    },
  ),
  _Shot(
    '02_cast',
    'Cast it.\nFeel it.',
    'Drag your wish into the water and let it go.',
    (c) async {
      await c.tap(find.byKey(const ValueKey('tab-cast')));
      // Short enough to sit clear of the moon in the corner.
      await c.t.enterText(find.byType(TextField), 'A calm new home.');
      await c.t.pump();
      await c.tap(find.text('TURN IT INTO LIGHT'));
      // Hold the orb mid-drag, on its way to the water.
      final orb = find.byType(GlowOrb).first;
      c.gesture = await c.t.startGesture(c.t.getCenter(orb));
      await c.gesture!.moveBy(Offset(0, 330 * c.scale));
      await c.t.pump();
    },
  ),
  _Shot(
    '03_vault',
    'Keep the proof\nit works',
    'Every win, big or small, in one starry vault.',
    (c) async {
      await c.tap(find.byKey(const ValueKey('tab-vault')));
    },
    proof: true,
  ),
  _Shot(
    '04_revisit',
    'Revisit with\nhonesty',
    'Granted, closer, changed or let go. All of it counts.',
    (c) async {
      await c.tap(find.byKey(const ValueKey('tab-vault')));
      await c.tap(find.text('Launching my new app'));
    },
    proof: true,
  ),
  _Shot(
    '05_spark',
    'Catch the\nlittle wins',
    'Log a daily spark and watch your luck add up.',
    (c) async {
      await c.tap(find.byKey(const ValueKey('tab-cast')));
      await c.tap(find.text('Daily spark'));
      await c.tap(find.text('Windfall'));
      await c.t.enterText(find.byType(TextField), 'Found twenty dollars in my winter coat');
      await c.t.pump();
    },
  ),
  _Shot(
    '06_notifications',
    'Know when\nluck arrives',
    'Gentle alerts about your own wishes, never who sent them.',
    (c) async {
      await c.t.pumpAndSettle();
      final context = c.t.element(find.byType(Scaffold).first);
      showPushOfferSheet(context);
      await c.t.pumpAndSettle();
    },
  ),
];

Future<void> _render(WidgetTester t, _Target target, _Shot shot) async {
  t.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
  SharedPreferences.setMockInitialValues({
    'onboarded': true,
    if (shot.proof) 'mine': _demoVault(),
  });
  final state = await AppState.load();
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(target.w.toDouble(), target.h.toDouble());
  addTearDown(t.view.reset);

  final canvasKey = GlobalKey();
  final innerKey = GlobalKey();
  final geometry = _Geometry(target);
  await t.pumpWidget(_StoreFrame(
    canvasKey: canvasKey,
    innerKey: innerKey,
    geometry: geometry,
    title: shot.title,
    subtitle: shot.subtitle,
    app: ManifestWellApp(state: state),
  ));
  await t.runAsync(() async {
    final ctx = t.element(find.byKey(innerKey));
    for (final a in ['nebula', 'spiral', 'galaxy']) {
      await precacheImage(AssetImage('assets/images/$a.jpg'), ctx);
    }
  });
  await t.pumpAndSettle();

  final ctx = _Ctx(t, state, innerKey, geometry.scale);
  await shot.run(ctx);
  await t.pumpAndSettle();
  await expectLater(
    find.byKey(canvasKey),
    matchesGoldenFile('../store/${target.folder}/${shot.file}.png'),
  );
  await ctx.gesture?.up();
}

class _Geometry {
  final double w;
  final double h;
  final double scale;
  final double phoneW;
  final double phoneH;
  final double bezel;
  final double top;
  _Geometry(_Target t)
      : w = t.w.toDouble(),
        h = t.h.toDouble(),
        phoneH = t.h * t.phoneShare,
        scale = (t.h * t.phoneShare) / _inner.height,
        phoneW = _inner.width * (t.h * t.phoneShare) / _inner.height,
        bezel = t.w * 0.011,
        top = t.h - t.h * 0.035 - (t.h * t.phoneShare + 2 * t.w * 0.011);
}

class _StoreFrame extends StatelessWidget {
  final GlobalKey canvasKey;
  final GlobalKey innerKey;
  final _Geometry geometry;
  final String title;
  final String subtitle;
  final Widget app;
  const _StoreFrame({
    required this.canvasKey,
    required this.innerKey,
    required this.geometry,
    required this.title,
    required this.subtitle,
    required this.app,
  });

  @override
  Widget build(BuildContext context) {
    final g = geometry;
    final radius = 55 * g.scale;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: canvasKey,
          child: SizedBox(
            width: g.w,
            height: g.h,
            child: Stack(children: [
              Positioned.fill(child: Image.asset('assets/images/nebula.jpg', fit: BoxFit.cover)),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        MW.inkDeep.withValues(alpha: 0.72),
                        MW.inkDeep.withValues(alpha: 0.28),
                        MW.inkDeep.withValues(alpha: 0.5),
                      ],
                      stops: const [0, 0.5, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: g.w * 0.06,
                right: g.w * 0.06,
                top: g.h * 0.05,
                height: g.top - g.h * 0.05,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: MW.display(g.w * 0.0625).copyWith(height: 1.12, shadows: MW.titleGlow),
                  ),
                  SizedBox(height: g.h * 0.014),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: MW.ui(g.w * 0.03, color: MW.textDim, weight: 600, height: 1.35),
                  ),
                ]),
              ),
              Positioned(
                left: (g.w - g.phoneW - 2 * g.bezel) / 2,
                top: g.top,
                child: Container(
                  width: g.phoneW + 2 * g.bezel,
                  height: g.phoneH + 2 * g.bezel,
                  padding: EdgeInsets.all(g.bezel),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0A18),
                    borderRadius: BorderRadius.circular(radius + g.bezel),
                    border: Border.all(color: const Color(0xFF34305E), width: g.bezel * 0.16),
                    boxShadow: [
                      BoxShadow(color: MW.violet.withValues(alpha: 0.42), blurRadius: g.w * 0.1),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: g.w * 0.05,
                        offset: Offset(0, g.w * 0.02),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: SizedBox(
                      width: g.phoneW,
                      height: g.phoneH,
                      child: FittedBox(
                        fit: BoxFit.fill,
                        child: SizedBox(
                          key: innerKey,
                          width: _inner.width,
                          height: _inner.height,
                          child: Stack(children: [
                            Builder(
                              builder: (context) => MediaQuery(
                                data: MediaQuery.of(context).copyWith(
                                  size: _inner,
                                  devicePixelRatio: 3,
                                  padding: const EdgeInsets.only(top: 54, bottom: 34),
                                  viewPadding: const EdgeInsets.only(top: 54, bottom: 34),
                                  viewInsets: EdgeInsets.zero,
                                ),
                                child: app,
                              ),
                            ),
                            const Positioned(top: 0, left: 0, right: 0, height: 54, child: IgnorePointer(child: _StatusBar())),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A plain status bar (island, clock, signal, battery) so the screens read as
/// a real phone without borrowing anyone's artwork.
class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned(
          top: 11,
          left: (_inner.width - 126) / 2,
          child: Container(
            width: 126,
            height: 37,
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
          ),
        ),
        Positioned(left: 52, top: 16, child: Text('9:41', style: MW.ui(17, weight: 800))),
        Positioned(
          right: 44,
          top: 21,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 4; i++) ...[
              Container(
                width: 4,
                height: 5.0 + i * 3,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1)),
              ),
              const SizedBox(width: 2),
            ],
            const SizedBox(width: 8),
            Container(
              width: 27,
              height: 13,
              padding: const EdgeInsets.all(1.6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ]),
        ),
      ]);
}

void main() {
  final enabled = Platform.environment.containsKey('STORE');

  setUpAll(() async {
    await loadAppFonts();
    // Wishes in the Well contain emoji, which the app gets from the phone. The
    // test engine has no system fonts, so lend it Windows' colour emoji font
    // (used only to draw these images, never bundled in the app).
    final emoji = File(r'C:\Windows\Fonts\seguiemj.ttf');
    if (emoji.existsSync()) {
      final bytes = emoji.readAsBytesSync();
      final loader = FontLoader('Segoe UI Emoji')..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  });

  for (final target in _targets) {
    for (final shot in _shots) {
      testWidgets('${target.folder} ${shot.file}', skip: !enabled, (t) async {
        debugDisableShadows = false;
        try {
          await _render(t, target, shot);
        } finally {
          debugDisableShadows = true;
        }
      });
    }
  }

  // Google Play's feature graphic: 1024 x 500, shown at the top of the listing.
  testWidgets('play feature graphic 1024x500', skip: !enabled, (t) async {
    debugDisableShadows = false;
    try {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(1024, 500);
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 1024,
            height: 500,
            child: Stack(children: [
              Positioned.fill(child: Image.asset('assets/images/nebula.jpg', fit: BoxFit.cover)),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [MW.inkDeep.withValues(alpha: 0.78), MW.inkDeep.withValues(alpha: 0.18)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 64,
                top: 0,
                bottom: 0,
                width: 600,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // One line, always: scale down rather than wrap if it ever grows.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'ManifestWell',
                      softWrap: false,
                      style: MW.display(72).copyWith(shadows: MW.titleGlow),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Cast a wish. Send luck.\nKeep the proof.',
                    style: MW.ui(32, color: MW.textDim, weight: 600, height: 1.3),
                  ),
                ]),
              ),
              const Positioned(right: 96, top: 150, child: GlowOrb(size: 200, golden: true)),
            ]),
          ),
        ),
      ));
      await t.runAsync(() async {
        await precacheImage(const AssetImage('assets/images/nebula.jpg'), t.element(find.byKey(key)));
      });
      await t.pumpAndSettle();
      await expectLater(find.byKey(key), matchesGoldenFile('../store/play_feature_graphic_1024x500/feature_graphic.png'));
    } finally {
      debugDisableShadows = true;
    }
  });
}
