import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manifestwell/screens/paywall_screen.dart';
import 'package:manifestwell/state/app_state.dart';
import 'package:manifestwell/state/subscriptions.dart';
import 'package:manifestwell/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'test_fonts.dart';

/// Opens the paywall from a launcher page, so "the screen closed" can be
/// asserted by the launcher coming back.
Future<AppState> _open(WidgetTester t, {Subscriptions? subs, bool alreadyPlus = false}) async {
  t.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
  SharedPreferences.setMockInitialValues({'plusCached': alreadyPlus});
  final state = await AppState.load(subscriptions: subs ?? FakeSubscriptions());
  await t.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(
      theme: MW.theme(),
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => PaywallScreen.show(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('Open'));
  await _settle(t);
  return state;
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('shows every plan the store offers, with its own price', (t) async {
    await _open(t);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Yearly'), findsOneWidget);
    expect(find.text(r'$1.99'), findsOneWidget);
    expect(find.text(r'$4.99'), findsOneWidget);
    expect(find.text(r'$39.99'), findsOneWidget);
    expect(find.text('3 days free'), findsOneWidget);
  });

  testWidgets('monthly is selected first and the button says Continue', (t) async {
    await _open(t);
    expect(find.text('CONTINUE'), findsOneWidget);
    expect(find.text(r'$4.99 per month. Cancel any time.'), findsOneWidget);
  });

  testWidgets('choosing a plan with a trial says so before they pay', (t) async {
    await _open(t);
    await t.tap(find.byKey(const ValueKey(r'plan-$rc_annual')));
    await _settle(t);
    expect(find.text('START FREE TRIAL'), findsOneWidget);
    expect(find.text(r'3 days free, then $39.99 per year. Cancel any time.'), findsOneWidget);
  });

  testWidgets('the required renewal and cancellation terms are on screen', (t) async {
    await _open(t);
    expect(find.textContaining('Payment is charged to your Google Play account'), findsOneWidget);
    expect(find.textContaining('renews automatically'), findsOneWidget);
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
  });

  testWidgets('a successful purchase unlocks Plus, closes the paywall and welcomes them', (t) async {
    final subs = FakeSubscriptions();
    final state = await _open(t, subs: subs);
    await t.tap(find.byKey(const ValueKey('buy-button')));
    await _settle(t);
    expect(subs.bought, [monthly.id]);
    expect(state.isPro, isTrue);
    expect(find.text('Open'), findsOneWidget); // back on the launcher
    expect(find.textContaining('Welcome to Plus'), findsOneWidget);
  });

  testWidgets('the plan they picked is the plan they buy', (t) async {
    final subs = FakeSubscriptions();
    await _open(t, subs: subs);
    await t.tap(find.byKey(const ValueKey(r'plan-$rc_weekly')));
    await _settle(t);
    await t.tap(find.byKey(const ValueKey('buy-button')));
    await _settle(t);
    expect(subs.bought, [weekly.id]);
  });

  testWidgets('closing the store sheet leaves them on the paywall, quietly', (t) async {
    final subs = FakeSubscriptions()..nextBuy = const BuyResult(PurchaseOutcome.cancelled);
    final state = await _open(t, subs: subs);
    await t.tap(find.byKey(const ValueKey('buy-button')));
    await _settle(t);
    expect(state.isPro, isFalse);
    expect(find.text('CONTINUE'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a pending purchase explains that Plus will unlock when it clears', (t) async {
    final subs = FakeSubscriptions()..nextBuy = const BuyResult(PurchaseOutcome.pending);
    final state = await _open(t, subs: subs);
    await t.tap(find.byKey(const ValueKey('buy-button')));
    await _settle(t);
    expect(state.isPro, isFalse);
    expect(find.textContaining('waiting for approval'), findsOneWidget);
  });

  testWidgets('a failed purchase shows the reason and keeps the paywall open', (t) async {
    final subs = FakeSubscriptions()
      ..nextBuy = const BuyResult(PurchaseOutcome.failed, 'Could not reach the store.');
    final state = await _open(t, subs: subs);
    await t.tap(find.byKey(const ValueKey('buy-button')));
    await _settle(t);
    expect(state.isPro, isFalse);
    expect(find.text('Could not reach the store.'), findsOneWidget);
    expect(find.text('CONTINUE'), findsOneWidget);
  });

  testWidgets('with no store configured it says so instead of selling anything', (t) async {
    await _open(t, subs: const NoSubscriptions());
    expect(find.text('Subscriptions are not available in this version yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('buy-button')), findsNothing);
  });

  testWidgets('when the store cannot be reached it offers to try again', (t) async {
    final subs = FakeSubscriptions(catalogue: const []);
    await _open(t, subs: subs);
    expect(find.textContaining('could not load the plans'), findsOneWidget);
    subs.catalogue = const [monthly];
    await t.tap(find.text('TRY AGAIN'));
    await _settle(t);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.byKey(const ValueKey('buy-button')), findsOneWidget);
  });

  testWidgets('restoring finds an existing subscription and closes', (t) async {
    final subs = FakeSubscriptions()..restoreResult = true;
    final state = await _open(t, subs: subs);
    await t.tap(find.text('Restore purchases'));
    await _settle(t);
    expect(state.isPro, isTrue);
    expect(find.text('Open'), findsOneWidget);
    expect(find.textContaining('Plus restored'), findsOneWidget);
  });

  testWidgets('restoring with nothing to restore says so', (t) async {
    final state = await _open(t);
    await t.tap(find.text('Restore purchases'));
    await _settle(t);
    expect(state.isPro, isFalse);
    expect(find.textContaining('could not find an active Plus'), findsOneWidget);
  });

  testWidgets('restoring while offline explains the problem', (t) async {
    final subs = FakeSubscriptions()..restoreThrows = true;
    await _open(t, subs: subs);
    await t.tap(find.text('Restore purchases'));
    await _settle(t);
    expect(find.textContaining('Could not reach the store'), findsOneWidget);
  });

  // Opt-in render for design review: SHOTS=1 flutter test test/paywall_test.dart --update-goldens
  testWidgets('renders (opt-in)', skip: !Platform.environment.containsKey('SHOTS'), (t) async {
    debugDisableShadows = false;
    try {
      await _open(t);
      await t.binding.setSurfaceSize(const Size(430, 932));
      await t.runAsync(() async {
        await precacheImage(const AssetImage('assets/images/galaxy.jpg'), t.element(find.byType(MaterialApp)));
      });
      await _settle(t);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/19_paywall_plans.png'));
    } finally {
      debugDisableShadows = true;
    }
  });

  testWidgets('someone already on Plus sees that, not a sales page', (t) async {
    final subs = FakeSubscriptions()..plus = true;
    await _open(t, subs: subs, alreadyPlus: true);
    expect(find.text('You are on Plus.'), findsOneWidget);
    expect(find.text('MANAGE SUBSCRIPTION'), findsOneWidget);
    expect(find.byKey(const ValueKey('buy-button')), findsNothing);
  });
}
