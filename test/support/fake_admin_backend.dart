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

  OverviewStats? stats;
  Object? overviewError;
  AppConfig? savedConfig;
  final exports = <AdminExport>[];

  void _act(String call) {
    if (failActions) throw StateError('offline');
    calls.add(call);
  }

  @override
  Stream<List<ModWish>> watchAllWishes() => wishes.stream;
  @override
  Stream<List<WishReport>> watchReports() => reports.stream;
  @override
  Future<void> setHidden(String wishId, bool hidden) async => _act('hide:$wishId:$hidden');
  @override
  Future<void> removeWish(String wishId) async => _act('remove:$wishId');
  @override
  Future<void> dismissReports(String wishId, List<String> reportIds) async =>
      _act('dismiss:$wishId:${reportIds.join('+')}');

  @override
  Stream<List<BlockedPerson>> watchBlocked() => blocked.stream;
  @override
  Future<void> block(String uid, {String reason = ''}) async => _act('block:$uid');
  @override
  Future<void> unblock(String uid) async => _act('unblock:$uid');

  // ---- Admins ----------------------------------------------------------------

  final admins = <AdminAccount>[
    const AdminAccount(uid: 'owner-uid-1', email: 'boss@braidstribe.com', owner: true, you: true),
    const AdminAccount(uid: 'helper-uid-2', email: 'helper@braidstribe.com'),
  ];

  /// Emails that have an account; anything else is "no account".
  final knownEmails = <String>{'new@braidstribe.com'};

  @override
  Future<List<AdminAccount>> listAdmins() async {
    if (failActions) throw StateError('offline');
    return List.of(admins);
  }

  @override
  Future<void> addAdmin(String email) async {
    _act('add-admin:$email');
    if (!knownEmails.contains(email)) {
      throw const AdminActionException('No account has that email. They need to sign in to the app first.');
    }
    admins.add(AdminAccount(uid: 'uid-$email', email: email));
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

  @override
  Future<OverviewStats> loadOverview({DateTime? now, int days = 14}) async {
    if (overviewError != null) throw overviewError!;
    return stats ?? sampleStats();
  }

  @override
  Future<void> saveConfig(AppConfig config) async {
    _act('config');
    savedConfig = config;
  }

  @override
  Stream<List<Announcement>> watchAnnouncements() => announcements.stream;
  @override
  Future<void> sendAnnouncement({required String title, required String body, required Audience audience}) async =>
      _act('announce:${audience.id}:$title:$body');

  @override
  Stream<List<AdminLogEntry>> watchLog() => log.stream;

  @override
  Future<String> exportCsv(AdminExport what) async {
    exports.add(what);
    return 'a,b\r\n1,2\r\n';
  }
}

OverviewStats sampleStats({int days = 14}) => OverviewStats(
      wishes: 1284,
      hidden: 6,
      openReports: 3,
      luck: 9120,
      blocked: 2,
      devices: 410,
      androidDevices: 250,
      iosDevices: 160,
      luckAlertDevices: 380,
      revisitDevices: 290,
      plusMembers: 57,
      byCategory: {
        WishCategory.career: 410,
        WishCategory.love: 380,
        WishCategory.health: 240,
        WishCategory.travel: 150,
        WishCategory.home: 104,
      },
      daily: [
        for (var i = 0; i < days; i++) DailyCount(DateTime(2026, 10, 28 + i), [4, 9, 6, 12, 8, 15, 11, 7, 14, 18, 9, 13, 21, 16][i % 14]),
      ],
      wishers: 96,
      windowLuck: 840,
      windowCapped: false,
    );
