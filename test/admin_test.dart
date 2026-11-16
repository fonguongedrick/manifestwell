// The admin dashboard: every module is driven through a fake backend, so what
// is checked is what each screen asks the backend to do (and what it shows).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manifestwell/models/admin.dart';
import 'package:manifestwell/models/moderation.dart';
import 'package:manifestwell/models/wish.dart';
import 'package:manifestwell/screens/admin/activity_screen.dart';
import 'package:manifestwell/screens/admin/admins_screen.dart';
import 'package:manifestwell/screens/admin/announcements_screen.dart';
import 'package:manifestwell/screens/admin/subscriptions_screen.dart';
import 'package:manifestwell/screens/admin/controls_screen.dart';
import 'package:manifestwell/screens/admin/moderation_screen.dart';
import 'package:manifestwell/screens/admin/overview_screen.dart';
import 'package:manifestwell/screens/admin/people_screen.dart';
import 'package:manifestwell/screens/admin_screen.dart';
import 'package:manifestwell/screens/well_screen.dart';
import 'package:manifestwell/state/admin_backend.dart';
import 'package:manifestwell/state/app_state.dart';
import 'package:manifestwell/theme.dart';
import 'package:manifestwell/widgets/ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_admin_backend.dart';
import 'support/fake_well_backend.dart';
import 'test_fonts.dart';

Wish _wish(String id, String text, {int luck = 0}) => Wish(
      id: id,
      text: text,
      kind: WishKind.big,
      category: WishCategory.love,
      createdAt: DateTime(2026, 10, 27, 9, 30),
      luck: luck,
    );

class _Rig {
  final FakeWellBackend backend;
  final AppState state;
  _Rig(this.backend, this.state);
  FakeAdminBackend get tools => backend.tools;
}

Future<_Rig> _open(WidgetTester t, Widget screen, {void Function(FakeAdminBackend tools)? prepare}) async {
  t.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
  SharedPreferences.setMockInitialValues({'onboarded': true});
  final backend = FakeWellBackend(account: 'boss@example.com')..admin = true;
  prepare?.call(backend.tools);
  final state = await AppState.load(backend: backend);
  await t.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(theme: MW.theme(), debugShowCheckedModeBanner: false, home: screen),
  ));
  await t.pump();
  return _Rig(backend, state);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

/// A round icon button by its accessibility label.
Finder _iconButton(String label) =>
    find.byWidgetPredicate((w) => w is RoundIconButton && w.semanticLabel == label);

Finder _field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

/// The confirm button of an open bottom sheet (its label is upper-cased).
Finder _sheetButton(String label) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(label.toUpperCase()));

