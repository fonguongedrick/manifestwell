// The enterprise side of the dashboard: roles and what each may see, moderation
// at scale (search, sort, bulk actions, undo), trends, previews, guards.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manifestwell/models/admin.dart';
import 'package:manifestwell/models/moderation.dart';
import 'package:manifestwell/models/wish.dart';
import 'package:manifestwell/screens/admin/activity_screen.dart';
import 'package:manifestwell/screens/admin/admin_kit.dart';
import 'package:manifestwell/screens/admin/admins_screen.dart';
import 'package:manifestwell/screens/admin/announcements_screen.dart';
import 'package:manifestwell/screens/admin/controls_screen.dart';
import 'package:manifestwell/screens/admin/moderation_screen.dart';
import 'package:manifestwell/screens/admin/overview_screen.dart';
import 'package:manifestwell/screens/admin_screen.dart';
import 'package:manifestwell/state/app_state.dart';
import 'package:manifestwell/theme.dart';
import 'package:manifestwell/widgets/ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_admin_backend.dart';
import 'support/fake_well_backend.dart';
import 'test_fonts.dart';

Wish _wish(String id, String text, {int luck = 0, int hoursAgo = 3, WishCategory c = WishCategory.love}) => Wish(
      id: id,
      text: text,
      kind: WishKind.big,
      category: c,
      createdAt: DateTime.now().subtract(Duration(hours: hoursAgo)),
      luck: luck,
    );

class _Rig {
  final FakeWellBackend backend;
  final AppState state;
  _Rig(this.backend, this.state);
  FakeAdminBackend get tools => backend.tools;
}

Future<_Rig> _open(
  WidgetTester t,
  Widget screen, {
  AdminRole role = AdminRole.owner,
  void Function(FakeAdminBackend tools)? prepare,
  Size size = const Size(430, 1400),
}) async {
  t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
  SharedPreferences.setMockInitialValues({'onboarded': true});
  final backend = FakeWellBackend(account: 'boss@example.com')
    ..admin = true
    ..role = role;
  prepare?.call(backend.tools);
  final state = await AppState.load(backend: backend);
  await t.binding.setSurfaceSize(size);
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

Finder _field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));
Finder _typedIn(String key, String text) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text));
Finder _iconButton(String label) => find.byWidgetPredicate((w) => w is RoundIconButton && w.semanticLabel == label);

/// A trend arrow, found by what a screen reader is told about it.
Finder _trend(String label) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

/// Any trend arrow at all.
Finder _anyTrend() => find.byWidgetPredicate(
    (w) => w is Semantics && (w.properties.label ?? '').contains('compared with the previous period'));

/// Scrolls the page's list until [target] exists. A long list builds its rows
/// lazily, so something near the bottom is not in the tree until you get there.
Future<void> _scrollTo(WidgetTester t, Finder target) async {
  final list = find.byType(ListView).last;
  for (var i = 0; i < 60 && target.evaluate().isEmpty; i++) {
    await t.drag(list, const Offset(0, -700));
    await t.pump();
  }
  expect(target, findsOneWidget, reason: 'never scrolled to it');
  await t.ensureVisible(target);
  await t.pump();
}

/// A screen that opens [page], so there is somewhere to come back to.
class _Launcher extends StatelessWidget {
  final Widget page;
  const _Launcher(this.page);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('open page'),
          ),
        ),
      );
}

