import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:manifestwell/models/admin.dart';
import 'package:manifestwell/models/wish.dart';
import 'package:manifestwell/state/admin_backend.dart';
import 'package:manifestwell/state/app_state.dart';
import 'package:manifestwell/state/reminders.dart';
import 'package:manifestwell/utils/haptics.dart';
import 'package:manifestwell/state/well_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fakes.dart';

class _FakeBackend implements WellBackend {
  final feed = StreamController<List<Wish>>.broadcast();
  final published = <String>[];
  final luck = <String>[];
  final withdrawn = <String>[];

  @override
  Stream<List<Wish>> watchWell() => feed.stream;
  @override
  Future<void> publish(Wish wish) async => published.add(wish.id);
  @override
  Future<void> sendLuck(String wishId) async => luck.add(wishId);
  @override
  Future<void> withdraw(String wishId) async => withdrawn.add(wishId);
  final reports = <String>[];
  final cloud = <String, Wish>{};
  final saves = <String>[];
  final myLuck = StreamController<Map<String, int>>.broadcast();
  var admin = false;

  var deleteAnswer = true;
  var failSaves = false;
  @override
  Future<bool> deleteAccount() async {
    if (!deleteAnswer) return false;
    cloud.clear();
    account = null;
    return true;
  }
  final devices = <String, ({bool luck, bool revisit, String tz})>{};
  var failRegister = false;
  @override
  Future<void> registerDevice({
    required String token,
    required String platform,
    required String timezone,
    required bool luckAlerts,
    required bool revisitNudges,
  }) async {
    if (failRegister) throw StateError('offline');
    devices[token] = (luck: luckAlerts, revisit: revisitNudges, tz: timezone);
  }
  @override
  Future<void> unregisterDevice(String token) async => devices.remove(token);
  @override
  Future<List<Wish>> fetchMyWishes() async => cloud.values.toList();
  @override
  Future<void> saveMyWish(Wish wish) async {
    if (failSaves) throw StateError('offline');
    cloud[wish.id] = wish;
    saves.add(wish.id);
  }
  @override
  Stream<Map<String, int>> watchMyLuck() => myLuck.stream;
  @override
  Future<void> report(String wishId, String reason) async => reports.add(wishId);
  @override
  Future<bool> checkAdmin() async => admin;
  @override
  Future<bool> signInAdmin(String email, String password) async => admin = password == 'right';
  @override
  Future<void> signOut() async {
    admin = false;
    account = null;
  }
  String? account;
  @override
  String? get accountLabel => account;
  @override
  String? get accountId => account == null ? null : 'uid-$account';
  @override
  Future<bool> signInWithGoogle() async {
    account = 'a@b.c';
    return true;
  }
  @override
  Future<bool> signInWithApple() async => false;
  @override
  AdminBackend? get adminTools => null;
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

class _FakeReminders implements Reminders {
  bool allow = true;
  final log = <String>[];

