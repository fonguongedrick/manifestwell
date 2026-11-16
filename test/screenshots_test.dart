// Renders each screen to test/shots/*.png with the real bundled fonts so the
// design can be reviewed without a device. Run:
//   SHOTS=1 flutter test test/screenshots_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manifestwell/main.dart';
import 'package:manifestwell/models/wish.dart';
import 'package:manifestwell/screens/paywall_screen.dart';
import 'package:manifestwell/screens/settings_screen.dart';
import 'package:manifestwell/state/app_state.dart';
import 'package:manifestwell/theme.dart';
import 'package:manifestwell/widgets/backdrop.dart';
import 'package:manifestwell/widgets/glyphs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_fonts.dart';


Future<AppState> _boot(WidgetTester t, {bool onboarded = true, Widget? home}) async {
  t.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
  SharedPreferences.setMockInitialValues({'onboarded': onboarded});
  final state = await AppState.load();
  await t.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => t.binding.setSurfaceSize(null));
  if (home == null) {
    await t.pumpWidget(ManifestWellApp(state: state));
  } else {
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(theme: MW.theme(), debugShowCheckedModeBanner: false, home: home),
    ));
  }
  await t.runAsync(() async {
    final ctx = t.element(find.byType(MaterialApp));
    for (final a in ['nebula', 'spiral', 'galaxy']) {
      await precacheImage(AssetImage('assets/images/$a.jpg'), ctx);
    }
  });
  await t.pumpAndSettle();
  return state;
}

Future<void> _shot(WidgetTester t, String name) async {
  await t.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
}

Future<void> _seedProof(AppState s) async {
  final a = await s.cast('Signed the lease on my townhouse', WishKind.big, WishCategory.home);
  await s.resolve(a!.id, WishStatus.granted, note: 'The landlord called the same afternoon.');
  await s.cast('Found twenty dollars in my winter coat', WishKind.spark, WishCategory.daily, tag: 'Windfall');
  await s.cast('Free iced coffee, the barista was kind', WishKind.spark, WishCategory.daily, tag: 'Treat');
  await s.cast('Launching my new app', WishKind.big, WishCategory.career);
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
  });

  shotTest('shots: onboarding', (t) async {
    await _boot(t, onboarded: false);
    await _shot(t, '01_welcome');
    await t.tap(find.text('BEGIN YOUR RITUAL'));
    await t.pumpAndSettle();
    await _shot(t, '02_concept');
    await t.tap(find.text('NEXT'));
    await t.pumpAndSettle();
    await t.tap(find.text('NEXT'));
    await t.pumpAndSettle();
    await t.tap(find.text('CONTINUE'));
    await t.pumpAndSettle();
    await _shot(t, '03_auth');
    await t.tap(find.text('CONTINUE AS GUEST'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'My dream apartment in Brooklyn comes through.');
    await t.pump();
    await _shot(t, '04_first_wish');
    await t.tap(find.text('TURN IT INTO LIGHT'));
    await t.pumpAndSettle();
    await _shot(t, '05_orb');
    final g = await t.startGesture(const Offset(215, 325));
    await g.moveBy(const Offset(0, 330));
    await t.pump();
    await _shot(t, '06_orb_dragging');
    await g.up();
    await t.pump(const Duration(milliseconds: 1500));
    await _shot(t, '07_orb_landing');
    await t.pumpAndSettle();
    await _shot(t, '08_released');
    await t.tap(find.text('CONTINUE'));
    await t.pumpAndSettle();
    await _shot(t, '09_reminder');
  });

  shotTest('shots: main app', (t) async {
    final s = await _boot(t);
    await _shot(t, '10_well_empty');
    await _seedProof(s);
    await t.pumpAndSettle();
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, 0));
    await _shot(t, '11_well');
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, -520));
    await t.pumpAndSettle();
    await _shot(t, '12_well_scrolled');
    await t.tap(find.byKey(const ValueKey('tab-cast')));
    await t.pumpAndSettle();
    await _shot(t, '13_cast');
    await t.tap(find.text('Daily spark'));
    await t.pumpAndSettle();
    await t.tap(find.text('Windfall'));
    await t.pumpAndSettle();
    await _shot(t, '14_cast_spark');
    await t.tap(find.byKey(const ValueKey('tab-vault')));
    await t.pumpAndSettle();
    await _shot(t, '15_vault');
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, -420));
    await t.pumpAndSettle();
    await _shot(t, '16_vault_scrolled');
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, 900));
    await t.pumpAndSettle();
    await t.tap(find.text('Launching my new app'));
    await t.pumpAndSettle();
    await t.tap(find.text('A different door opened'));
    await t.pumpAndSettle();
    await _shot(t, '17_revisit');
  });

  shotTest('shots: secondary screens', (t) async {
    await _boot(t, home: const Scaffold(body: Backdrop(moon: true, child: SettingsScreen())));
    await _shot(t, '18_settings');
    await _boot(t, home: const PaywallScreen());
    await _shot(t, '19_paywall');
    await _boot(t, home: const _GlyphSheet());
    await _shot(t, '20_glyphs');
  });
}

class _GlyphSheet extends StatelessWidget {
  const _GlyphSheet();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(spacing: 22, runSpacing: 22, children: [
            for (final k in GlyphKind.values) ...[
              Glyph(k, size: 44, color: MW.goldBright, stroke: 1.5),
              Glyph(k, size: 44, color: MW.goldBright, filled: true),
            ],
          ]),
        ),
      );
}

/// flutter_test flattens blurred shadows by default; restore them for review,
/// and put the flag back before the framework's invariant check.
void shotTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, skip: !Platform.environment.containsKey('SHOTS'), (t) async {
      debugDisableShadows = false;
      try {
        await body(t);
      } finally {
        debugDisableShadows = true;
      }
    });
