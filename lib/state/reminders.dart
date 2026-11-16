import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The daily "notice what went right" nudge. AppState only knows this seam, so
/// tests and unsupported platforms run with [NoReminders].
abstract class Reminders {
  /// Asks the OS for permission if needed. True when reminders can be shown.
  Future<bool> requestPermission();

  /// Schedules one repeating reminder at [hour]:[minute] local time, replacing
  /// any earlier one.
  Future<void> schedule({required int hour, required int minute});

  Future<void> cancel();
}

class NoReminders implements Reminders {
  const NoReminders();
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> schedule({required int hour, required int minute}) async {}
  @override
  Future<void> cancel() async {}
}

class LocalReminders implements Reminders {
  static const _id = 1001;
  static const _channelId = 'daily_ritual';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // Without the device zone the reminder would fire at the wrong hour,
      // so say so loudly in debug builds rather than guessing.
      debugPrint('Could not read the device timezone: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        // The flat star in res/drawable, so the status bar shows a clean glyph
        // instead of a filled square.
        android: AndroidInitializationSettings('ic_stat_manifestwell'),
        // Permission is requested when the person turns reminders on, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
    return false;
  }

  @override
  Future<void> schedule({required int hour, required int minute}) async {
    await _init();
    final now = tz.TZDateTime.now(tz.local);
    var first = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!first.isAfter(now)) first = first.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: _id,
      title: 'ManifestWell',
      body: 'A quiet moment for your wishes. What went right today?',
      scheduledDate: first,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Daily ritual',
          channelDescription: 'A gentle daily nudge to notice what went right.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      // Inexact is deliberate: a daily nudge doesn't need to-the-second timing,
      // and it avoids the exact-alarm permission Google Play reviews closely.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancel() async {
    await _init();
    await _plugin.cancel(id: _id);
  }
}