  @override
  Future<bool> requestPermission() async => allow;
  @override
  Future<void> schedule({required int hour, required int minute}) async => log.add('schedule $hour:$minute');
  @override
  Future<void> cancel() async => log.add('cancel');
}

void main() {
  late _FakeBackend backend;
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = _FakeBackend();
    var tick = 0;
    state = await AppState.load(
      now: () => DateTime(2026, 10, 27, 12).add(Duration(seconds: tick++)),
      backend: backend,
    );
  });

  Wish remote(String id, int luck) => Wish(
        id: id,
        text: 'A wish from someone else',
        kind: WishKind.big,
        category: WishCategory.love,
        createdAt: DateTime(2026, 10, 27, 11),
        luck: luck,
      );

  test('remote wishes appear in the feed with the server luck count', () async {
    backend.feed.add([remote('r1', 7)]);
    await pumpEventQueue();
    expect(state.feed.firstWhere((w) => w.id == 'r1').luck, 7);
  });

  test('sending luck calls the backend once and does not double count', () async {
    backend.feed.add([remote('r1', 7)]);
    await pumpEventQueue();
    expect(await state.sendLuck('r1'), isTrue);
    expect(await state.sendLuck('r1'), isFalse);
    expect(backend.luck, ['r1']);
    expect(state.feed.firstWhere((w) => w.id == 'r1').luck, 7);
  });

  test('seed luck stays local and never reaches the backend', () async {
    final seed = state.feed.firstWhere((w) => w.isSeed);
    await state.sendLuck(seed.id);
    expect(backend.luck, isEmpty);
    expect(state.feed.firstWhere((w) => w.id == seed.id).luck, seed.luck + 1);
  });

  test('only Big Wishes are published; resolving withdraws them', () async {
    final spark = await state.cast('Found a parking spot', WishKind.spark, WishCategory.daily);
    final big = await state.cast('A calm new home', WishKind.big, WishCategory.home);
    expect(backend.published, [big!.id]);
    expect(backend.published, isNot(contains(spark!.id)));
    await state.resolve(big.id, WishStatus.granted);
    expect(backend.withdrawn, [big.id]);
  });

  test('a wish still being held stays in the Well', () async {
    final big = await state.cast('A calm new home', WishKind.big, WishCategory.home);
    await state.resolve(big!.id, WishStatus.closer);
    expect(backend.withdrawn, isEmpty);
  });

  test('reporting reaches the backend', () async {
    await state.report('r1', 'Spam');
    expect(backend.reports, ['r1']);
  });

  test('admin sign-in only succeeds with an admin account', () async {
    expect(state.isAdmin, isFalse);
    expect(await state.signInAdmin('a@b.c', 'wrong'), isFalse);
    expect(state.isAdmin, isFalse);
    expect(await state.signInAdmin('a@b.c', 'right'), isTrue);
    expect(state.isAdmin, isTrue);
    await state.signOut();
    expect(state.isAdmin, isFalse);
  });

  test('the admin settings reach the app as they change', () async {
    expect(state.wishingPaused, isFalse);
    expect(state.config.banner, isEmpty);
    backend.configFeed.add(const AppConfig(wishingPaused: true, banner: 'Back soon', blockedTerms: ['spam']));
    await pumpEventQueue();
    expect(state.wishingPaused, isTrue);
    expect(state.config.banner, 'Back soon');
    expect(state.config.blockedTerms, ['spam']);
    backend.configFeed.add(AppConfig.defaults);
    await pumpEventQueue();
    expect(state.wishingPaused, isFalse);
  });

  group('Plus given by an admin', () {
    final t0 = DateTime(2026, 10, 27, 12);

    test('a gift makes the account Plus, and the free limit stops applying', () async {
      expect(state.isPro, isFalse);
      await state.cast('First', WishKind.big, WishCategory.home);
      expect(state.canCastBigWish, isFalse); // the free limit

      backend.grantFeed.add(PlusGrant(until: t0.add(const Duration(days: 30))));
      await pumpEventQueue();
      expect(state.isPro, isTrue);
      expect(state.canCastBigWish, isTrue);
    });

    test('a lifetime gift never runs out', () async {
      backend.grantFeed.add(const PlusGrant(lifetime: true));
      await pumpEventQueue();
      expect(state.isPro, isTrue);
    });

    test('a gift that has run out gives nothing', () async {
      backend.grantFeed.add(PlusGrant(until: t0.subtract(const Duration(days: 1))));
      await pumpEventQueue();
      expect(state.isPro, isFalse);
    });

    test('taking the gift back ends it', () async {
      backend.grantFeed.add(const PlusGrant(lifetime: true));
      await pumpEventQueue();
      expect(state.isPro, isTrue);
      backend.grantFeed.add(null);
      await pumpEventQueue();
      expect(state.isPro, isFalse);
    });

    test('a purchase still counts when there is no gift', () async {
      final s = await AppState.load(backend: backend, subscriptions: (FakeSubscriptions()..plus = true));
      await pumpEventQueue();
      expect(s.isPro, isTrue);
    });

    test('signing in re-attaches the gift for the new account', () async {
      await state.signInWithGoogle();
      backend.grantFeed.add(const PlusGrant(lifetime: true));
      await pumpEventQueue();
      expect(state.isPro, isTrue);
      await state.signOut();
      // The listener restarted, so the old account's gift is not carried over.
      expect(state.isPro, isFalse);
    });
  });

  test('without a backend there are no admin tools and nothing is paused', () async {
    final offline = await AppState.load();
    expect(offline.adminTools, isNull);
    expect(offline.wishingPaused, isFalse);
  });

  test('Google sign-in sets the account; a dismissed Apple sheet changes nothing', () async {
    expect(state.accountLabel, isNull);
    expect(await state.signInWithApple(), isFalse);
    expect(state.accountLabel, isNull);
    expect(await state.signInWithGoogle(), isTrue);
    expect(state.accountLabel, 'a@b.c');
    await state.signOut();
    expect(state.accountLabel, isNull);
  });

  group('account sync', () {
    Wish cloudWish(String id, String text, DateTime changed) => Wish(
          id: id,
          text: text,
          kind: WishKind.big,
          category: WishCategory.career,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: changed,
        );

    test('a guest never uploads anything', () async {
      await state.cast('A calm new home', WishKind.big, WishCategory.home);
      await state.cast('Found a parking spot', WishKind.spark, WishCategory.daily);
      expect(backend.saves, isEmpty);
    });

    test('a signed-in account uploads sparks and big wishes', () async {
      await state.signInWithGoogle();
      final big = await state.cast('A calm new home', WishKind.big, WishCategory.home);
      final spark = await state.cast('Found a parking spot', WishKind.spark, WishCategory.daily);
      await pumpEventQueue();
      expect(backend.saves, containsAll([big!.id, spark!.id]));
    });

    test('signing in merges this phone with the cloud, newest change wins', () async {
      final mine = await state.cast('Written as a guest', WishKind.big, WishCategory.home);
      backend.cloud['c1'] = cloudWish('c1', 'From my old phone', DateTime(2026, 10, 2));
      // Same wish on both sides; the cloud copy is far newer.
      backend.cloud[mine!.id] = cloudWish(mine.id, 'Edited elsewhere', DateTime(2030));
      await state.signInWithGoogle();
      expect(state.activeWishes.map((w) => w.text), containsAll(['From my old phone', 'Edited elsewhere']));
      expect(state.activeWishes.any((w) => w.text == 'Written as a guest'), isFalse);
    });

    test('a guest wish the cloud has never seen is uploaded on sign-in', () async {
      final mine = await state.cast('Written as a guest', WishKind.big, WishCategory.home);
      await state.signInWithGoogle();
      expect(backend.cloud.containsKey(mine!.id), isTrue);
    });

    test('signing out clears personal wishes so the next person starts clean', () async {
      await state.signInWithGoogle();
      await state.cast('A calm new home', WishKind.big, WishCategory.home);
      await state.signOut();
      expect(state.activeWishes, isEmpty);
      final reloaded = await AppState.load(backend: backend);
      expect(reloaded.activeWishes, isEmpty);
    });

    test('luck received comes from the Well and survives resolving', () async {
      final big = await state.cast('A calm new home', WishKind.big, WishCategory.home);
      backend.myLuck.add({big!.id: 12});
      await pumpEventQueue();
      expect(state.totalLuckReceived, 12);
      await state.resolve(big.id, WishStatus.granted);
      backend.myLuck.add({});
      await pumpEventQueue();
      expect(state.totalLuckReceived, 12);
      expect(state.proof.single.luck, 12);
    });
  });

  group('settings behaviour', () {
    late _FakeReminders reminders;
    late AppState s;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      reminders = _FakeReminders();
      s = await AppState.load(
        now: () => DateTime(2026, 10, 27, 12),
        backend: backend,
        reminders: reminders,
      );
    });

    test('turning the reminder on asks permission, then schedules it', () async {
      expect(await s.setReminder(hour: 8, minute: 30, enabled: true), isTrue);
      expect(s.remindersEnabled, isTrue);
      expect(reminders.log, ['schedule 8:30']);
    });

    test('a refused permission leaves the switch off and schedules nothing', () async {
      reminders.allow = false;
      expect(await s.setReminder(hour: 8, minute: 30, enabled: true), isFalse);
      expect(s.remindersEnabled, isFalse);
      expect(reminders.log, ['cancel']);
    });

    test('turning it off cancels the notification', () async {
      await s.setReminder(hour: 8, minute: 30, enabled: true);
      await s.setReminder(hour: 8, minute: 30, enabled: false);
      expect(s.remindersEnabled, isFalse);
      expect(reminders.log.last, 'cancel');
    });

    test('an enabled reminder is re-armed on the next launch', () async {
      await s.setReminder(hour: 21, minute: 15, enabled: true);
      reminders.log.clear();
      await AppState.load(backend: backend, reminders: reminders);
      await pumpEventQueue();
      expect(reminders.log, ['schedule 21:15']);
    });

    test('the haptics switch persists and silences every vibration', () async {
      await s.setHaptics(false);
      expect(Haptics.enabled, isFalse);
      final again = await AppState.load(backend: backend, reminders: reminders);
      expect(again.hapticsEnabled, isFalse);
      expect(Haptics.enabled, isFalse);
      await s.setHaptics(true);
      expect(Haptics.enabled, isTrue);
    });

    test('export contains the wishes and settings', () async {
      await s.cast('A calm new home', WishKind.big, WishCategory.home);
      final out = s.exportData();
      expect(out, contains('A calm new home'));
      expect(out, contains('"haptics": true'));
      expect(out, contains('"account": "Guest"'));
    });

    test('sign-out is refused when a wish cannot be saved first', () async {
      await s.signInWithGoogle();
      await s.cast('A calm new home', WishKind.big, WishCategory.home);
      backend.failSaves = true;
      await expectLater(s.signOut(), throwsA(isA<StateError>()));
      expect(s.accountLabel, isNotNull);
      expect(s.activeWishes, hasLength(1));
    });

    test('backing out of deletion changes nothing', () async {
      await s.cast('A calm new home', WishKind.big, WishCategory.home);
      backend.deleteAnswer = false;
      expect(await s.deleteEverything(), isFalse);
      expect(s.activeWishes, hasLength(1));
    });

    test('deleting everything wipes the phone and returns to first run', () async {
      await s.signInWithGoogle();
      await s.completeOnboarding();
      await s.setHaptics(false);
      await s.cast('A calm new home', WishKind.big, WishCategory.home);
      expect(await s.deleteEverything(), isTrue);
      expect(s.activeWishes, isEmpty);
      expect(s.onboarded, isFalse);
      expect(s.accountLabel, isNull);
      expect(s.hapticsEnabled, isTrue);
      expect(backend.cloud, isEmpty);
      final reloaded = await AppState.load(backend: backend);
      expect(reloaded.activeWishes, isEmpty);
      expect(reloaded.onboarded, isFalse);
    });
  });
}
