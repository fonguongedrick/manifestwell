import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manifestwell/main.dart';
import 'package:manifestwell/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fonts.dart';

Future<void> _boot(WidgetTester t, {bool onboarded = false}) async {
  // Freeze ambient motion (starfield, orb) so the tree can settle.
  t.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);

  SharedPreferences.setMockInitialValues({'onboarded': onboarded});
  final state = await AppState.load();
  await t.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ManifestWellApp(state: state));
  await t.pumpAndSettle();
}

Future<void> _tapCast(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('tab-cast')));
  await t.pumpAndSettle();
}

Future<void> _castBigWish(WidgetTester t, String text) async {
  await t.enterText(find.byType(TextField), text);
  await t.pump();
  await t.tap(find.text('TURN IT INTO LIGHT'));
  await t.pumpAndSettle();
}

Future<void> _release(WidgetTester t) async {
  await t.tap(find.text('or tap to release'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('onboarding walks from welcome through first wish to the Well', (t) async {
    await _boot(t);
    expect(find.textContaining('works out for you.'), findsOneWidget);

    await t.tap(find.text('BEGIN YOUR RITUAL'));
    await t.pumpAndSettle();
    await t.tap(find.text('NEXT'));
    await t.pumpAndSettle();
    await t.tap(find.text('NEXT'));
    await t.pumpAndSettle();
    await t.tap(find.text('CONTINUE'));
    await t.pumpAndSettle();
    expect(find.textContaining('energy space.'), findsOneWidget);

    await t.tap(find.text('CONTINUE AS GUEST'));
    await t.pumpAndSettle();
    expect(find.text('YOUR FIRST WISH'), findsOneWidget);

    await _castBigWish(t, 'My dream apartment comes through');
    expect(find.text('or tap to release'), findsOneWidget);
    await _release(t);
    expect(find.text('Released.'), findsOneWidget);

    await t.tap(find.text('CONTINUE'));
    await t.pumpAndSettle();
    expect(find.textContaining('daily spark.'), findsOneWidget);

    await t.tap(find.text('Maybe later'));
    await t.pumpAndSettle();
    // Landed in the Well, and the wish just cast is in the feed.
    expect(find.text('RECENT WISHES'), findsOneWidget);
    expect(find.textContaining('My dream apartment comes through'), findsOneWidget);
  });

  testWidgets('inappropriate wish is blocked before the orb stage', (t) async {
    await _boot(t, onboarded: true);
    await _tapCast(t);
    await _castBigWish(t, 'this is shit');
    expect(find.textContaining('keep the Well positive'), findsOneWidget);
    expect(find.text('or tap to release'), findsNothing);
  });

  testWidgets('cast button stays disabled until something is written', (t) async {
    await _boot(t, onboarded: true);
    await _tapCast(t);
    await t.tap(find.text('TURN IT INTO LIGHT'));
    await t.pumpAndSettle();
    expect(find.text('or tap to release'), findsNothing);
  });

  testWidgets('sending luck updates the entry once', (t) async {
    await _boot(t, onboarded: true);
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, -500));
    await t.pumpAndSettle();
    await t.tap(find.text('SEND LUCK').first);
    await t.pumpAndSettle();
    expect(find.text('SENT'), findsOneWidget);
  });

  testWidgets('second big wish opens the paywall', (t) async {
    await _boot(t, onboarded: true);
    await _tapCast(t);
    await _castBigWish(t, 'first wish');
    await _release(t);
    await t.tap(find.text('BACK TO THE WELL'));
    await t.pumpAndSettle();

    await _tapCast(t);
    await _castBigWish(t, 'second wish');
    expect(find.textContaining('Hold every dream'), findsOneWidget);
    // These tests run with no store configured, so the paywall must say that
    // plainly rather than offer something that cannot be bought.
    expect(find.text('Subscriptions are not available in this version yet.'), findsOneWidget);
    expect(find.text('CONTINUE'), findsNothing);
  });

  testWidgets('daily spark goes straight to the Proof Vault', (t) async {
    await _boot(t, onboarded: true);
    await _tapCast(t);
    await t.tap(find.text('Daily spark'));
    await t.pumpAndSettle();
    await t.tap(find.text('Treat'));
    await t.pumpAndSettle();
    await _castBigWish(t, 'Free coffee today');
    await _release(t);
    await t.tap(find.text('BACK TO THE WELL'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('tab-vault')));
    await t.pumpAndSettle();
    expect(find.text('thing has worked out for you.'), findsOneWidget);
    expect(find.text('Free coffee today'), findsOneWidget);
    expect(find.textContaining('[Treat]'), findsOneWidget);
  });

  testWidgets('granting a wish moves it into the Proof Vault', (t) async {
    await _boot(t, onboarded: true);
    await _tapCast(t);
    await _castBigWish(t, 'sign the lease');
    await _release(t);
    await t.tap(find.text('BACK TO THE WELL'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('tab-vault')));
    await t.pumpAndSettle();
    expect(find.text('Your proof starts '), findsNothing);
    await t.tap(find.text('sign the lease'));
    await t.pumpAndSettle();
    await t.tap(find.text('It happened'));
    await t.pumpAndSettle();
    await t.tap(find.text('SAVE'));
    await t.pumpAndSettle();

    expect(find.text('thing has worked out for you.'), findsOneWidget);
    expect(find.text('sign the lease'), findsOneWidget);
  });
}
