import 'dart:async';

import 'package:manifestwell/models/admin.dart';
import 'package:manifestwell/models/moderation.dart';
import 'package:manifestwell/models/wish.dart';
import 'package:manifestwell/state/admin_backend.dart';

/// Stands in for Firestore on the dashboard. Streams are pushed by the test;
/// every action is recorded in [calls] so a test can check what was asked for.
class FakeAdminBackend implements AdminBackend {
  final wishes = StreamController<List<ModWish>>.broadcast();
  final reports = StreamController<List<WishReport>>.broadcast();
  final blocked = StreamController<List<BlockedPerson>>.broadcast();
  final announcements = StreamController<List<Announcement>>.broadcast();
  final log = StreamController<List<AdminLogEntry>>.broadcast();
  final calls = <String>[];

  /// Make every action fail, as if the phone were offline.
  bool failActions = false;

  /// The limits the screens asked for, in order, to check "load more".
  final wishLimits = <int>[];
  final logLimits = <int>[];

  OverviewStats? stats;
  Object? overviewError;
  int? lastOverviewDays;
  bool? lastIncludeReach;
  AppConfig? savedConfig;
  final exports = <AdminExport>[];

  void _act(String call) {
    if (failActions) throw StateError('offline');
    calls.add(call);
  }

  // ---- Moderation --------------------------------------------------------------

  @override
  Stream<List<ModWish>> watchAllWishes({int limit = 200}) {
    wishLimits.add(limit);
    return wishes.stream;
  }

  @override
  Stream<List<WishReport>> watchReports({int limit = 200}) => reports.stream;
  @override
  Future<void> setHidden(String wishId, bool hidden) async => _act('hide:$wishId:$hidden');
  @override
  Future<void> setHiddenMany(List<String> wishIds, bool hidden) async =>
      _act('${hidden ? 'hide' : 'restore'}-many:${wishIds.join('+')}');
  @override
  Future<void> removeWish(String wishId, {required ModerationReason reason, String note = ''}) async =>
      _act('remove:$wishId:${reason.name}${note.isEmpty ? '' : ':$note'}');
  @override
  Future<void> removeWishes(List<String> wishIds, {required ModerationReason reason, String note = ''}) async =>
      _act('remove-many:${wishIds.join('+')}:${reason.name}${note.isEmpty ? '' : ':$note'}');
  @override
  Future<void> dismissReports(String wishId, List<String> reportIds) async =>
      _act('dismiss:$wishId:${reportIds.join('+')}');
  @override
  Future<void> dismissReportsFor(List<String> wishIds) async => _act('dismiss-for:${wishIds.join('+')}');

  @override
  Stream<List<BlockedPerson>> watchBlocked() => blocked.stream;
  @override
  Future<void> block(String uid, {required ModerationReason reason, String note = ''}) async =>
      _act('block:$uid:${reason.name}${note.isEmpty ? '' : ':$note'}');
  @override
  Future<void> unblock(String uid) async => _act('unblock:$uid');

  // ---- Admins ----------------------------------------------------------------

  final admins = <AdminAccount>[
    const AdminAccount(uid: 'owner-uid-1', email: 'boss@braidstribe.com', role: AdminRole.owner, you: true),
    const AdminAccount(uid: 'helper-uid-2', email: 'helper@braidstribe.com'),
    const AdminAccount(uid: 'mod-uid-3', email: 'mod@braidstribe.com', role: AdminRole.moderator),
  ];

  /// Emails that have an account; anything else is "no account".
  final knownEmails = <String>{'new@braidstribe.com'};

  @override
  Future<List<AdminAccount>> listAdmins() async {
    if (failActions) throw StateError('offline');
    return List.of(admins);
  }

  @override
  Future<void> addAdmin(String email, {AdminRole role = AdminRole.admin}) async {
    _act('add-admin:$email:${role.id}');
    if (!knownEmails.contains(email)) {
      throw const AdminActionException('No account has that email. They need to sign in to the app first.');
    }
    admins.add(AdminAccount(uid: 'uid-$email', email: email, role: role));
  }

  @override
  Future<void> setAdminRole(String uid, AdminRole role) async {
    final i = admins.indexWhere((a) => a.uid == uid);
    if (admins[i].you) throw const AdminActionException('You cannot change your own role.');
    _act('set-role:$uid:${role.id}');
    final old = admins[i];
    admins[i] = AdminAccount(uid: old.uid, email: old.email, role: role, you: old.you);
  }

  @override
  Future<void> removeAdmin(String uid) async {
    final target = admins.firstWhere((a) => a.uid == uid);
    if (target.you) throw const AdminActionException('You cannot remove yourself.');
    _act('remove-admin:$uid');
    admins.remove(target);
  }

  // ---- Subscriptions -----------------------------------------------------------

