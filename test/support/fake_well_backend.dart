import 'dart:async';

import 'package:manifestwell/models/admin.dart';
import 'package:manifestwell/models/wish.dart';
import 'package:manifestwell/state/admin_backend.dart';
import 'package:manifestwell/state/well_backend.dart';

import 'fake_admin_backend.dart';

/// An in-memory stand-in for Firestore so screens can be driven in tests.
class FakeWellBackend implements WellBackend {
  FakeWellBackend({this.account});

  String? account;
  bool admin = false;
  bool deleteAnswer = true;
  final cloud = <String, Wish>{};

  @override
  String? get accountLabel => account;

  @override
  String? get accountId => account == null ? null : 'uid-$account';

  @override
  Stream<List<Wish>> watchWell() => const Stream.empty();
  @override
  Future<void> publish(Wish wish) async {}
  @override
  Future<void> sendLuck(String wishId) async {}
  @override
  Future<void> withdraw(String wishId) async {}
  @override
  Future<void> report(String wishId, String reason) async {}

  /// Device records as the server would hold them, keyed by token.
  final devices = <String, ({String? uid, bool luck, bool revisit, String tz})>{};

  @override
  Future<void> registerDevice({
    required String token,
    required String platform,
    required String timezone,
    required bool luckAlerts,
    required bool revisitNudges,
  }) async =>
      devices[token] = (uid: accountId, luck: luckAlerts, revisit: revisitNudges, tz: timezone);

  @override
  Future<void> unregisterDevice(String token) async => devices.remove(token);

  @override
  Future<List<Wish>> fetchMyWishes() async => cloud.values.toList();
  @override
  Future<void> saveMyWish(Wish wish) async => cloud[wish.id] = wish;
  @override
  Stream<Map<String, int>> watchMyLuck() => const Stream.empty();

  @override
  Future<bool> signInWithGoogle() async {
    account = 'ada@example.com';
    return true;
  }

  @override
  Future<bool> signInWithApple() async => false;
  @override
  Future<void> signOut() async => account = null;
  @override
  Future<bool> deleteAccount() async {
    if (!deleteAnswer) return false;
    cloud.clear();
    account = null;
    return true;
  }

  @override
  Future<bool> checkAdmin() async => admin;
  @override
  Future<bool> signInAdmin(String email, String password) async => admin;
  /// What the dashboard talks to. Tests that open admin screens use this.
  final tools = FakeAdminBackend();
  @override
  AdminBackend? get adminTools => tools;
  /// Pushes a change in the account's admin status, as the live record would.
  final adminFeed = StreamController<bool>.broadcast();
  @override
  Stream<bool> watchAdmin() => adminFeed.stream;
  final grantFeed = StreamController<PlusGrant?>.broadcast();
  @override
  Stream<PlusGrant?> watchPlusGrant() => grantFeed.stream;
  final configFeed = StreamController<AppConfig>.broadcast();
  @override
  Stream<AppConfig> watchConfig() => configFeed.stream;
}
