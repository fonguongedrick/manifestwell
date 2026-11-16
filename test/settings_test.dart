// Behaviour tests for the Settings tab, plus opt-in full-page renders:
//   SHOTS=1 flutter test test/settings_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manifestwell/models/wish.dart';
import 'package:manifestwell/screens/settings_screen.dart';
import 'package:manifestwell/state/app_state.dart';
import 'package:manifestwell/theme.dart';
import 'package:manifestwell/utils/app_info.dart';
import 'package:manifestwell/widgets/backdrop.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_well_backend.dart';
import 'test_fonts.dart';

const _tall = Size(430, 2900);

Future<AppState> _open(
  WidgetTester t, {
  FakeWellBackend? backend,
  bool precache = false,
}) async {
  t.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
  SharedPreferences.setMockInitialValues({'onboarded': true});
  PackageInfo.setMockInitialValues(
    appName: 'ManifestWell',
    packageName: 'com.tribesofkin.manifestwell',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  await AppInfo.init();
  final state = await AppState.load(backend: backend);
  await t.binding.setSurfaceSize(_tall);
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(
      theme: MW.theme(),
      debugShowCheckedModeBanner: false,
      home: const Scaffold(body: Backdrop(moon: true, child: SettingsScreen())),
    ),
  ));
  if (precache) {
    await t.runAsync(() async {
      await precacheImage(const AssetImage('assets/images/nebula.jpg'), t.element(find.byType(MaterialApp)));
    });
  }
  await t.pump(const Duration(milliseconds: 100));
  return state;
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUpAll(loadAppFonts);

  group('Settings', () {
    testWidgets('a guest can sign in, export and delete, but not sign out', (t) async {
      await _open(t, backend: FakeWellBackend());
      expect(find.text('Guest'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Export my data'), findsOneWidget);
      expect(find.text('Delete my data'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
    });

    testWidgets('a signed-in account shows its email, sign out and delete account', (t) async {
      await _open(t, backend: FakeWellBackend(account: 'ada@example.com'));
      expect(find.text('ada@example.com'), findsOneWidget);
      expect(find.text('A'), findsOneWidget); // avatar initial
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('offline with no backend offers no sign-in', (t) async {
      await _open(t);
      expect(find.text('Sign in'), findsNothing);
      expect(find.textContaining('Offline'), findsOneWidget);
    });

    testWidgets('the profile shows real counts', (t) async {
      final state = await _open(t, backend: FakeWellBackend());
      await state.cast('A calm new home', WishKind.big, WishCategory.home);
      await t.pump();
      expect(find.text('Wishes\ncast'.toUpperCase()), findsOneWidget);
      expect(state.wishesCast, 1);
    });

    testWidgets('the haptics switch changes the setting', (t) async {
      final state = await _open(t, backend: FakeWellBackend());
      expect(state.hapticsEnabled, isTrue);
      await t.tap(find.byKey(const ValueKey('switch-haptics')));
      await _settle(t);
      expect(state.hapticsEnabled, isFalse);
    });

    testWidgets('the reminder switch turns the reminder on', (t) async {
      final state = await _open(t, backend: FakeWellBackend());
      expect(state.remindersEnabled, isFalse);
      await t.tap(find.byKey(const ValueKey('switch-reminder')));
      await _settle(t);
      expect(state.remindersEnabled, isTrue);
    });

    testWidgets('the reminder time cannot be edited while the reminder is off', (t) async {
      await _open(t, backend: FakeWellBackend());
      await t.tap(find.text('Reminder time'), warnIfMissed: false);
      await _settle(t);
      expect(find.byType(TimePickerDialog), findsNothing);
    });

    testWidgets('deleting asks first, and Cancel keeps everything', (t) async {
      final state = await _open(t, backend: FakeWellBackend());
      await state.cast('A calm new home', WishKind.big, WishCategory.home);
      await t.tap(find.text('Delete my data'));
      await _settle(t);
      expect(find.text('DELETE YOUR DATA?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await _settle(t);
      expect(state.activeWishes, hasLength(1));
      expect(state.onboarded, isTrue);
    });

    testWidgets('confirming deletion wipes the data and returns to first run', (t) async {
      final state = await _open(t, backend: FakeWellBackend());
      await state.cast('A calm new home', WishKind.big, WishCategory.home);
      await t.tap(find.text('Delete my data'));
      await _settle(t);
      await t.tap(find.text('DELETE EVERYTHING'));
      await _settle(t);
      expect(state.activeWishes, isEmpty);
      expect(state.onboarded, isFalse);
    });

    testWidgets('signing out asks first and then signs out', (t) async {
      final backend = FakeWellBackend(account: 'ada@example.com');
      final state = await _open(t, backend: backend);
      await t.tap(find.text('Sign out'));
      await _settle(t);
      expect(find.text('SIGN OUT?'), findsOneWidget);
      await t.tap(find.text('SIGN OUT'));
      await _settle(t);
      expect(state.accountLabel, isNull);
    });

    testWidgets('the About section shows the installed version', (t) async {
      await _open(t, backend: FakeWellBackend());
      await _settle(t);
      expect(find.text('1.0.0 (1)'), findsOneWidget);
    });

    testWidgets('the anonymity explainer opens', (t) async {
      await _open(t, backend: FakeWellBackend());
      await t.tap(find.text('How the Well stays anonymous'));
      await _settle(t);
      expect(find.text('ANONYMOUS BY DESIGN'), findsOneWidget);
      expect(find.text('No name, ever'), findsOneWidget);
    });

    testWidgets('admins see the dashboard; everyone else does not', (t) async {
      await _open(t, backend: FakeWellBackend());
      expect(find.text('Admin dashboard'), findsNothing);
      final admin = FakeWellBackend(account: 'boss@example.com')..admin = true;
      await _open(t, backend: admin);
      expect(find.text('Admin dashboard'), findsOneWidget);
    });
  });

  group('Settings renders (opt-in)', () {
    final enabled = Platform.environment.containsKey('SHOTS');

    Future<void> shot(WidgetTester t, String name) async {
      await _settle(t);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
    }

    Future<void> withShadows(Future<void> Function() body) async {
      debugDisableShadows = false;
      try {
        await body();
      } finally {
        debugDisableShadows = true;
      }
    }

    testWidgets('guest', skip: !enabled, (t) async {
      await withShadows(() async {
        final state = await _open(t, backend: FakeWellBackend(), precache: true);
        await state.cast('Signed the lease on my townhouse', WishKind.big, WishCategory.home);
        await state.cast('Free iced coffee, the barista was kind', WishKind.spark, WishCategory.daily);
        await shot(t, '18_settings_guest');
      });
    });

    testWidgets('signed in, reminder on', skip: !enabled, (t) async {
      await withShadows(() async {
        final state = await _open(t, backend: FakeWellBackend(account: 'ada@example.com'), precache: true);
        await state.cast('Signed the lease on my townhouse', WishKind.big, WishCategory.home);
        await state.setReminder(hour: 19, minute: 30, enabled: true);
        await state.setHaptics(false);
        await shot(t, '18_settings_account');
      });
    });

    testWidgets('delete confirmation', skip: !enabled, (t) async {
      await withShadows(() async {
        await t.binding.setSurfaceSize(const Size(430, 932));
        await _open(t, backend: FakeWellBackend(account: 'ada@example.com'), precache: true);
        await t.binding.setSurfaceSize(const Size(430, 932));
        await t.pump();
        await t.scrollUntilVisible(find.text('Delete account'), 300, scrollable: find.byType(Scrollable).first);
        await t.ensureVisible(find.text('Delete account'));
        await t.pump();
        await t.tap(find.text('Delete account'));
        await shot(t, '18_settings_delete');
      });
    });
  });
}