  final subscribers = StreamController<List<SubscriberRecord>>.broadcast();

  /// What a lookup returns, by email. Anything else is "no account".
  final people = <String, SubscriberDetail>{};

  SubscriberDetail _known(String query) =>
      people[query] ?? (throw const AdminActionException('No account has that email. They need to sign in to the app first.'));

  @override
  Stream<List<SubscriberRecord>> watchSubscribers() => subscribers.stream;

  @override
  Future<SubscriberDetail> lookupSubscriber(String query) async {
    _act('lookup:$query');
    return _known(query);
  }

  @override
  Future<SubscriberDetail> grantPlus(String uid, GrantLength length) async {
    _act('grant:$uid:${length.id}');
    final old = people.values.firstWhere((p) => p.uid == uid);
    final next = SubscriberDetail(
      uid: uid,
      email: old.email,
      purchaseActive: old.purchaseActive,
      purchaseExpiresAt: old.purchaseExpiresAt,
      store: old.store,
      grantActive: true,
      grantLifetime: length == GrantLength.lifetime,
      grantExpiresAt: length == GrantLength.lifetime ? null : DateTime(2027, 1, 5),
    );
    people[old.email] = next;
    return next;
  }

  @override
  Future<SubscriberDetail> revokeGivenPlus(String uid) async {
    _act('revoke:$uid');
    final old = people.values.firstWhere((p) => p.uid == uid);
    // Only the gift goes; a purchase is left exactly as it was.
    final next = SubscriberDetail(
      uid: uid,
      email: old.email,
      purchaseActive: old.purchaseActive,
      purchaseExpiresAt: old.purchaseExpiresAt,
      store: old.store,
    );
    people[old.email] = next;
    return next;
  }

  // ---- Overview ----------------------------------------------------------------

  @override
  Future<OverviewStats> loadOverview({DateTime? now, int days = 14, bool includeReach = true}) async {
    lastOverviewDays = days;
    lastIncludeReach = includeReach;
    if (overviewError != null) throw overviewError!;
    return stats ?? sampleStats(days: days, includeReach: includeReach);
  }

  // ---- Controls ----------------------------------------------------------------

  @override
  Future<void> saveConfig(AppConfig config) async {
    _act('config');
    savedConfig = config;
  }

  // ---- Announcements -------------------------------------------------------------

  /// How many phones each audience would reach.
  final reach = <Audience, int>{Audience.all: 410, Audience.android: 250, Audience.ios: 160};

  /// How many of the admin's own phones have notifications on (0 = none).
  int testPhones = 1;

  @override
  Stream<List<Announcement>> watchAnnouncements() => announcements.stream;

  @override
  Future<int> estimateReach(Audience audience) async => reach[audience] ?? 0;

  @override
  Future<int> sendTestAnnouncement({required String title, required String body}) async {
    _act('announce-test:$title:$body');
    if (testPhones == 0) {
      throw const AdminActionException('This account has no phone with notifications on. Turn them on in Settings first.');
    }
    return testPhones;
  }

  @override
  Future<void> sendAnnouncement({required String title, required String body, required Audience audience}) async =>
      _act('announce:${audience.id}:$title:$body');

  // ---- Activity & export -----------------------------------------------------------

  @override
  Stream<List<AdminLogEntry>> watchLog({int limit = 100}) {
    logLimits.add(limit);
    return log.stream;
  }

  @override
  Future<String> exportCsv(AdminExport what) async {
    exports.add(what);
    return 'a,b\r\n1,2\r\n';
  }
}

OverviewStats sampleStats({int days = 14, bool includeReach = true}) => OverviewStats(
      wishes: 1284,
      hidden: 6,
      openReports: 3,
      luck: 9120,
      blocked: 2,
      devices: includeReach ? 410 : 0,
      androidDevices: includeReach ? 250 : 0,
      iosDevices: includeReach ? 160 : 0,
      luckAlertDevices: includeReach ? 380 : 0,
      revisitDevices: includeReach ? 290 : 0,
      plusMembers: includeReach ? 57 : 0,
      byCategory: {
        WishCategory.career: 410,
        WishCategory.love: 380,
        WishCategory.health: 240,
        WishCategory.travel: 150,
        WishCategory.home: 104,
      },
      daily: [
        for (var i = 0; i < days; i++)
          DailyCount(DateTime(2026, 11, 1).add(Duration(days: i)), [4, 9, 6, 12, 8, 15, 11, 7, 14, 18, 9, 13, 21, 16][i % 14]),
      ],
      wishers: 96,
      windowLuck: 840,
      windowCapped: false,
      // 163 wishes now against 130 before: up 25%.
      previous: const PeriodTotals(wishes: 130, wishers: 80, luck: 900),
      oldestOpenReport: DateTime.now().subtract(const Duration(hours: 30)),
      includesReach: includeReach,
    );
