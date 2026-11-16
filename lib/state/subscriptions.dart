import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/purchases_config.dart';

/// One way to subscribe, as the paywall shows it. Prices come from the store,
/// already localised and in the buyer's currency, never from our code.
class Plan {
  final String id;

  /// "Weekly", "Monthly", "Yearly".
  final String title;

  /// The store's formatted price, for example "$4.99".
  final String price;

  /// "week", "month" or "year": what the price is per.
  final String period;

  /// For example "3 days free", when the store offers a free trial.
  final String? trial;

  /// Opaque to the UI: the store package that [Subscriptions.buy] needs.
  final Object? handle;

  const Plan({
    required this.id,
    required this.title,
    required this.price,
    required this.period,
    this.trial,
    this.handle,
  });
}

enum PurchaseOutcome {
  /// Plus is now active.
  success,

  /// The person closed the store sheet. Not an error.
  cancelled,

  /// Waiting on approval (a parent, a slow bank). Plus unlocks when it clears.
  pending,

  failed,
}

class BuyResult {
  final PurchaseOutcome outcome;

  /// Something safe to show the person, when [outcome] is [PurchaseOutcome.failed].
  final String? message;
  const BuyResult(this.outcome, [this.message]);
}

/// ManifestWell Plus. AppState only knows this seam, so tests and builds
/// without store credentials use a stand-in.
abstract class Subscriptions {
  /// False when no store is configured, so the UI can say so honestly.
  bool get available;

  /// Whether Plus is active, now and whenever it changes (purchase, renewal,
  /// expiry, a restore on another device).
  Stream<bool> get plusChanges;

  /// Null when the answer can't be read right now (offline), which is not the
  /// same as "no": callers keep what they last knew.
  Future<bool?> isPlus();

  /// What can be bought. Empty when the store can't be reached.
  Future<List<Plan>> plans();

  Future<BuyResult> buy(Plan plan);

  /// Re-attaches purchases made earlier or on another phone. True if Plus is
  /// active afterwards.
  Future<bool> restore();

  /// Ties purchases to a signed-in account so they follow it across phones.
  /// Null goes back to an anonymous purchaser.
  Future<void> identify(String? accountId);

  /// Where the store lets the person change or cancel the subscription.
  Future<Uri> managementUrl();
}

class NoSubscriptions implements Subscriptions {
  const NoSubscriptions();
  @override
  bool get available => false;
  @override
  Stream<bool> get plusChanges => const Stream.empty();
  @override
  Future<bool?> isPlus() async => false;
  @override
  Future<List<Plan>> plans() async => const [];
  @override
  Future<BuyResult> buy(Plan plan) async =>
      const BuyResult(PurchaseOutcome.failed, 'Purchases are not available right now.');
  @override
  Future<bool> restore() async => false;
  @override
  Future<void> identify(String? accountId) async {}
  @override
  Future<Uri> managementUrl() async => _storeSubscriptionsPage();
}

Uri _storeSubscriptionsPage() => Uri.parse(
      defaultTargetPlatform == TargetPlatform.iOS
          ? 'https://apps.apple.com/account/subscriptions'
          : 'https://play.google.com/store/account/subscriptions',
    );

/// RevenueCat: validates receipts on its servers, keeps entitlements in sync
/// across devices, and wraps StoreKit and Google Play Billing. Products and
/// the entitlement are configured in its dashboard; see docs/launch-checklist.md.
class RevenueCatSubscriptions implements Subscriptions {
  RevenueCatSubscriptions._();

  final _plus = StreamController<bool>.broadcast();
  String? _managementUrl;

  /// Null when [apiKey] is empty or the SDK can't start, so the app falls back
  /// to [NoSubscriptions] rather than failing at launch.
  static Future<RevenueCatSubscriptions?> tryCreate({required String apiKey}) async {
    if (apiKey.isEmpty) {
      debugPrint('No RevenueCat key (RC_ANDROID_KEY / RC_IOS_KEY): purchases are off.');
      return null;
    }
    try {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
      await Purchases.configure(PurchasesConfiguration(apiKey));
      final s = RevenueCatSubscriptions._();
      Purchases.addCustomerInfoUpdateListener(s._onInfo);
      return s;
    } catch (e) {
      debugPrint('Could not start purchases: $e');
      return null;
    }
  }

  static bool _active(CustomerInfo info) =>
      info.entitlements.active.containsKey(PurchasesConfig.entitlement);

  void _onInfo(CustomerInfo info) {
    _managementUrl = info.managementURL;
    _plus.add(_active(info));
  }

  @override
  bool get available => true;

  @override
  Stream<bool> get plusChanges => _plus.stream;

