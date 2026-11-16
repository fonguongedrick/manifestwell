import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// A tap on a delivered notification, reduced to what the app needs.
class PushTap {
  /// "luck", "revisit" or "announcement".
  final String type;
  final String? wishId;
  const PushTap(this.type, this.wishId);
}

/// Push notifications from the server (luck received, revisit nudges). AppState
/// only knows this seam, so tests and builds without Firebase use [NoPush].
abstract class Push {
  /// True if the OS currently lets the app show notifications. Never prompts.
  Future<bool> isAuthorized();

  /// Shows the system prompt if it hasn't been answered. True if allowed.
  Future<bool> requestPermission();

  /// This phone's token, or null when it can't have one (simulator, a phone
  /// without Google Play services, permission refused).
  Future<String?> token();

  /// New tokens, as the platform rotates them.
  Stream<String> get tokenChanges;

  /// Taps on notifications while the app was in the background.
  Stream<PushTap> get taps;

  /// The tap that launched the app from a closed state, if there was one.
  Future<PushTap?> launchTap();

  /// The IANA zone this phone is in, so nudges arrive at a sensible hour.
  Future<String> timezone();

  /// Forgets this phone's token so the server can no longer reach it.
  Future<void> revoke();
}

class NoPush implements Push {
  const NoPush();
  @override
  Future<bool> isAuthorized() async => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get tokenChanges => const Stream.empty();
  @override
  Stream<PushTap> get taps => const Stream.empty();
  @override
  Future<PushTap?> launchTap() async => null;
  @override
  Future<String> timezone() async => 'UTC';
  @override
  Future<void> revoke() async {}
}

/// Firebase Cloud Messaging.
///
/// firebase_messaging 17 deprecates getToken/onTokenRefresh/deleteToken in
/// favour of Firebase Installation IDs, but the Admin SDK on our server still
/// addresses classic registration tokens, so this is the one place that uses
/// them. Moving to FIDs later means changing only this class.
class FirebasePush implements Push {
  FirebasePush() {
    FirebaseMessaging.onMessageOpenedApp.listen(_forward);
    _createChannels();
  }

  final _messaging = FirebaseMessaging.instance;
  final _taps = StreamController<PushTap>.broadcast();

  /// Android needs a channel to exist before a push can name it. These ids
  /// match the ones the Cloud Functions send.
  Future<void> _createChannels() async {
    try {
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'luck_alerts',
        'Luck on my wishes',
        description: 'When someone sends luck to a wish you shared.',
        importance: Importance.defaultImportance,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'revisit',
        'Revisit reminders',
        description: 'A nudge to revisit a wish after a while.',
        importance: Importance.defaultImportance,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'announcements',
        'News from ManifestWell',
        description: 'Occasional notes from the team.',
        importance: Importance.defaultImportance,
      ));
    } catch (e) {
      debugPrint('Could not create notification channels: $e');
    }
  }

  void _forward(RemoteMessage message) {
    final tap = _parse(message);
    if (tap != null) _taps.add(tap);
  }

  static PushTap? _parse(RemoteMessage message) {
    final type = message.data['type'];
    if (type is! String || type.isEmpty) return null;
    final wish = message.data['wishId'];
    return PushTap(type, wish is String ? wish : null);
  }

  static bool _allowed(AuthorizationStatus s) =>
      s == AuthorizationStatus.authorized || s == AuthorizationStatus.provisional;

  @override
  Future<bool> isAuthorized() async =>
      _allowed((await _messaging.getNotificationSettings()).authorizationStatus);

  @override
  Future<bool> requestPermission() async {
    final current = await _messaging.getNotificationSettings();
    if (_allowed(current.authorizationStatus)) return true;
    final result = await _messaging.requestPermission();
    return _allowed(result.authorizationStatus);
  }

  @override
  Future<String?> token() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS hands out the APNs token a moment after permission is granted,
        // and FCM can't mint a token without it. Simulators never get one.
        for (var i = 0; i < 10 && await _messaging.getAPNSToken() == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (await _messaging.getAPNSToken() == null) return null;
      }
      // ignore: deprecated_member_use
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('Could not get a push token: $e');
      return null;
    }
  }

  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenChanges => _messaging.onTokenRefresh;

  @override
  Stream<PushTap> get taps => _taps.stream;

  @override
  Future<PushTap?> launchTap() async {
    try {
      final message = await _messaging.getInitialMessage();
      return message == null ? null : _parse(message);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> timezone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return 'UTC';
    }
  }

  @override
  Future<void> revoke() async {
    try {
      // ignore: deprecated_member_use
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('Could not revoke the push token: $e');
    }
  }
}
