import 'dart:async';

import 'package:manifestwell/state/push.dart';
import 'package:manifestwell/state/subscriptions.dart';

/// A push service whose permission, token and taps the test controls.
class FakePush implements Push {
  FakePush({this.allowed = true, this.currentToken = 'token-1'});

  /// What the OS permission prompt will answer.
  bool allowed;

  /// Whether permission has already been granted (no prompt needed).
  bool granted = false;

  String? currentToken;
  PushTap? launch;
  var revoked = 0;
  var prompts = 0;

  final tokens = StreamController<String>.broadcast();
  final tapController = StreamController<PushTap>.broadcast();

  @override
  Future<bool> isAuthorized() async => granted;

  @override
  Future<bool> requestPermission() async {
    prompts++;
    if (allowed) granted = true;
    return allowed;
  }

  @override
  Future<String?> token() async => currentToken;
  @override
  Stream<String> get tokenChanges => tokens.stream;
  @override
  Stream<PushTap> get taps => tapController.stream;
  @override
  Future<PushTap?> launchTap() async => launch;
  @override
  Future<String> timezone() async => 'America/New_York';
  @override
  Future<void> revoke() async => revoked++;
}

const monthly = Plan(id: r'$rc_monthly', title: 'Monthly', price: r'$4.99', period: 'month');
const weekly = Plan(id: r'$rc_weekly', title: 'Weekly', price: r'$1.99', period: 'week');
const yearly = Plan(
  id: r'$rc_annual',
  title: 'Yearly',
  price: r'$39.99',
  period: 'year',
  trial: '3 days free',
);

/// A store whose catalogue and purchase results the test controls.
class FakeSubscriptions implements Subscriptions {
  FakeSubscriptions({this.available = true, this.catalogue = const [weekly, monthly, yearly]});

  @override
  bool available;
  List<Plan> catalogue;

  /// What [isPlus] reports; null simulates being offline.
  bool? plus = false;
  BuyResult nextBuy = const BuyResult(PurchaseOutcome.success);
  bool restoreResult = false;
  bool restoreThrows = false;
  final identified = <String?>[];
  final bought = <String>[];
  final changes = StreamController<bool>.broadcast();

  @override
  Stream<bool> get plusChanges => changes.stream;

  @override
  Future<bool?> isPlus() async => plus;

  @override
  Future<List<Plan>> plans() async => catalogue;

  @override
  Future<BuyResult> buy(Plan plan) async {
    bought.add(plan.id);
    if (nextBuy.outcome == PurchaseOutcome.success) plus = true;
    return nextBuy;
  }

  @override
  Future<bool> restore() async {
    if (restoreThrows) throw StateError('offline');
    if (restoreResult) plus = true;
    return restoreResult;
  }

  @override
  Future<void> identify(String? accountId) async => identified.add(accountId);

  @override
  Future<Uri> managementUrl() async => Uri.parse('https://example.com/manage');
}