  @override
  Future<bool?> isPlus() async {
    try {
      final info = await Purchases.getCustomerInfo();
      _managementUrl = info.managementURL;
      return _active(info);
    } catch (e) {
      debugPrint('Could not read the subscription: $e');
      return null;
    }
  }

  @override
  Future<List<Plan>> plans() async {
    try {
      final offering = (await Purchases.getOfferings()).current;
      final packages = [...?offering?.availablePackages]
        ..sort((a, b) => _rank(a.packageType).compareTo(_rank(b.packageType)));
      return [for (final p in packages) _plan(p)];
    } catch (e) {
      debugPrint('Could not load plans: $e');
      return const [];
    }
  }

  /// Shortest period first.
  static int _rank(PackageType t) => switch (t) {
        PackageType.weekly => 0,
        PackageType.monthly => 1,
        PackageType.twoMonth => 2,
        PackageType.threeMonth => 3,
        PackageType.sixMonth => 4,
        PackageType.annual => 5,
        _ => 6,
      };

  static Plan _plan(Package p) {
    final (title, period) = switch (p.packageType) {
      PackageType.weekly => ('Weekly', 'week'),
      PackageType.monthly => ('Monthly', 'month'),
      PackageType.twoMonth => ('2 months', '2 months'),
      PackageType.threeMonth => ('3 months', '3 months'),
      PackageType.sixMonth => ('6 months', '6 months'),
      PackageType.annual => ('Yearly', 'year'),
      _ => (p.storeProduct.title, 'period'),
    };
    return Plan(
      id: p.identifier,
      title: title,
      price: p.storeProduct.priceString,
      period: period,
      trial: _trial(p.storeProduct.introductoryPrice),
      handle: p,
    );
  }

  static String? _trial(IntroductoryPrice? intro) {
    if (intro == null || intro.price != 0) return null;
    final n = intro.periodNumberOfUnits * intro.cycles;
    final unit = switch (intro.periodUnit) {
      PeriodUnit.day => 'day',
      PeriodUnit.week => 'week',
      PeriodUnit.month => 'month',
      PeriodUnit.year => 'year',
      PeriodUnit.unknown => null,
    };
    if (unit == null || n <= 0) return null;
    return '$n $unit${n == 1 ? '' : 's'} free';
  }

  @override
  Future<BuyResult> buy(Plan plan) async {
    final package = plan.handle;
    if (package is! Package) {
      return const BuyResult(PurchaseOutcome.failed, 'That plan is not available right now.');
    }
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      final active = _active(result.customerInfo);
      _onInfo(result.customerInfo);
      return active
          ? const BuyResult(PurchaseOutcome.success)
          : const BuyResult(
              PurchaseOutcome.failed,
              'Your purchase went through but Plus is not active yet. Try Restore purchases in a moment.');
    } on PlatformException catch (e) {
      return switch (PurchasesErrorHelper.getErrorCode(e)) {
        PurchasesErrorCode.purchaseCancelledError => const BuyResult(PurchaseOutcome.cancelled),
        PurchasesErrorCode.paymentPendingError => const BuyResult(PurchaseOutcome.pending),
        PurchasesErrorCode.productAlreadyPurchasedError => const BuyResult(
            PurchaseOutcome.failed, 'You already have this. Tap Restore purchases to unlock Plus.'),
        PurchasesErrorCode.networkError => const BuyResult(
            PurchaseOutcome.failed, 'Could not reach the store. Check your connection and try again.'),
        PurchasesErrorCode.purchaseNotAllowedError => const BuyResult(
            PurchaseOutcome.failed, 'Purchases are turned off on this device.'),
        _ => const BuyResult(PurchaseOutcome.failed, 'The purchase could not be completed. You were not charged.'),
      };
    } catch (e) {
      debugPrint('Purchase failed: $e');
      return const BuyResult(PurchaseOutcome.failed, 'The purchase could not be completed. You were not charged.');
    }
  }

  @override
  Future<bool> restore() async {
    final info = await Purchases.restorePurchases();
    _onInfo(info);
    return _active(info);
  }

  @override
  Future<void> identify(String? accountId) async {
    try {
      if (accountId == null) {
        // logOut on an anonymous purchaser is an error, so check first.
        if (!await Purchases.isAnonymous) _onInfo(await Purchases.logOut());
        return;
      }
      if (await Purchases.appUserID == accountId) return;
      _onInfo((await Purchases.logIn(accountId)).customerInfo);
    } catch (e) {
      debugPrint('Could not link purchases to the account: $e');
    }
  }

  @override
  Future<Uri> managementUrl() async {
    final url = _managementUrl;
    return url == null ? _storeSubscriptionsPage() : Uri.parse(url);
  }
}
