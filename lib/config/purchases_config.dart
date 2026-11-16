import 'package:flutter/foundation.dart';

/// Settings for in-app subscriptions, which are managed through RevenueCat.
///
/// The SDK keys are public identifiers, not secrets, but they differ per
/// platform and per environment, so they are supplied at build time:
///   flutter run --dart-define=RC_ANDROID_KEY=goog_xxx --dart-define=RC_IOS_KEY=appl_xxx
/// With no key the app runs normally and the paywall says purchases aren't
/// available yet, instead of pretending to sell something.
class PurchasesConfig {
  PurchasesConfig._();

  static const _androidKey = String.fromEnvironment('RC_ANDROID_KEY');
  static const _iosKey = String.fromEnvironment('RC_IOS_KEY');

  /// The entitlement that unlocks Plus, as named in the RevenueCat dashboard.
  static const entitlement = 'plus';

  static String get apiKey => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => _iosKey,
        TargetPlatform.android => _androidKey,
        _ => '',
      };
}
