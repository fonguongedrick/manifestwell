// Opt-in renders of the admin dashboard, for looking at rather than asserting:
//   SHOTS=1 flutter test test/admin_shots_test.dart --update-goldens
// The pictures land in test/shots/admin_*.png.
import 'dart:io';

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
import 'package:manifestwell/screens/admin_screen.dart';
import 'package:manifestwell/state/app_state.dart';
import 'package:manifestwell/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_admin_backend.dart';
import 'support/fake_well_backend.dart';
import 'test_fonts.dart';

Wish _wish(String id, String text, WishCategory c, int luck, {int hoursAgo = 3}) => Wish(
      id: id,
      text: text,
      kind: WishKind.big,
      category: c,
      createdAt: DateTime.now().subtract(Duration(hours: hoursAgo)),
      luck: luck,
    );

void main() {
  setUpAll(loadAppFonts);
  final enabled = Platform.environment.containsKey('SHOTS');

  Future<FakeAdminBackend> open(WidgetTester t, Widget screen, {AppConfig? config, AdminRole role = AdminRole.owner}) async {
    debugDisableShadows = false;
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    SharedPreferences.setMockInitialValues({'onboarded': true});
    final backend = FakeWellBackend(account: 'boss@braidstribe.com')
      ..admin = true
      ..role = role;
    final state = await AppState.load(backend: backend);
    if (config != null) {
      backend.configFeed.add(config);
      await t.pump();
    }
    await t.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(theme: MW.theme(), debugShowCheckedModeBanner: false, home: screen),
    ));
    await t.runAsync(() async {
      await precacheImage(const AssetImage('assets/images/nebula.jpg'), t.element(find.byType(MaterialApp)));
    });
    await t.pump();
    return backend.tools;
  }

  Future<void> shot(WidgetTester t, String name) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
    // Put it back inside the test: Flutter checks this before any teardown.
    debugDisableShadows = true;
  }

  testWidgets('hub', skip: !enabled, (t) async {
    final tools = await open(t, const AdminScreen());
    tools.reports.add(const [
      WishReport(id: 'r1', wishId: 'w1', reason: 'Spam'),
      WishReport(id: 'r2', wishId: 'w1', reason: 'Spam'),
      WishReport(id: 'r3', wishId: 'w2', reason: 'Unkind'),
    ]);
    await shot(t, 'admin_1_hub');
  });

  testWidgets('overview', skip: !enabled, (t) async {
    await t.binding.setSurfaceSize(const Size(430, 1500));
    await open(t, const OverviewScreen());
    await t.binding.setSurfaceSize(const Size(430, 1500));
    await shot(t, 'admin_2_overview');
  });

  testWidgets('moderation', skip: !enabled, (t) async {
    final tools = await open(t, const ModerationScreen());
    tools.wishes.add([
      ModWish(_wish('w1', 'I hope everyone here fails, you are all pathetic', WishCategory.love, 0),
          hidden: false, authorUid: 'k3f9a2x'),
      ModWish(_wish('w2', 'A calm new home near my family', WishCategory.home, 14, hoursAgo: 30),
          hidden: false, authorUid: 'q8m2b7z'),
    ]);
    tools.reports.add(const [
      WishReport(id: 'r1', wishId: 'w1', reason: 'Unkind or harmful'),
      WishReport(id: 'r2', wishId: 'w1', reason: 'Spam or links'),
      WishReport(id: 'r3', wishId: 'w2', reason: 'Other'),
    ]);
    tools.blocked.add(const []);
    await shot(t, 'admin_3_moderation');
  });

  testWidgets('moderation selecting', skip: !enabled, (t) async {
    final tools = await open(t, const ModerationScreen());
    tools.wishes.add([
      ModWish(_wish('w1', 'I hope everyone here fails, you are all pathetic', WishCategory.love, 0),
          hidden: false, authorUid: 'k3f9a2x'),
      ModWish(_wish('w2', 'A calm new home near my family', WishCategory.home, 14, hoursAgo: 30),
          hidden: false, authorUid: 'q8m2b7z'),
      ModWish(_wish('w3', 'Win the lottery, then travel everywhere', WishCategory.travel, 3, hoursAgo: 50),
          hidden: true, authorUid: 'z1y2x3w'),
    ]);
    tools.reports.add([
      WishReport(id: 'r1', wishId: 'w1', reason: 'Unkind or harmful', at: DateTime.now().subtract(const Duration(hours: 5))),
      WishReport(id: 'r2', wishId: 'w1', reason: 'Spam or links', at: DateTime.now().subtract(const Duration(hours: 2))),
      WishReport(id: 'r3', wishId: 'w2', reason: 'Other', at: DateTime.now().subtract(const Duration(hours: 26))),
    ]);
    tools.blocked.add(const []);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    await t.tap(find.text('All wishes'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Select'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('I hope everyone here fails, you are all pathetic'));
    await t.tap(find.text('A calm new home near my family'));
    await shot(t, 'admin_3b_moderation_selecting');
  });

  testWidgets('hub as a moderator', skip: !enabled, (t) async {
    final tools = await open(t, const AdminScreen(), role: AdminRole.moderator);
    tools.reports.add(const [WishReport(id: 'r1', wishId: 'w1', reason: 'Spam')]);
    await shot(t, 'admin_1b_hub_moderator');
  });

  testWidgets('activity', skip: !enabled, (t) async {
    final tools = await open(t, const ActivityScreen());
    tools.log.add([
      AdminLogEntry(id: '1', action: 'remove', detail: 'wish 4f9a2b1c; 2 reports cleared. Reason: Harassment or unkindness', by: 'mod@braidstribe.com', at: DateTime.now().subtract(const Duration(minutes: 12))),
      AdminLogEntry(id: '2', action: 'block', detail: 'person k3f9a2x; 3 wishes hidden. Reason: Spam or links: same link five times', by: 'boss@braidstribe.com', at: DateTime.now().subtract(const Duration(hours: 3))),
      AdminLogEntry(id: '3', action: 'announce', detail: '"Gratitude circle on Friday" to Everyone', by: 'boss@braidstribe.com', at: DateTime.now().subtract(const Duration(days: 1))),
      AdminLogEntry(id: '4', action: 'grant', detail: 'Plus (month) given to ada@example.com', by: 'boss@braidstribe.com', at: DateTime.now().subtract(const Duration(days: 2))),
      AdminLogEntry(id: '5', action: 'admin-role', detail: 'mod@braidstribe.com: admin to moderator', by: 'boss@braidstribe.com', at: DateTime.now().subtract(const Duration(days: 4))),
    ]);
    await shot(t, 'admin_8_activity');
  });

  testWidgets('announcements', skip: !enabled, (t) async {
    await t.binding.setSurfaceSize(const Size(430, 1300));
    final tools = await open(t, const AnnouncementsScreen());
    await t.binding.setSurfaceSize(const Size(430, 1300));
    tools.announcements.add([
      Announcement(
        id: 'a1',
        title: 'Gratitude circle on Friday',
        body: 'Join us at 7pm for a live gratitude circle in the Well.',
        audience: Audience.all,
        status: AnnouncementStatus.sent,
        sent: 318,
        failed: 4,
        at: DateTime.now().subtract(const Duration(days: 2)),
      ),
      Announcement(
        id: 'a2',
        title: 'New in the Vault',
        body: 'You can now revisit any wish after 30 days.',
        audience: Audience.ios,
        status: AnnouncementStatus.sent,
        sent: 120,
        at: DateTime.now().subtract(const Duration(days: 9)),
      ),
    ]);
    await t.enterText(find.byType(TextField).at(0), 'Gratitude circle on Friday');
    await t.enterText(find.byType(TextField).at(1), 'Join us at 7pm for a live gratitude circle in the Well.');
    await shot(t, 'admin_4_announcements');
  });

  testWidgets('subscriptions', skip: !enabled, (t) async {
    await t.binding.setSurfaceSize(const Size(430, 1500));
    final tools = await open(t, const SubscriptionsScreen());
    await t.binding.setSurfaceSize(const Size(430, 1500));
    tools.people['ada@example.com'] = const SubscriberDetail(
      uid: 'u-ada',
      email: 'ada@example.com',
    );
    tools.subscribers.add([
      SubscriberRecord(
          uid: 'u1', email: 'maya@example.com', status: SubscriptionStatus.active, expiresAt: DateTime(2027, 3, 9)),
      SubscriberRecord(
          uid: 'u2', email: 'jon@example.com', status: SubscriptionStatus.cancelled, expiresAt: DateTime(2026, 12, 1)),
      SubscriberRecord(
          uid: 'u3', email: 'lea@example.com', status: SubscriptionStatus.expired, expiresAt: DateTime(2026, 9, 1)),
    ]);
    await t.enterText(find.byType(TextField).first, 'ada@example.com');
    await t.pump();
    await t.tap(find.text('FIND'));
    await shot(t, 'admin_6_subscriptions');
  });

  testWidgets('admins', skip: !enabled, (t) async {
    await open(t, const AdminsScreen());
    await shot(t, 'admin_7_admins');
  });

  testWidgets('controls', skip: !enabled, (t) async {
    await t.binding.setSurfaceSize(const Size(430, 1250));
    await open(
      t,
      const ControlsScreen(),
      config: const AppConfig(banner: 'Our monthly gratitude circle is this Friday at 7pm.', blockedTerms: ['spam', 'buy now', 'scam']),
    );
    await t.binding.setSurfaceSize(const Size(430, 1250));
    await shot(t, 'admin_5_controls');
  });
}