void main() {
  setUpAll(loadAppFonts);

  group('Hub', () {
    testWidgets('lists every module and shows how many reports are waiting', (t) async {
      final rig = await _open(t, const AdminScreen());
      rig.tools.reports.add([
        const WishReport(id: 'r1', wishId: 'w1', reason: 'Spam'),
        const WishReport(id: 'r2', wishId: 'w2', reason: 'Spam'),
      ]);
      await _settle(t);
      for (final name in [
        'Overview',
        'Moderation',
        'People',
        'Announcements',
        'Subscriptions',
        'Admins',
        'Controls',
        'Activity',
        'Export data',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('2'), findsOneWidget); // the badge
      expect(find.text('Signed in as boss@example.com'), findsOneWidget);
    });

    testWidgets('each card opens its page', (t) async {
      final rig = await _open(t, const AdminScreen());
      for (final (card, page) in [
        ('People', PeopleScreen),
        ('Controls', ControlsScreen),
        ('Activity', ActivityScreen),
        ('Announcements', AnnouncementsScreen),
        ('Moderation', ModerationScreen),
        ('Overview', OverviewScreen),
        ('Subscriptions', SubscriptionsScreen),
        ('Admins', AdminsScreen),
      ]) {
        await t.tap(find.text(card));
        await _settle(t);
        expect(find.byType(page), findsOneWidget, reason: card);
        await t.tap(_iconButton('Back'));
        await _settle(t);
      }
      expect(rig.tools.calls, isEmpty);
    });

    testWidgets('without a connection it says so instead of showing dead cards', (t) async {
      SharedPreferences.setMockInitialValues({});
      final state = await AppState.load();
      await t.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: MW.theme(), home: const AdminScreen()),
      ));
      await t.pump();
      expect(find.textContaining('needs a connection'), findsOneWidget);
      expect(find.text('Moderation'), findsNothing);
    });

    testWidgets('export asks the backend for the chosen table', (t) async {
      final rig = await _open(t, const AdminScreen());
      await t.scrollUntilVisible(find.text('Export data'), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Export data'));
      await _settle(t);
      await t.tap(find.text('Reports'));
      await _settle(t);
      expect(rig.tools.exports, [AdminExport.reports]);
    });
  });

  group('Moderation', () {
    testWidgets('hide, then remove with a confirmation', (t) async {
      final rig = await _open(t, const ModerationScreen());
      rig.tools.wishes.add([ModWish(_wish('w1', 'Something unkind'), hidden: false, authorUid: 'abcdef123')]);
      rig.tools.reports.add(const [
        WishReport(id: 'r1', wishId: 'w1', reason: 'Unkind or harmful'),
        WishReport(id: 'r2', wishId: 'w1', reason: 'Spam or links'),
      ]);
      rig.tools.blocked.add(const []);
      await _settle(t);

      expect(find.text('Something unkind'), findsWidgets);
      expect(find.text('2 reports'), findsWidgets);

      await t.tap(find.text('Hide').first);
      await t.pump();
      expect(rig.tools.calls, ['hide:w1:true']);

      await t.tap(find.text('Remove').first);
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Remove'));
      await _settle(t);
      expect(rig.tools.calls.last, 'remove:w1');
    });

    testWidgets('an empty queue says the Well is calm', (t) async {
      final rig = await _open(t, const ModerationScreen());
      rig.tools.wishes.add(const []);
      rig.tools.reports.add(const []);
      rig.tools.blocked.add(const []);
      await _settle(t);
      expect(find.text('Nothing reported. The Well is calm.'), findsOneWidget);
    });

    testWidgets('dismissing reports clears them in one action, leaving the wish', (t) async {
      final rig = await _open(t, const ModerationScreen());
      rig.tools.wishes.add([ModWish(_wish('w1', 'A fine wish'), hidden: false)]);
      rig.tools.reports.add(const [
        WishReport(id: 'r1', wishId: 'w1', reason: 'Other'),
        WishReport(id: 'r2', wishId: 'w1', reason: 'Other'),
      ]);
      rig.tools.blocked.add(const []);
      await _settle(t);
      await t.tap(find.text('Dismiss reports'));
      await t.pump();
      expect(rig.tools.calls, ['dismiss:w1:r1+r2']);
    });

    testWidgets('blocking an author asks first, and only then blocks them', (t) async {
      final rig = await _open(t, const ModerationScreen());
      rig.tools.wishes.add([ModWish(_wish('w1', 'Bad wish'), hidden: false, authorUid: 'abcdef123')]);
      rig.tools.reports.add(const [WishReport(id: 'r1', wishId: 'w1', reason: 'Spam')]);
      rig.tools.blocked.add(const []);
      await _settle(t);

      await t.tap(find.text('Block author'));
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(t);
      expect(rig.tools.calls, isEmpty);

      await t.tap(find.text('Block author'));
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Block'));
      await _settle(t);
      expect(rig.tools.calls, ['block:abcdef123']);
    });

    testWidgets('an already-blocked author is marked and cannot be blocked twice', (t) async {
      final rig = await _open(t, const ModerationScreen());
      rig.tools.wishes.add([ModWish(_wish('w1', 'Bad wish'), hidden: true, authorUid: 'abcdef123')]);
      rig.tools.reports.add(const [WishReport(id: 'r1', wishId: 'w1', reason: 'Spam')]);
      rig.tools.blocked.add([BlockedPerson(uid: 'abcdef123', at: DateTime(2026, 10, 27))]);
      await _settle(t);
      expect(find.text('Block author'), findsNothing);
      expect(find.textContaining('Blocked'), findsWidgets);
      expect(find.text('Restore'), findsOneWidget);
    });

    testWidgets('the Hidden filter shows only hidden wishes', (t) async {
      final rig = await _open(t, const ModerationScreen());
      rig.tools.wishes.add([
        ModWish(_wish('w1', 'Visible wish'), hidden: false),
        ModWish(_wish('w2', 'Hidden wish'), hidden: true),
      ]);
      rig.tools.reports.add(const []);
      rig.tools.blocked.add(const []);
      await _settle(t);
      await t.tap(find.text('All wishes'));
      await _settle(t);
      expect(find.text('Visible wish'), findsOneWidget);
      await t.tap(find.text('Hidden'));
      await _settle(t);
      expect(find.text('Visible wish'), findsNothing);
      expect(find.text('Hidden wish'), findsOneWidget);
    });

    testWidgets('a failed action says so instead of failing silently', (t) async {
      final rig = await _open(t, const ModerationScreen());
      rig.tools.wishes.add([ModWish(_wish('w1', 'A wish'), hidden: false)]);
      rig.tools.reports.add(const [WishReport(id: 'r1', wishId: 'w1', reason: 'Spam')]);
      rig.tools.blocked.add(const []);
      await _settle(t);
      rig.tools.failActions = true;
      await t.tap(find.text('Hide').first);
      await _settle(t);
      expect(find.textContaining('did not go through'), findsOneWidget);
    });
  });

  group('Overview', () {
    testWidgets('shows the figures it was given', (t) async {
      await _open(t, const OverviewScreen());
      await _settle(t);
      expect(find.text('1,284'), findsOneWidget); // wishes in the Well
      expect(find.text('9,120'), findsOneWidget); // luck given
      expect(find.text('OPEN REPORTS'), findsOneWidget);
      expect(find.textContaining('96 people'), findsOneWidget);
      expect(find.text('410'), findsWidgets); // career + devices
      expect(find.text('Career'), findsOneWidget);
    });

    testWidgets('a failure offers to try again, and trying again recovers', (t) async {
      final rig = await _open(t, const OverviewScreen());
      // The first load already succeeded; make the next one fail, then recover.
      rig.tools.overviewError = StateError('offline');
      await t.tap(_iconButton('Refresh'));
      await _settle(t);
      expect(find.textContaining('Could not load'), findsOneWidget);
      rig.tools.overviewError = null;
      await t.tap(find.text('Try again'));
      await _settle(t);
      expect(find.text('1,284'), findsOneWidget);
    });

    testWidgets('says when the window was too busy to read in full', (t) async {
      await _open(
        t,
        const OverviewScreen(),
        prepare: (tools) => tools.stats = OverviewStats(
          wishes: 5000,
          hidden: 0,
          openReports: 0,
          luck: 0,
          blocked: 0,
          devices: 0,
          androidDevices: 0,
          iosDevices: 0,
          luckAlertDevices: 0,
          revisitDevices: 0,
          byCategory: const {},
          daily: [DailyCount(DateTime(2026, 11, 10), 1000)],
          wishers: 1,
          windowLuck: 0,
          windowCapped: true,
        ),
      );
      await _settle(t);
      expect(find.textContaining('are a minimum'), findsOneWidget);
    });
  });

  group('People', () {
    testWidgets('lists blocked people and unblocks after confirmation', (t) async {
      final rig = await _open(t, const PeopleScreen());
      rig.tools.blocked.add([
        BlockedPerson(uid: 'abcdef123', reason: 'Spam wishes', at: DateTime(2026, 10, 27)),
      ]);
      await _settle(t);
      expect(find.text('Person abcdef'), findsOneWidget);
      expect(find.text('Spam wishes'), findsOneWidget);
      await t.tap(find.text('Unblock'));
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Unblock'));
      await _settle(t);
      expect(rig.tools.calls, ['unblock:abcdef123']);
    });

    testWidgets('says so when no one is blocked', (t) async {
      final rig = await _open(t, const PeopleScreen());
      rig.tools.blocked.add(const []);
      await _settle(t);
      expect(find.text('No one is blocked.'), findsOneWidget);
    });
  });

  group('Announcements', () {
    testWidgets('Send does nothing until there is a title and a message', (t) async {
      final rig = await _open(t, const AnnouncementsScreen());
      await t.tap(find.text('SEND'));
      await _settle(t);
      expect(find.byType(BottomSheet), findsNothing); // not even asked to confirm
      expect(rig.tools.calls, isEmpty);

      await t.enterText(_field('announce-title'), 'Only a title');
      await t.tap(find.text('SEND'));
      await _settle(t);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('confirms, then queues the push for the chosen audience', (t) async {
      final rig = await _open(t, const AnnouncementsScreen());
      await t.enterText(_field('announce-title'), 'Gratitude circle');
      await t.enterText(_field('announce-body'), 'Join us Friday at 7pm.');
      await t.tap(find.text('Android'));
      await _settle(t);
      await t.tap(find.text('SEND'));
      await _settle(t);
      expect(find.textContaining('every Android phone'), findsOneWidget);
      await t.tap(_sheetButton('Send'));
      await _settle(t);
      expect(rig.tools.calls, ['announce:android:Gratitude circle:Join us Friday at 7pm.']);
      // The form clears once it is queued.
      expect(find.text('Gratitude circle'), findsNothing);
    });

    testWidgets('cancelling the confirmation sends nothing', (t) async {
      final rig = await _open(t, const AnnouncementsScreen());
      await t.enterText(_field('announce-title'), 'Hello');
      await t.enterText(_field('announce-body'), 'There');
      await t.pump(); // the Send button enables once both fields have text
      await t.tap(find.text('SEND'));
      await _settle(t);
      await t.tap(find.text('Cancel'));
      await _settle(t);
      expect(rig.tools.calls, isEmpty);
      expect(find.text('Hello'), findsOneWidget); // still typed
    });

    testWidgets('a failure keeps what was typed', (t) async {
      final rig = await _open(t, const AnnouncementsScreen());
      await t.enterText(_field('announce-title'), 'Hello');
      await t.enterText(_field('announce-body'), 'There');
      await t.pump();
      rig.tools.failActions = true;
      await t.tap(find.text('SEND'));
      await _settle(t);
      await t.tap(_sheetButton('Send'));
      await _settle(t);
      expect(find.textContaining('did not go through'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('the history shows how each one went', (t) async {
      final rig = await _open(t, const AnnouncementsScreen());
      rig.tools.announcements.add([
        Announcement(
          id: 'a1',
          title: 'Hello world',
          body: 'First note',
          audience: Audience.all,
          status: AnnouncementStatus.sent,
          sent: 12,
          failed: 1,
          at: DateTime(2026, 10, 27),
        ),
        Announcement(
          id: 'a2',
          title: 'Old and stuck',
          body: 'Never left',
          audience: Audience.ios,
          status: AnnouncementStatus.queued,
          at: DateTime.now().subtract(const Duration(minutes: 30)),
        ),
      ]);
      await _settle(t);
      expect(find.text('Delivered to 12 phones, 1 could not be reached'), findsOneWidget);
      expect(find.textContaining('Still queued'), findsOneWidget);
    });
  });

  group('Controls', () {
    testWidgets('Save is off until something changes, then saves the cleaned values', (t) async {
      final rig = await _open(t, const ControlsScreen());
      await t.enterText(_field('field-banner'), '  Gratitude circle on Friday  ');
      await t.enterText(_field('field-terms'), 'Spam, buy now\nSPAM, x, scam');
      await t.pump();
      await t.tap(find.text('SAVE CHANGES'));
      await _settle(t);
      expect(rig.tools.savedConfig, isNotNull);
      expect(rig.tools.savedConfig!.banner, 'Gratitude circle on Friday');
      // Lower-cased, de-duplicated, and the one-letter entry dropped.
      expect(rig.tools.savedConfig!.blockedTerms, ['spam', 'buy now', 'scam']);
      expect(rig.tools.savedConfig!.wishingPaused, isFalse);
    });

    testWidgets('nothing is saved when nothing changed', (t) async {
      final rig = await _open(t, const ControlsScreen());
      await t.tap(find.text('SAVE CHANGES'));
      await _settle(t);
      expect(rig.tools.savedConfig, isNull);
    });

    testWidgets('pausing wishes needs a confirmation', (t) async {
      final rig = await _open(t, const ControlsScreen());
      await t.tap(find.byKey(const ValueKey('switch-pause')));
      await t.pump();
      expect(find.text('On: sharing is paused'), findsOneWidget);
      await t.tap(find.text('SAVE CHANGES'));
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(t);
      expect(rig.tools.savedConfig, isNull);

      await t.tap(find.text('SAVE CHANGES'));
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Pause'));
      await _settle(t);
      expect(rig.tools.savedConfig!.wishingPaused, isTrue);
    });

    testWidgets('opens showing the settings that are live now', (t) async {
      SharedPreferences.setMockInitialValues({});
      final backend = FakeWellBackend(account: 'boss@example.com')..admin = true;
      final state = await AppState.load(backend: backend);
      backend.configFeed.add(const AppConfig(banner: 'Live banner', blockedTerms: ['spam', 'scam']));
      await t.pump(); // lets the stream event reach the app (time is faked in tests)
      expect(state.config.banner, 'Live banner');
      await t.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: MW.theme(), home: const ControlsScreen()),
      ));
      await t.pump();
      expect(find.text('Live banner'), findsOneWidget);
      expect(find.text('spam, scam'), findsOneWidget);
    });
  });

  group('Admins', () {
    testWidgets('lists admins, marks owners and you, and cannot remove yourself', (t) async {
      await _open(t, const AdminsScreen());
      await _settle(t);
      expect(find.text('boss@braidstribe.com'), findsOneWidget);
      expect(find.text('Owner · You'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget); // the helper
      // Only the other admin gets a Remove link.
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('adds an admin by email, and the list shows them', (t) async {
      final rig = await _open(t, const AdminsScreen());
      await _settle(t);
      await t.enterText(_field('field-admin-email'), 'new@braidstribe.com');
      await t.pump();
      await t.tap(find.text('ADD ADMIN'));
      await _settle(t);
      expect(rig.tools.calls, ['add-admin:new@braidstribe.com']);
      expect(find.text('new@braidstribe.com'), findsOneWidget);
      expect(find.text('new@braidstribe.com is now an admin.'), findsOneWidget);
    });

    testWidgets('Add stays off until there is an email', (t) async {
      final rig = await _open(t, const AdminsScreen());
      await _settle(t);
      await t.tap(find.text('ADD ADMIN'));
      await _settle(t);
      expect(rig.tools.calls, isEmpty);
      await t.enterText(_field('field-admin-email'), 'not an email');
      await t.pump();
      await t.tap(find.text('ADD ADMIN'));
      await _settle(t);
      expect(rig.tools.calls, isEmpty);
    });

    testWidgets('an email with no account shows the server reason and keeps the text', (t) async {
      final rig = await _open(t, const AdminsScreen());
      await _settle(t);
      await t.enterText(_field('field-admin-email'), 'stranger@example.com');
      await t.pump();
      await t.tap(find.text('ADD ADMIN'));
      await _settle(t);
      expect(find.textContaining('No account has that email'), findsOneWidget);
      expect(find.text('stranger@example.com'), findsOneWidget);
      expect(rig.tools.admins.length, 2);
    });

    testWidgets('removing an admin asks first', (t) async {
      final rig = await _open(t, const AdminsScreen());
      await _settle(t);
      await t.tap(find.text('Remove'));
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(t);
      expect(rig.tools.calls, isEmpty);

      await t.tap(find.text('Remove'));
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Remove'));
      await _settle(t);
      expect(rig.tools.calls, ['remove-admin:helper-uid-2']);
      expect(find.text('helper@braidstribe.com'), findsNothing);
    });
  });

  group('Subscriptions', () {
    /// [purchase]: a store subscription ending Mar 9, 2027 (RevenueCat's webhook
    /// writes the store in capitals). [gift]: Plus an admin gave, ending Jan 5.
    SubscriberDetail person({bool purchase = false, bool gift = false}) => SubscriberDetail(
          uid: 'u-ada',
          email: 'ada@example.com',
          purchaseActive: purchase,
          purchaseExpiresAt: purchase ? DateTime(2027, 3, 9) : null,
          store: purchase ? 'APP_STORE' : null,
          grantActive: gift,
          grantExpiresAt: gift ? DateTime(2027, 1, 5) : null,
        );

    Future<_Rig> openWith(WidgetTester t, SubscriberDetail? p) =>
        _open(t, const SubscriptionsScreen(), prepare: (tools) {
          if (p != null) tools.people[p.email] = p;
        });

    testWidgets('finds someone by email and shows what they have', (t) async {
      final rig = await openWith(t, person(purchase: true));
      await t.enterText(_field('field-find'), 'ada@example.com');
      await t.pump();
      await t.tap(find.text('FIND'));
      await _settle(t);
      expect(rig.tools.calls, ['lookup:ada@example.com']);
      expect(find.text('Plus until Mar 9, 2027'), findsOneWidget);
      expect(find.text('Bought on the App Store'), findsOneWidget);
      // A purchase can't be taken back from here.
      expect(find.text('Take back given Plus'), findsNothing);
    });

    testWidgets('someone with no account gets the reason, not a blank card', (t) async {
      await openWith(t, null);
      await t.enterText(_field('field-find'), 'ghost@example.com');
      await t.pump();
      await t.tap(find.text('FIND'));
      await _settle(t);
      expect(find.textContaining('No account has that email'), findsOneWidget);
      expect(find.text('GIVE PLUS'), findsNothing);
    });

    testWidgets('gives Plus for the chosen length, after confirming', (t) async {
      final rig = await openWith(t, person());
      await t.enterText(_field('field-find'), 'ada@example.com');
      await t.pump();
      await t.tap(find.text('FIND'));
      await _settle(t);
      expect(find.text('No Plus right now'), findsOneWidget);

      await t.tap(find.text('3 months'));
      await _settle(t);
      await t.tap(find.text('GIVE PLUS'));
      await _settle(t);
      expect(find.textContaining('free. Nobody is charged'), findsOneWidget);
      await t.tap(find.widgetWithText(TextButton, 'Give Plus'));
      await _settle(t);
      expect(rig.tools.calls.last, 'grant:u-ada:quarter');
      expect(find.text('Plus until Jan 5, 2027'), findsOneWidget);
      expect(find.text('Given by an admin'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation gives nothing', (t) async {
      final rig = await openWith(t, person());
      await t.enterText(_field('field-find'), 'ada@example.com');
      await t.pump();
      await t.tap(find.text('FIND'));
      await _settle(t);
      await t.tap(find.text('GIVE PLUS'));
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(t);
      expect(rig.tools.calls.where((c) => c.startsWith('grant')), isEmpty);
    });

    testWidgets('lifetime is offered and described as such', (t) async {
      final rig = await openWith(t, person());
      await t.enterText(_field('field-find'), 'ada@example.com');
      await t.pump();
      await t.tap(find.text('FIND'));
      await _settle(t);
      await t.tap(find.text('Lifetime'));
      await _settle(t);
      await t.tap(find.text('GIVE PLUS'));
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Give Plus'));
      await _settle(t);
      expect(rig.tools.calls.last, 'grant:u-ada:lifetime');
      expect(find.text('Plus for life'), findsOneWidget);
    });

    testWidgets('given Plus can be taken back, after confirming', (t) async {
      final rig = await openWith(t, person(gift: true));
      await t.enterText(_field('field-find'), 'ada@example.com');
      await t.pump();
      await t.tap(find.text('FIND'));
      await _settle(t);
      await t.tap(find.text('Take back given Plus'));
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Take back'));
      await _settle(t);
      expect(rig.tools.calls.last, 'revoke:u-ada');
      expect(find.text('No Plus right now'), findsOneWidget);
    });

    testWidgets('a paying member who is also given Plus shows both, and keeps the purchase when it is taken back',
        (t) async {
      final rig = await openWith(t, person(purchase: true, gift: true));
      await t.enterText(_field('field-find'), 'ada@example.com');
      await t.pump();
      await t.tap(find.text('FIND'));
      await _settle(t);
      expect(find.text('Given by an admin'), findsOneWidget);
      expect(find.text('Bought on the App Store'), findsOneWidget);
      // Whichever lasts longer is the date shown.
      expect(find.text('Plus until Mar 9, 2027'), findsOneWidget);

      await t.tap(find.text('Take back given Plus'));
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Take back'));
      await _settle(t);
      expect(rig.tools.calls.last, 'revoke:u-ada');
      expect(find.text('Given by an admin'), findsNothing);
      expect(find.text('Bought on the App Store'), findsOneWidget);
      expect(find.text('Plus until Mar 9, 2027'), findsOneWidget);
      expect(find.text('Take back given Plus'), findsNothing);
    });

    testWidgets('the member list shows someone who was only ever given Plus', (t) async {
      final rig = await openWith(t, null);
      rig.tools.subscribers.add([
        SubscriberRecord(
          uid: 'u-gift',
          email: 'gift@example.com',
          status: SubscriptionStatus.expired, // never bought anything
          grant: PlusGrant(until: DateTime.now().add(const Duration(days: 20))),
        ),
        const SubscriberRecord(
          uid: 'u-life',
          email: 'life@example.com',
          status: SubscriptionStatus.expired,
          grant: PlusGrant(lifetime: true),
        ),
        SubscriberRecord(
          uid: 'u-old',
          email: 'old@example.com',
          status: SubscriptionStatus.expired,
          grant: PlusGrant(until: DateTime(2020, 1, 1)), // ran out long ago
        ),
      ]);
      await _settle(t);
      expect(find.textContaining('Given by an admin · until'), findsOneWidget);
      expect(find.text('Given by an admin · for life'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget); // the lapsed gift
      expect(find.text('WITH PLUS NOW'), findsOneWidget);
      // Two of the three have Plus now.
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('a failed grant says so and leaves the card as it was', (t) async {
      final rig = await openWith(t, person());
      await t.enterText(_field('field-find'), 'ada@example.com');
      await t.pump();
      await t.tap(find.text('FIND'));
      await _settle(t);
      rig.tools.failActions = true;
      await t.tap(find.text('GIVE PLUS'));
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Give Plus'));
      await _settle(t);
      expect(find.textContaining('did not go through'), findsOneWidget);
      expect(find.text('No Plus right now'), findsOneWidget);
    });

    testWidgets('the member list shows status, and tapping a row looks them up', (t) async {
      final rig = await openWith(t, person(purchase: true));
      rig.tools.subscribers.add([
        SubscriberRecord(
          uid: 'u-ada',
          email: 'ada@example.com',
          status: SubscriptionStatus.active,
          expiresAt: DateTime(2027, 3, 9),
        ),
        SubscriberRecord(
          uid: 'u-bo',
          email: 'bo@example.com',
          status: SubscriptionStatus.cancelled,
          expiresAt: DateTime(2026, 12, 1),
        ),
        SubscriberRecord(
          uid: 'u-cy',
          email: 'cy@example.com',
          status: SubscriptionStatus.expired,
          expiresAt: DateTime(2026, 9, 1),
        ),
        const SubscriberRecord(uid: r'$RCAnonymousID:x', guest: true, status: SubscriptionStatus.billingIssue),
      ]);
      await _settle(t);
      expect(find.text('Active · until Mar 9, 2027'), findsOneWidget);
      expect(find.text('Cancelled, still active · until Dec 1, 2026'), findsOneWidget);
      expect(find.text('Expired · ended Sep 1, 2026'), findsOneWidget);
      expect(find.text('Guest purchase'), findsOneWidget);
      expect(find.text('WITH PLUS NOW'), findsOneWidget);

      await t.scrollUntilVisible(find.text('ada@example.com'), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('ada@example.com'));
      await _settle(t);
      expect(rig.tools.calls, ['lookup:ada@example.com']);
    });

    testWidgets('before the webhook is connected the list explains itself', (t) async {
      final rig = await openWith(t, null);
      rig.tools.subscribers.add(const []);
      await _settle(t);
      expect(find.textContaining('RevenueCat webhook'), findsOneWidget);
    });
  });

  group('Admin access is live', () {
    testWidgets('the app follows the admin record as it changes', (t) async {
      final rig = await _open(t, const AdminScreen());
      expect(rig.state.isAdmin, isTrue);
      rig.backend.adminFeed.add(false);
      await t.pump();
      expect(rig.state.isAdmin, isFalse);
      rig.backend.adminFeed.add(true);
      await t.pump();
      expect(rig.state.isAdmin, isTrue);
    });

    testWidgets('a removed admin loses the open page, with the reason', (t) async {
      final rig = await _open(t, const ModerationScreen());
      rig.tools.wishes.add(const []);
      rig.tools.reports.add(const []);
      rig.tools.blocked.add(const []);
      await _settle(t);
      expect(find.text('MODERATION'), findsOneWidget);

      rig.backend.adminFeed.add(false);
      await _settle(t);
      expect(find.text('MODERATION'), findsNothing);
      expect(find.text('Admin access has ended for this account.'), findsOneWidget);
    });

    testWidgets('a dashboard opened from another screen drops back to it', (t) async {
      final rig = await _open(t, const _Base());
      await t.tap(find.text('open dashboard'));
      await _settle(t);
      expect(find.byType(AdminScreen), findsOneWidget);

      rig.backend.adminFeed.add(false);
      await _settle(t);
      expect(find.byType(AdminScreen), findsNothing);
      expect(find.text('open dashboard'), findsOneWidget);
    });

    testWidgets('someone who was never an admin is not shown the dashboard either', (t) async {
      SharedPreferences.setMockInitialValues({});
      final backend = FakeWellBackend(account: 'member@example.com'); // not an admin
      final state = await AppState.load(backend: backend);
      await t.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: MW.theme(), home: const _Base()),
      ));
      await t.tap(find.text('open dashboard'));
      await _settle(t);
      expect(find.byType(AdminScreen), findsNothing);
    });
  });

  group('Activity', () {
    testWidgets('lists what admins did, newest first, in plain words', (t) async {
      final rig = await _open(t, const ActivityScreen());
      rig.tools.log.add([
        AdminLogEntry(id: '1', action: 'block', detail: 'person abc; 3 wishes hidden', by: 'boss@example.com', at: DateTime(2026, 10, 27)),
        AdminLogEntry(id: '2', action: 'auto-hide', detail: 'wish w9 matched "spam"', by: 'Automatic', at: DateTime(2026, 10, 26)),
      ]);
      await _settle(t);
      expect(find.text('Blocked a person'), findsOneWidget);
      expect(find.text('Auto-hidden a wish'), findsOneWidget);
      expect(find.textContaining('boss@example.com'), findsOneWidget);
    });

    testWidgets('an empty log explains itself', (t) async {
      final rig = await _open(t, const ActivityScreen());
      rig.tools.log.add(const []);
      await _settle(t);
      expect(find.textContaining('Every admin action will be listed'), findsOneWidget);
    });
  });

  group('Member side', () {
    testWidgets('the Well shows the admin banner, and says when wishing is paused', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      SharedPreferences.setMockInitialValues({'onboarded': true});
      final backend = FakeWellBackend();
      final state = await AppState.load(backend: backend);
      await t.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: MW.theme(),
          home: Scaffold(body: WellScreen(onCast: () {}, onOpenVault: () {})),
        ),
      ));
      await _settle(t);
      expect(find.text('Gratitude circle Friday'), findsNothing);

      backend.configFeed.add(const AppConfig(banner: 'Gratitude circle Friday'));
      await _settle(t);
      expect(find.text('Gratitude circle Friday'), findsOneWidget);
      expect(find.textContaining('paused'), findsNothing);

      backend.configFeed.add(const AppConfig(wishingPaused: true, banner: 'Gratitude circle Friday'));
      await _settle(t);
      expect(find.textContaining('New wishes are paused'), findsOneWidget);
      expect(find.text('Gratitude circle Friday'), findsOneWidget); // still shown beneath

      backend.configFeed.add(AppConfig.defaults);
      await _settle(t);
      expect(find.textContaining('paused'), findsNothing);
    });
  });
}

/// A screen underneath the dashboard, to open it from and fall back to.
class _Base extends StatelessWidget {
  const _Base();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AdminScreen())),
            child: const Text('open dashboard'),
          ),
        ),
      );
}