void main() {
  setUpAll(loadAppFonts);

  group('Roles: what each may see', () {
    testWidgets('an owner sees every module and the export', (t) async {
      await _open(t, const AdminScreen());
      await _settle(t);
      for (final m in ['Overview', 'Moderation', 'People', 'Announcements', 'Subscriptions', 'Admins', 'Controls', 'Activity', 'Export data']) {
        expect(find.text(m), findsOneWidget, reason: m);
      }
      expect(find.text('OWNER'), findsOneWidget);
    });

    testWidgets('a moderator sees only moderation, people, overview and activity', (t) async {
      await _open(t, const AdminScreen(), role: AdminRole.moderator);
      await _settle(t);
      for (final m in ['Overview', 'Moderation', 'People', 'Activity']) {
        expect(find.text(m), findsOneWidget, reason: m);
      }
      for (final m in ['Announcements', 'Subscriptions', 'Admins', 'Controls', 'Export data']) {
        expect(find.text(m), findsNothing, reason: '$m must be hidden from a moderator');
      }
      expect(find.text('MODERATOR'), findsOneWidget);
    });

    testWidgets('an admin sees everything an owner does', (t) async {
      await _open(t, const AdminScreen(), role: AdminRole.admin);
      await _settle(t);
      expect(find.text('Admins'), findsOneWidget);
      expect(find.text('Export data'), findsOneWidget);
    });

    testWidgets('a moderator who reaches a page that is not theirs is told so', (t) async {
      await _open(t, const AdminsScreen(), role: AdminRole.moderator);
      await _settle(t);
      expect(find.text('Your role does not include this part of the dashboard.'), findsOneWidget);
      expect(find.text('ADD ADMIN'), findsNothing);
    });

    testWidgets('each page a moderator may not open refuses, however it is reached', (t) async {
      for (final page in <Widget>[
        const AnnouncementsScreen(),
        const ControlsScreen(),
      ]) {
        await _open(t, page, role: AdminRole.moderator);
        await _settle(t);
        expect(find.text('Your role does not include this part of the dashboard.'), findsOneWidget, reason: '$page');
      }
    });

    testWidgets('a role change reaches the open dashboard at once', (t) async {
      final rig = await _open(t, const AdminScreen());
      await _settle(t);
      expect(find.text('Announcements'), findsOneWidget);
      rig.backend.adminFeed.add(AdminRole.moderator); // demoted while the app is open
      await _settle(t);
      expect(find.text('Announcements'), findsNothing);
      expect(find.text('Moderation'), findsOneWidget);
      rig.backend.adminFeed.add(AdminRole.admin);
      await _settle(t);
      expect(find.text('Announcements'), findsOneWidget);
    });

    testWidgets('until the role is known the least privileged one applies', (t) async {
      SharedPreferences.setMockInitialValues({});
      final state = await AppState.load(); // no backend: nobody is an admin
      expect(state.isAdmin, isFalse);
      expect(state.adminRole, AdminRole.moderator);
      for (final area in AdminArea.values) {
        expect(state.canAdmin(area), isFalse, reason: '$area');
      }
    });

    testWidgets('a moderator\'s overview does not ask for, or show, phone and Plus figures', (t) async {
      final rig = await _open(t, const OverviewScreen(), role: AdminRole.moderator);
      await _settle(t);
      expect(rig.tools.lastIncludeReach, isFalse);
      expect(find.text('REACH'), findsNothing);
      expect(find.text('PLUS MEMBERS'), findsNothing);
      expect(find.text('WISHES IN THE WELL'), findsOneWidget);
    });

    testWidgets('an owner\'s overview does include them', (t) async {
      final rig = await _open(t, const OverviewScreen());
      await _settle(t);
      expect(rig.tools.lastIncludeReach, isTrue);
      expect(find.text('REACH'), findsOneWidget);
      expect(find.text('PLUS MEMBERS'), findsOneWidget);
    });
  });

  group('Admins and roles', () {
    List<AdminAccount> team() => const [
          AdminAccount(uid: 'o1', email: 'owner@x.com', role: AdminRole.owner),
          AdminAccount(uid: 'me', email: 'me@x.com', role: AdminRole.admin, you: true),
          AdminAccount(uid: 'm1', email: 'mod@x.com', role: AdminRole.moderator),
        ];

    testWidgets('an owner can give the owner role; an admin cannot', (t) async {
      await _open(t, const AdminsScreen());
      await _settle(t);
      expect(find.text('Owner'), findsOneWidget); // a pill to choose
      await t.pumpWidget(const SizedBox());

      await _open(t, const AdminsScreen(), role: AdminRole.admin);
      await _settle(t);
      expect(find.text('Owner'), findsNothing);
      expect(find.text('Moderator'), findsOneWidget);
    });

    testWidgets('adding someone as a moderator sends that role', (t) async {
      final rig = await _open(t, const AdminsScreen());
      await _settle(t);
      await t.enterText(_field('field-admin-email'), 'new@braidstribe.com');
      await t.tap(find.text('Moderator'));
      await t.pump();
      expect(find.text('Reviews wishes and reports, blocks people'), findsWidgets);
      await t.tap(find.text('ADD ADMIN'));
      await _settle(t);
      expect(rig.tools.calls, ['add-admin:new@braidstribe.com:moderator']);
      expect(find.text('new@braidstribe.com is now a moderator.'), findsOneWidget);
    });

    testWidgets('only an owner is offered Change role, and never for themselves', (t) async {
      await _open(t, const AdminsScreen(), prepare: (tools) {
        tools.admins
          ..clear()
          ..addAll(const [
            AdminAccount(uid: 'me', email: 'me@x.com', role: AdminRole.owner, you: true),
            AdminAccount(uid: 'a1', email: 'a1@x.com', role: AdminRole.admin),
            AdminAccount(uid: 'm1', email: 'm1@x.com', role: AdminRole.moderator),
          ]);
      });
      await _settle(t);
      expect(find.text('Change role'), findsNWidgets(2)); // a1 and m1, not me
      await t.pumpWidget(const SizedBox());

      await _open(t, const AdminsScreen(), role: AdminRole.admin, prepare: (tools) {
        tools.admins
          ..clear()
          ..addAll(team());
      });
      await _settle(t);
      expect(find.text('Change role'), findsNothing); // an admin cannot change roles
    });

    testWidgets('an owner changes a role from the sheet', (t) async {
      final rig = await _open(t, const AdminsScreen(), prepare: (tools) {
        tools.admins
          ..clear()
          ..addAll(const [
            AdminAccount(uid: 'me', email: 'me@x.com', role: AdminRole.owner, you: true),
            AdminAccount(uid: 'a1', email: 'a1@x.com', role: AdminRole.admin),
          ]);
      });
      await _settle(t);
      await t.tap(find.text('Change role'));
      await _settle(t);
      expect(find.text('CHANGE ROLE'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('role-moderator')));
      await _settle(t);
      expect(rig.tools.calls, ['set-role:a1:moderator']);
      expect(find.text('a1@x.com is now a moderator.'), findsOneWidget);
    });

    testWidgets('choosing the role someone already has changes nothing', (t) async {
      final rig = await _open(t, const AdminsScreen(), prepare: (tools) {
        tools.admins
          ..clear()
          ..addAll(const [
            AdminAccount(uid: 'me', email: 'me@x.com', role: AdminRole.owner, you: true),
            AdminAccount(uid: 'a1', email: 'a1@x.com', role: AdminRole.admin),
          ]);
      });
      await _settle(t);
      await t.tap(find.text('Change role'));
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('role-admin')));
      await _settle(t);
      expect(rig.tools.calls, isEmpty);
    });

    testWidgets('an admin cannot remove an owner (no Remove is offered)', (t) async {
      await _open(t, const AdminsScreen(), role: AdminRole.admin, prepare: (tools) {
        tools.admins
          ..clear()
          ..addAll(team());
      });
      await _settle(t);
      // owner@x.com has no Remove; mod@x.com does.
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('an owner can remove an owner', (t) async {
      await _open(t, const AdminsScreen(), prepare: (tools) {
        tools.admins
          ..clear()
          ..addAll(const [
            AdminAccount(uid: 'me', email: 'me@x.com', role: AdminRole.owner, you: true),
            AdminAccount(uid: 'o2', email: 'o2@x.com', role: AdminRole.owner),
          ]);
      });
      await _settle(t);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('the page explains what each role can do', (t) async {
      await _open(t, const AdminsScreen());
      await _settle(t);
      expect(find.text('WHAT EACH ROLE CAN DO'), findsOneWidget);
      expect(find.text('Everything, including other owners'), findsOneWidget);
      expect(find.text('Everything except managing owners'), findsWidgets);
    });
  });

  group('Moderation at scale', () {
    void seed(_Rig rig) {
      rig.tools.wishes.add([
        ModWish(_wish('w1', 'Quiet wish about a garden', luck: 2, hoursAgo: 1), hidden: false, authorUid: 'aaa111'),
        ModWish(_wish('w2', 'Spam: buy my stuff now', luck: 0, hoursAgo: 5), hidden: false, authorUid: 'bbb222'),
        ModWish(_wish('w3', 'A popular wish for travel', luck: 90, hoursAgo: 9, c: WishCategory.travel), hidden: false, authorUid: 'ccc333'),
        ModWish(_wish('w4', 'Hidden earlier', luck: 1, hoursAgo: 20), hidden: true, authorUid: 'bbb222'),
      ]);
      rig.tools.reports.add([
        WishReport(id: 'r1', wishId: 'w2', reason: 'Spam or links', at: DateTime.now().subtract(const Duration(hours: 4))),
        WishReport(id: 'r2', wishId: 'w2', reason: 'Unkind or harmful', at: DateTime.now().subtract(const Duration(hours: 2))),
        WishReport(id: 'r3', wishId: 'w3', reason: 'Other', at: DateTime.now().subtract(const Duration(hours: 1))),
      ]);
      rig.tools.blocked.add(const []);
    }

    Future<void> allWishes(WidgetTester t) async {
      await t.tap(find.text('All wishes'));
      await _settle(t);
    }

    testWidgets('search narrows the list by wish text, and says when nothing matches', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      await allWishes(t);
      expect(find.text('Quiet wish about a garden'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, 'garden');
      await _settle(t);
      expect(find.text('Quiet wish about a garden'), findsOneWidget);
      expect(find.text('A popular wish for travel'), findsNothing);

      await t.enterText(find.byType(TextField).first, 'zzzz');
      await _settle(t);
      expect(find.text('Nothing matches “zzzz”.'), findsOneWidget);
    });

    testWidgets('search also finds a person by the start of their id, and a report by its reason', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      await allWishes(t);
      await t.enterText(find.byType(TextField).first, 'bbb');
      await _settle(t);
      expect(find.text('Spam: buy my stuff now'), findsOneWidget);
      expect(find.text('Hidden earlier'), findsOneWidget); // same author
      expect(find.text('Quiet wish about a garden'), findsNothing);

      await t.enterText(find.byType(TextField).first, 'unkind');
      await _settle(t);
      expect(find.text('Spam: buy my stuff now'), findsOneWidget);
      expect(find.text('Hidden earlier'), findsNothing);
    });

    testWidgets('clearing the search brings everything back', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      await allWishes(t);
      await t.enterText(find.byType(TextField).first, 'garden');
      await _settle(t);
      await t.tap(find.text('Newest').first); // opens the sort sheet, unrelated to clear
      await _settle(t);
      await t.tap(find.text('Newest').last);
      await _settle(t);
      await t.tap(find.bySemanticsLabel('Clear search'), warnIfMissed: false);
      await t.enterText(find.byType(TextField).first, '');
      await _settle(t);
      expect(find.text('A popular wish for travel'), findsOneWidget);
    });

    testWidgets('sort by most reported puts the most reported first', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      await t.tap(find.text('Newest').first);
      await _settle(t);
      await t.tap(find.text('Most reported'));
      await _settle(t);
      final spam = t.getTopLeft(find.text('Spam: buy my stuff now')).dy;
      final popular = t.getTopLeft(find.text('A popular wish for travel')).dy;
      expect(spam, lessThan(popular)); // 2 reports against 1
    });

    testWidgets('sort by most luck puts the luckiest first', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      await allWishes(t);
      await t.tap(find.text('Newest').first);
      await _settle(t);
      await t.tap(find.text('Most luck'));
      await _settle(t);
      final popular = t.getTopLeft(find.text('A popular wish for travel')).dy;
      final quiet = t.getTopLeft(find.text('Quiet wish about a garden')).dy;
      expect(popular, lessThan(quiet)); // 90 luck against 2
    });

    testWidgets('newest is the default order', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      await allWishes(t);
      final quiet = t.getTopLeft(find.text('Quiet wish about a garden')).dy; // 1h ago
      final spam = t.getTopLeft(find.text('Spam: buy my stuff now')).dy; // 5h ago
      expect(quiet, lessThan(spam));
    });

    testWidgets('a report shows each reason and how long ago when opened', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      await t.tap(find.text('2 reports'));
      await _settle(t);
      expect(find.text('Spam or links'), findsOneWidget);
      expect(find.text('Unkind or harmful'), findsOneWidget);
      expect(find.text('4 hours ago'), findsOneWidget);
      expect(find.text('2 hours ago'), findsOneWidget);
    });

    testWidgets('hiding can be undone straight away', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      await t.tap(find.text('Hide').first);
      await _settle(t);
      expect(rig.tools.calls, ['hide:w3:true']);
      expect(find.text('Hidden.'), findsOneWidget);
      await t.tap(find.text('Undo'));
      await _settle(t);
      expect(rig.tools.calls, ['hide:w3:true', 'hide:w3:false']);
    });

    testWidgets('select several, then hide them in one action', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      await allWishes(t);
      await t.tap(find.text('Select'));
      await _settle(t);
      expect(find.text('Tap wishes to select them'), findsOneWidget);
      await t.tap(find.text('Quiet wish about a garden'));
      await t.tap(find.text('A popular wish for travel'));
      await _settle(t);
      expect(find.text('2 selected'), findsOneWidget);
      await t.tap(find.text('Hide'));
      await _settle(t);
      expect(rig.tools.calls, ['hide-many:w1+w3']);
      expect(find.text('2 wishes hidden.'), findsOneWidget);
    });

    testWidgets('select all, then dismiss the reports on the selection', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      await t.tap(find.text('Select'));
      await _settle(t);
      await t.tap(find.text('Select all 2'));
      await _settle(t);
      expect(find.text('2 selected'), findsOneWidget);
      await t.tap(find.text('Dismiss'));
      await _settle(t);
      expect(rig.tools.calls.single, startsWith('dismiss-for:'));
      expect(rig.tools.calls.single, allOf(contains('w2'), contains('w3')));
    });

    testWidgets('removing a selection asks why once, for all of them', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      await allWishes(t);
      await t.tap(find.text('Select'));
      await _settle(t);
      await t.tap(find.text('Spam: buy my stuff now'));
      await t.tap(find.text('Hidden earlier'));
      await _settle(t);
      await t.tap(find.text('Remove'));
      await _settle(t);
      expect(find.text('REMOVE 2 WISHES?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('reason-spam')));
      await t.pump();
      await t.tap(find.text('REMOVE 2 WISHES'));
      await _settle(t);
      expect(rig.tools.calls, ['remove-many:w2+w4:spam']);
    });

    testWidgets('leaving selection mode clears the selection', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      await allWishes(t);
      await t.tap(find.text('Select'));
      await _settle(t);
      await t.tap(find.text('Quiet wish about a garden'));
      await _settle(t);
      expect(find.text('1 selected'), findsOneWidget);
      await t.tap(find.text('Done'));
      await _settle(t);
      await t.tap(find.text('Select'));
      await _settle(t);
      expect(find.text('Tap wishes to select them'), findsOneWidget);
    });

    testWidgets('the actions on each card are hidden while selecting', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      expect(find.text('Block author'), findsWidgets);
      await t.tap(find.text('Select'));
      await _settle(t);
      expect(find.text('Block author'), findsNothing);
    });

    testWidgets('load more appears only when the list is full, and reads further', (t) async {
      final rig = await _open(t, const ModerationScreen());
      rig.tools.wishes.add([for (var i = 0; i < 200; i++) ModWish(_wish('w$i', 'Wish number $i', hoursAgo: i), hidden: false)]);
      rig.tools.reports.add(const []);
      rig.tools.blocked.add(const []);
      await _settle(t);
      await allWishes(t);
      expect(rig.tools.wishLimits, [200]);
      await _scrollTo(t, find.text('Load more wishes'));
      await t.tap(find.text('Load more wishes'));
      await _settle(t);
      expect(rig.tools.wishLimits, [200, 400]);
    });

    testWidgets('a short list has no load more', (t) async {
      final rig = await _open(t, const ModerationScreen());
      seed(rig);
      await _settle(t);
      await allWishes(t);
      expect(find.text('Load more wishes'), findsNothing);
    });

    testWidgets('the queue shows a skeleton until data arrives', (t) async {
      await _open(t, const ModerationScreen());
      expect(find.byType(AdminSkeleton), findsOneWidget);
    });
  });

  group('Overview over time', () {
    testWidgets('choosing a longer range reloads for that many days', (t) async {
      final rig = await _open(t, const OverviewScreen());
      await _settle(t);
      expect(rig.tools.lastOverviewDays, 14);
      await t.tap(find.text('30 days'));
      await _settle(t);
      expect(rig.tools.lastOverviewDays, 30);
      expect(find.text('LAST 30 DAYS'), findsOneWidget);
      await t.tap(find.text('7 days'));
      await _settle(t);
      expect(rig.tools.lastOverviewDays, 7);
    });

    testWidgets('a rise against the period before shows as an up arrow with the percentage', (t) async {
      await _open(t, const OverviewScreen());
      await _settle(t);
      expect(_trend('Up 25 percent compared with the previous period'), findsOneWidget); // 163 against 130
      expect(find.text('25%'), findsOneWidget);
    });

    testWidgets('a fall shows as a down arrow', (t) async {
      await _open(t, const OverviewScreen(), prepare: (tools) {
        tools.stats = OverviewStats(
          wishes: 10, hidden: 0, openReports: 0, luck: 0, blocked: 0, devices: 0, androidDevices: 0, iosDevices: 0,
          luckAlertDevices: 0, revisitDevices: 0, byCategory: const {},
          daily: [DailyCount(DateTime(2026, 11, 10), 50)],
          wishers: 10, windowLuck: 40, windowCapped: false,
          previous: const PeriodTotals(wishes: 100, wishers: 10, luck: 40),
        );
      });
      await _settle(t);
      expect(_trend('Down 50 percent compared with the previous period'), findsOneWidget); // 50 against 100
      expect(_trend('No change compared with the previous period'), findsNWidgets(2)); // people and luck
    });

    testWidgets('no arrow when the period before is empty, or too busy to read', (t) async {
      OverviewStats withPrevious(PeriodTotals? p) => OverviewStats(
            wishes: 10, hidden: 0, openReports: 0, luck: 0, blocked: 0, devices: 0, androidDevices: 0, iosDevices: 0,
            luckAlertDevices: 0, revisitDevices: 0, byCategory: const {},
            daily: [DailyCount(DateTime(2026, 11, 10), 5)],
            wishers: 3, windowLuck: 7, windowCapped: false, previous: p,
          );
      await _open(t, const OverviewScreen(), prepare: (tools) => tools.stats = withPrevious(const PeriodTotals(wishes: 0, wishers: 0, luck: 0)));
      await _settle(t);
      expect(_anyTrend(), findsNothing); // a rise from nothing is not a percentage
      await t.pumpWidget(const SizedBox());

      await _open(t, const OverviewScreen(), prepare: (tools) => tools.stats = withPrevious(null));
      await _settle(t);
      expect(_anyTrend(), findsNothing);
      expect(find.textContaining('Too busy to compare'), findsOneWidget);
    });

    testWidgets('open reports show how long the oldest has waited, and open the queue', (t) async {
      await _open(t, const OverviewScreen());
      await _settle(t);
      expect(find.text('3 reports waiting'), findsOneWidget);
      expect(find.text('The oldest has waited 30 hours.'), findsOneWidget);
      await t.tap(find.text('Review'));
      await _settle(t);
      expect(find.byType(ModerationScreen), findsOneWidget);
    });

    testWidgets('an empty queue says the Well is calm instead', (t) async {
      await _open(t, const OverviewScreen(), prepare: (tools) {
        tools.stats = OverviewStats(
          wishes: 1, hidden: 0, openReports: 0, luck: 0, blocked: 0, devices: 0, androidDevices: 0, iosDevices: 0,
          luckAlertDevices: 0, revisitDevices: 0, byCategory: const {},
          daily: [DailyCount(DateTime(2026, 11, 10), 1)],
          wishers: 1, windowLuck: 0, windowCapped: false,
        );
      });
      await _settle(t);
      expect(find.text('Nothing is waiting. The Well is calm.'), findsOneWidget);
      expect(find.text('Review'), findsNothing);
    });

    testWidgets('says when it was last updated', (t) async {
      await _open(t, const OverviewScreen());
      await _settle(t);
      await _scrollTo(t, find.textContaining('Updated '));
      expect(find.textContaining('Pull down or tap refresh'), findsOneWidget);
    });

    testWidgets('on a tablet the page stays a readable column', (t) async {
      await _open(t, const OverviewScreen(), size: const Size(1400, 1000));
      await _settle(t);
      expect(t.getSize(find.byType(ListView).first).width, lessThanOrEqualTo(760));
    });
  });

  group('Announcements with care', () {
    Future<void> fill(WidgetTester t, {String title = 'Gratitude circle', String body = 'Friday at 7pm.'}) async {
      await t.enterText(_field('announce-title'), title);
      await t.enterText(_field('announce-body'), body);
      await t.pump();
    }

    testWidgets('a live preview shows what is typed, and a placeholder before that', (t) async {
      await _open(t, const AnnouncementsScreen());
      await _settle(t);
      expect(find.text('Your title'), findsOneWidget);
      expect(find.text('Your message will look like this.'), findsOneWidget);
      await fill(t);
      expect(find.text('Your title'), findsNothing);
      expect(find.text('MANIFESTWELL'), findsOneWidget);
      expect(find.descendant(of: find.byType(ListView), matching: find.text('Friday at 7pm.')), findsWidgets);
    });

    testWidgets('says how many phones it would reach, and changes with the audience', (t) async {
      await _open(t, const AnnouncementsScreen());
      await _settle(t);
      expect(find.text('Reaches about 410 phones.'), findsOneWidget);
      await t.tap(find.text('Android'));
      await _settle(t);
      expect(find.text('Reaches about 250 phones.'), findsOneWidget);
      await t.tap(find.text('iPhone'));
      await _settle(t);
      expect(find.text('Reaches about 160 phones.'), findsOneWidget);
    });

    testWidgets('warns when nobody would get it', (t) async {
      await _open(t, const AnnouncementsScreen(), prepare: (tools) => tools.reach[Audience.all] = 0);
      await _settle(t);
      expect(find.textContaining('nobody would get this'), findsOneWidget);
    });

    testWidgets('one phone is "1 phone", not "1 phones"', (t) async {
      await _open(t, const AnnouncementsScreen(), prepare: (tools) => tools.reach[Audience.all] = 1);
      await _settle(t);
      expect(find.text('Reaches about 1 phone.'), findsOneWidget);
    });

    testWidgets('the confirmation names the number of phones', (t) async {
      await _open(t, const AnnouncementsScreen());
      await _settle(t);
      await fill(t);
      await t.tap(find.text('SEND'));
      await _settle(t);
      // The page says "Reaches about 410 phones." and so does the confirmation.
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.textContaining('about 410 phones')),
          findsOneWidget);
    });

    testWidgets('a test goes to the admin\'s own phone only', (t) async {
      final rig = await _open(t, const AnnouncementsScreen());
      await _settle(t);
      await fill(t);
      await t.tap(find.text('Send me a test'));
      await _settle(t);
      expect(rig.tools.calls, ['announce-test:Gratitude circle:Friday at 7pm.']);
      expect(rig.tools.calls.where((c) => c.startsWith('announce:')), isEmpty); // nobody else was told
      expect(find.text('Test sent to 1 of your phone.'), findsOneWidget);
    });

    testWidgets('a test needs a title and message first', (t) async {
      final rig = await _open(t, const AnnouncementsScreen());
      await _settle(t);
      await t.tap(find.text('Send me a test'));
      await _settle(t);
      expect(rig.tools.calls, isEmpty);
    });

    testWidgets('a test explains when this account has no phone with notifications on', (t) async {
      final rig = await _open(t, const AnnouncementsScreen(), prepare: (tools) => tools.testPhones = 0);
      await _settle(t);
      await fill(t);
      await t.tap(find.text('Send me a test'));
      await _settle(t);
      expect(find.textContaining('no phone with notifications on'), findsOneWidget);
      expect(rig.tools.calls.where((c) => c.startsWith('announce:')), isEmpty);
    });

    testWidgets('after sending, Send is locked so a double tap cannot notify everyone twice', (t) async {
      final rig = await _open(t, const AnnouncementsScreen());
      await _settle(t);
      await fill(t);
      await t.tap(find.text('SEND'));
      await _settle(t);
      await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('SEND')));
      await _settle(t);
      expect(rig.tools.calls.where((c) => c.startsWith('announce:')).length, 1);

      // Typed again at once: still locked, and says for how long.
      await fill(t, title: 'Second', body: 'Again');
      expect(find.textContaining('SENT. WAIT'), findsOneWidget);
      await t.tap(find.textContaining('SENT. WAIT'));
      await _settle(t);
      expect(find.byType(BottomSheet), findsNothing);
      expect(rig.tools.calls.where((c) => c.startsWith('announce:')).length, 1);

      // A minute later it is free again.
      await t.pump(const Duration(seconds: 61));
      expect(find.text('SEND'), findsOneWidget);
      expect(find.textContaining('SENT. WAIT'), findsNothing);
    });

    testWidgets('a failed send does not lock anything', (t) async {
      final rig = await _open(t, const AnnouncementsScreen());
      await _settle(t);
      await fill(t);
      rig.tools.failActions = true;
      await t.tap(find.text('SEND'));
      await _settle(t);
      await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('SEND')));
      await _settle(t);
      expect(find.textContaining('SENT. WAIT'), findsNothing);
      expect(find.text('SEND'), findsOneWidget);
    });
  });

  group('Controls with care', () {
    testWidgets('leaving with unsaved changes asks first, and can be cancelled', (t) async {
      await _open(t, const _Launcher(ControlsScreen()));
      await t.tap(find.text('open page'));
      await _settle(t);
      await t.enterText(_field('field-banner'), 'Draft banner');
      await t.pump();
      expect(find.text('You have unsaved changes.'), findsOneWidget);

      await t.tap(_iconButton('Back'));
      await _settle(t);
      expect(find.text('DISCARD YOUR CHANGES?'), findsNothing); // dialog title is not upper-cased
      expect(find.text('Discard your changes?'), findsOneWidget);
      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(t);
      expect(find.byType(ControlsScreen), findsOneWidget); // still here
      expect(_typedIn('field-banner', 'Draft banner'), findsOneWidget); // and still typed
    });

    testWidgets('discarding leaves', (t) async {
      await _open(t, const _Launcher(ControlsScreen()));
      await t.tap(find.text('open page'));
      await _settle(t);
      await t.enterText(_field('field-banner'), 'Draft banner');
      await t.pump();
      await t.tap(_iconButton('Back'));
      await _settle(t);
      await t.tap(find.widgetWithText(TextButton, 'Discard'));
      await _settle(t);
      expect(find.byType(ControlsScreen), findsNothing);
      expect(find.text('open page'), findsOneWidget);
    });

    testWidgets('with nothing changed, back just goes back', (t) async {
      await _open(t, const _Launcher(ControlsScreen()));
      await t.tap(find.text('open page'));
      await _settle(t);
      await t.tap(_iconButton('Back'));
      await _settle(t);
      expect(find.byType(ControlsScreen), findsNothing);
      expect(find.text('Discard your changes?'), findsNothing);
    });

    testWidgets('after saving, leaving no longer asks', (t) async {
      await _open(t, const _Launcher(ControlsScreen()));
      await t.tap(find.text('open page'));
      await _settle(t);
      await t.enterText(_field('field-banner'), 'Saved banner');
      await t.pump();
      await t.tap(find.text('SAVE CHANGES'));
      await _settle(t);
      expect(find.text('You have unsaved changes.'), findsNothing);
      await t.tap(_iconButton('Back'));
      await _settle(t);
      expect(find.byType(ControlsScreen), findsNothing);
    });

    testWidgets('the banner preview follows what is typed', (t) async {
      await _open(t, const ControlsScreen());
      await _settle(t);
      expect(find.text('Nothing shows at the top of the Well.'), findsOneWidget);
      await t.enterText(_field('field-banner'), 'Circle on Friday');
      await t.pump();
      expect(find.text('Nothing shows at the top of the Well.'), findsNothing);
      expect(find.text('Circle on Friday'), findsNWidgets(2)); // the field and the preview
    });

    testWidgets('pausing previews the paused notice, with the banner beneath', (t) async {
      await _open(t, const ControlsScreen());
      await _settle(t);
      await t.enterText(_field('field-banner'), 'Back soon');
      await t.tap(find.byKey(const ValueKey('switch-pause')));
      await t.pump();
      expect(find.textContaining('New wishes are paused for a little while'), findsOneWidget);
      expect(find.text('Back soon'), findsNWidgets(2));
    });

    testWidgets('shows when the controls were last changed', (t) async {
      SharedPreferences.setMockInitialValues({});
      final backend = FakeWellBackend(account: 'boss@example.com')..admin = true;
      final state = await AppState.load(backend: backend);
      backend.configFeed.add(AppConfig(banner: 'x', updatedAt: DateTime(2026, 1, 5, 9, 5)));
      await t.pump();
      await t.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: MW.theme(), home: const ControlsScreen()),
      ));
      await _settle(t);
      expect(find.text('Last changed Jan 5, 09:05.'), findsOneWidget);
    });
  });

  group('Activity at scale', () {
    List<AdminLogEntry> entries() => [
          AdminLogEntry(id: '1', action: 'block', detail: 'person abc; 3 wishes hidden. Reason: Spam or links', by: 'boss@x.com', at: DateTime(2026, 10, 27)),
          AdminLogEntry(id: '2', action: 'remove', detail: 'wish w9; 1 report cleared. Reason: Harassment', by: 'mod@x.com', at: DateTime(2026, 10, 26)),
          AdminLogEntry(id: '3', action: 'announce', detail: '"Hello" to Everyone', by: 'boss@x.com', at: DateTime(2026, 10, 25)),
          AdminLogEntry(id: '4', action: 'grant', detail: 'Plus (month) given to ada@x.com', by: 'boss@x.com', at: DateTime(2026, 10, 24)),
          AdminLogEntry(id: '5', action: 'admin-role', detail: 'mod@x.com: admin to moderator', by: 'boss@x.com', at: DateTime(2026, 10, 23)),
          AdminLogEntry(id: '6', action: 'announce-test', detail: '"Hello" test to 1 phone(s)', by: 'boss@x.com', at: DateTime(2026, 10, 22)),
        ];

    testWidgets('filter by kind of action', (t) async {
      final rig = await _open(t, const ActivityScreen());
      rig.tools.log.add(entries());
      await _settle(t);
      expect(find.text('Blocked a person'), findsOneWidget);
      expect(find.text('Removed wishes'), findsOneWidget);

      await t.tap(find.text('People'));
      await _settle(t);
      expect(find.text('Blocked a person'), findsOneWidget);
      expect(find.text('Removed wishes'), findsNothing);

      await t.tap(find.text('Announcements'));
      await _settle(t);
      expect(find.text('Sent an announcement'), findsOneWidget);
      expect(find.text('Sent a test announcement'), findsOneWidget);
      expect(find.text('Blocked a person'), findsNothing);

      await t.tap(find.text('All'));
      await _settle(t);
      expect(find.text('Blocked a person'), findsOneWidget);
    });

    testWidgets('search by who, what or why', (t) async {
      final rig = await _open(t, const ActivityScreen());
      rig.tools.log.add(entries());
      await _settle(t);
      await t.enterText(find.byType(TextField).first, 'harassment'); // a reason in the detail
      await _settle(t);
      expect(find.text('Removed wishes'), findsOneWidget);
      expect(find.text('Blocked a person'), findsNothing);

      await t.enterText(find.byType(TextField).first, 'mod@x.com'); // who
      await _settle(t);
      expect(find.text('Removed wishes'), findsOneWidget);
      expect(find.text('Changed an admin’s role'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, 'zzz');
      await _settle(t);
      expect(find.text('Nothing matches “zzz”.'), findsOneWidget);
    });

    testWidgets('the reason given for a removal or block is on record', (t) async {
      final rig = await _open(t, const ActivityScreen());
      rig.tools.log.add(entries());
      await _settle(t);
      expect(find.textContaining('Reason: Spam or links'), findsOneWidget);
      expect(find.textContaining('Reason: Harassment'), findsOneWidget);
    });

    testWidgets('a kind with no entries says so', (t) async {
      final rig = await _open(t, const ActivityScreen());
      rig.tools.log.add([entries().first]);
      await _settle(t);
      // The filters scroll sideways; this one starts off the edge of the screen.
      await t.ensureVisible(find.text('Controls'));
      await t.pump();
      await t.tap(find.text('Controls'));
      await _settle(t);
      expect(find.text('Nothing of that kind yet.'), findsOneWidget);
    });

    testWidgets('load older appears only when a full page was read', (t) async {
      final rig = await _open(t, const ActivityScreen());
      rig.tools.log.add([
        for (var i = 0; i < 100; i++)
          AdminLogEntry(id: '$i', action: 'hide', detail: 'wish w$i', by: 'boss@x.com', at: DateTime(2026, 10, 1).add(Duration(minutes: i))),
      ]);
      await _settle(t);
      expect(rig.tools.logLimits, [100]);
      await _scrollTo(t, find.text('Load older activity'));
      await t.tap(find.text('Load older activity'));
      await _settle(t);
      expect(rig.tools.logLimits, [100, 200]);
    });

    testWidgets('a short log has no load older', (t) async {
      final rig = await _open(t, const ActivityScreen());
      rig.tools.log.add(entries());
      await _settle(t);
      expect(find.text('Load older activity'), findsNothing);
    });
  });
}
