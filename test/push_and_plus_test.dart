// AppState behaviour for push notifications and the Plus subscription, driven
// through in-memory stand-ins for Firestore, the OS and the store.
import 'package:flutter_test/flutter_test.dart';
import 'package:manifestwell/models/wish.dart';
import 'package:manifestwell/state/app_state.dart';
import 'package:manifestwell/state/push.dart';
import 'package:manifestwell/state/subscriptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_well_backend.dart';
import 'support/fakes.dart';

Future<AppState> _load({
  FakeWellBackend? backend,
  FakePush? push,
  FakeSubscriptions? subs,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final s = await AppState.load(
    backend: backend,
    push: push ?? const NoPush(),
    subscriptions: subs ?? const NoSubscriptions(),
  );
  await pumpEventQueue();
  return s;
}

void main() {
  group('push notifications', () {
    late FakeWellBackend backend;
    late FakePush push;

    setUp(() {
      backend = FakeWellBackend();
      push = FakePush();
    });

    test('nothing is registered until the person opts in', () async {
      await _load(backend: backend, push: push);
      expect(backend.devices, isEmpty);
      expect(push.prompts, 0);
    });

    test('turning on alerts asks permission, then registers this phone', () async {
      final s = await _load(backend: backend, push: push);
      expect(await s.setPush(luck: true, revisit: true), isTrue);
      expect(push.prompts, 1);
      expect(backend.devices['token-1'], (uid: null, luck: true, revisit: true, tz: 'America/New_York'));
    });

    test('a refused permission changes nothing and registers nothing', () async {
      push.allowed = false;
      final s = await _load(backend: backend, push: push);
      expect(await s.setPush(luck: true), isFalse);
      expect(s.pushLuck, isFalse);
      expect(backend.devices, isEmpty);
    });

    test('each kind can be switched independently', () async {
      final s = await _load(backend: backend, push: push);
      await s.setPush(luck: true);
      expect(backend.devices['token-1']!.luck, isTrue);
      expect(backend.devices['token-1']!.revisit, isFalse);
      await s.setPush(revisit: true);
      expect(backend.devices['token-1']!.revisit, isTrue);
    });

    test('turning everything off removes the phone from the server', () async {
      final s = await _load(backend: backend, push: push);
      await s.setPush(luck: true, revisit: true);
      await s.setPush(luck: false, revisit: false);
      expect(backend.devices, isEmpty);
      expect(s.pushAnyOn, isFalse);
    });

    test('the choice survives a restart and the phone re-registers', () async {
      final s = await _load(backend: backend, push: push);
      await s.setPush(luck: true);
      backend.devices.clear(); // e.g. the server lost the record
      final again = await _load(
        backend: backend,
        push: push,
        prefs: {'pushLuck': true, 'pushRevisit': false},
      );
      expect(again.pushLuck, isTrue);
      expect(backend.devices.keys, ['token-1']);
    });

    test('permission revoked in system settings registers nothing on launch', () async {
      push.granted = false;
      push.allowed = false;
      await _load(backend: backend, push: push, prefs: {'pushLuck': true});
      expect(backend.devices, isEmpty);
    });

    test('a rotated token moves the record rather than leaving a stale one', () async {
      final s = await _load(backend: backend, push: push);
      await s.setPush(luck: true);
      push.currentToken = 'token-2';
      push.tokens.add('token-2');
      await pumpEventQueue();
      expect(backend.devices.keys, ['token-2']);
      expect(s.pushLuck, isTrue);
    });

    test('a phone with no token (simulator) just does not register', () async {
      push.currentToken = null;
      final s = await _load(backend: backend, push: push);
      expect(await s.setPush(luck: true), isTrue);
      expect(backend.devices, isEmpty);
    });

    test('signing in re-registers the phone under the new account', () async {
      final s = await _load(backend: backend, push: push);
      await s.setPush(luck: true);
      expect(backend.devices['token-1']!.uid, isNull);
      await s.signInWithGoogle();
      await pumpEventQueue();
      expect(backend.devices['token-1']!.uid, 'uid-ada@example.com');
    });

    test('signing out stops the old account getting pushes on this phone', () async {
      final s = await _load(backend: backend, push: push);
      await s.signInWithGoogle();
      await s.setPush(luck: true);
      expect(backend.devices['token-1']!.uid, 'uid-ada@example.com');
      await s.signOut();
      await pumpEventQueue();
      // Re-registered, but as the new guest session, not the old account.
      expect(backend.devices['token-1']?.uid, isNull);
    });

    test('deleting everything revokes the token and clears the choices', () async {
      final s = await _load(backend: backend, push: push);
      await s.setPush(luck: true, revisit: true);
      expect(await s.deleteEverything(), isTrue);
      expect(push.revoked, 1);
      expect(s.pushLuck, isFalse);
      expect(s.pushRevisit, isFalse);
      expect(s.pushAsked, isFalse);
    });

    test('a tap on a notification asks for the Vault tab', () async {
      final s = await _load(backend: backend, push: push);
      push.tapController.add(const PushTap('luck', 'w1'));
      await pumpEventQueue();
      expect(s.openTab.value, 2);
    });

    test('the tap that launched the app is not lost', () async {
      push.launch = const PushTap('revisit', 'w1');
      final s = await _load(backend: backend, push: push);
      expect(s.openTab.value, 2);
    });

    test('the offer comes once, after the first Big Wish, and only with a backend', () async {
      final s = await _load(backend: backend, push: push);
      expect(s.shouldOfferPush, isFalse); // nothing cast yet
      await s.cast('Found twenty dollars', WishKind.spark, WishCategory.daily);
      expect(s.shouldOfferPush, isFalse); // sparks are private
      await s.cast('A calm new home', WishKind.big, WishCategory.home);
      expect(s.shouldOfferPush, isTrue);
      await s.markPushAsked();
      expect(s.shouldOfferPush, isFalse); // never nag

      final offline = await _load();
      await offline.cast('A calm new home', WishKind.big, WishCategory.home);
      expect(offline.shouldOfferPush, isFalse);
    });

    test('someone who already opted in is not offered it again', () async {
      final s = await _load(backend: backend, push: push);
      await s.setPush(luck: true);
      await s.cast('A calm new home', WishKind.big, WishCategory.home);
      expect(s.shouldOfferPush, isFalse);
    });
  });

  group('Plus subscription', () {
    late FakeSubscriptions subs;

    setUp(() => subs = FakeSubscriptions());

    test('a free person is not Plus and is held to one Big Wish', () async {
      final s = await _load(subs: subs);
      expect(s.isPro, isFalse);
      await s.cast('First', WishKind.big, WishCategory.home);
      expect(s.canCastBigWish, isFalse);
      expect(await s.cast('Second', WishKind.big, WishCategory.love), isNull);
    });

    test('an active subscription unlocks unlimited Big Wishes', () async {
      subs.plus = true;
      final s = await _load(subs: subs);
      expect(s.isPro, isTrue);
      await s.cast('First', WishKind.big, WishCategory.home);
      expect(await s.cast('Second', WishKind.big, WishCategory.love), isNotNull);
    });

    test('buying Plus unlocks it immediately', () async {
      final s = await _load(subs: subs);
      final result = await s.buyPlan(monthly);
      expect(result.outcome, PurchaseOutcome.success);
      expect(s.isPro, isTrue);
      expect(subs.bought, [monthly.id]);
    });

    test('a cancelled, pending or failed purchase leaves it locked', () async {
      final s = await _load(subs: subs);
      for (final outcome in [PurchaseOutcome.cancelled, PurchaseOutcome.pending, PurchaseOutcome.failed]) {
        subs.nextBuy = BuyResult(outcome, 'nope');
        expect((await s.buyPlan(monthly)).outcome, outcome);
        expect(s.isPro, isFalse);
      }
    });

    test('expiry or a refund takes Plus away while the app is open', () async {
      subs.plus = true;
      final s = await _load(subs: subs);
      subs.changes.add(false);
      await pumpEventQueue();
      expect(s.isPro, isFalse);
    });

    test('a renewal or a purchase elsewhere turns it on', () async {
      final s = await _load(subs: subs);
      subs.changes.add(true);
      await pumpEventQueue();
      expect(s.isPro, isTrue);
    });

    test('offline at launch keeps what the person already paid for', () async {
      subs.plus = null; // the store cannot be reached
      final s = await _load(subs: subs, prefs: {'plusCached': true});
      expect(s.isPro, isTrue);
    });

    test('but a known "no" at launch does remove a stale yes', () async {
      subs.plus = false;
      final s = await _load(subs: subs, prefs: {'plusCached': true});
      expect(s.isPro, isFalse);
    });

    test('restoring finds a subscription from another phone', () async {
      subs.restoreResult = true;
      final s = await _load(subs: subs);
      expect(await s.restorePurchases(), isTrue);
      expect(s.isPro, isTrue);
    });

    test('restoring with nothing to restore says so and changes nothing', () async {
      final s = await _load(subs: subs);
      expect(await s.restorePurchases(), isFalse);
      expect(s.isPro, isFalse);
    });

    test('restoring while offline throws so the screen can explain', () async {
      subs.restoreThrows = true;
      final s = await _load(subs: subs);
      await expectLater(s.restorePurchases(), throwsStateError);
    });

    test('purchases follow the account: linked on sign-in, released on sign-out', () async {
      final backend = FakeWellBackend();
      final s = await _load(backend: backend, subs: subs);
      expect(subs.identified, [null]); // anonymous at launch
      await s.signInWithGoogle();
      await pumpEventQueue();
      expect(subs.identified.last, 'uid-ada@example.com');
      await s.signOut();
      await pumpEventQueue();
      expect(subs.identified.last, isNull);
    });

    test('deleting everything drops Plus locally and unlinks the account', () async {
      subs.plus = true;
      final s = await _load(subs: subs);
      expect(s.isPro, isTrue);
      await s.deleteEverything();
      expect(s.isPro, isFalse);
      expect(subs.identified.last, isNull);
    });

    test('with no store configured the app says purchases are unavailable', () async {
      final s = await _load();
      expect(s.purchasesAvailable, isFalse);
      expect(await s.loadPlans(), isEmpty);
      expect((await s.buyPlan(monthly)).outcome, PurchaseOutcome.failed);
    });

    test('the export notes whether Plus is active', () async {
      subs.plus = true;
      final s = await _load(subs: subs);
      expect(s.exportData(), contains('"plus": true'));
    });
  });
}
