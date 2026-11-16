import 'package:flutter/services.dart';

/// Every vibration in the app goes through here so the Settings switch is
/// honoured everywhere, not just on the screens someone remembered to check.
class Haptics {
  Haptics._();

  /// Mirrors AppState.hapticsEnabled; set when the app loads and on toggle.
  static bool enabled = true;

  static void selection() {
    if (enabled) HapticFeedback.selectionClick();
  }

  static void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (enabled) HapticFeedback.heavyImpact();
  }
}
