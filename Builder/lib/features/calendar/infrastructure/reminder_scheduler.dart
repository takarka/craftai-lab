import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_planner.dart';

enum ReminderPermission {
  granted,

  /// Notifications are off for the app, or were refused.
  denied,

  /// This platform has no local notifications (web, desktop).
  unsupported,
}

/// What the operating system keeps for calendar reminders; replaced in tests.
abstract class ReminderScheduler {
  Future<ReminderPermission> permission();

  /// Asks the user once; the system may not show the dialog again after a refusal.
  Future<ReminderPermission> requestPermission();

  /// Makes the device hold exactly [planned] as calendar reminders: others it
  /// still holds are removed, and the same id never exists twice.
  Future<void> replace(List<PlannedReminder> planned);

  Future<void> cancelAll();
}

class SystemReminderScheduler implements ReminderScheduler {
  SystemReminderScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'calendar_reminders',
      'Напоминания календаря',
      channelDescription: 'Напоминания о событиях календаря Builder',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> _init() => _ready ??= _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      // The permission dialog is shown on request, not at startup.
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );

  @override
  Future<ReminderPermission> permission() async {
    if (!_supported) return ReminderPermission.unsupported;
    try {
      await _init();
    } on MissingPluginException {
      return ReminderPermission.unsupported;
    }
    final bool? enabled;
    if (defaultTargetPlatform == TargetPlatform.android) {
      enabled = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
    } else {
      enabled =
          (await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.checkPermissions())
              ?.isEnabled;
    }
    return enabled == true ? ReminderPermission.granted : ReminderPermission.denied;
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    if (!_supported) return ReminderPermission.unsupported;
    await _init();
    final bool? granted;
    if (defaultTargetPlatform == TargetPlatform.android) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true);
    }
    return granted == true ? ReminderPermission.granted : ReminderPermission.denied;
  }

  Future<List<PendingNotificationRequest>> _ours() async => [
    for (final pending in await _plugin.pendingNotificationRequests())
      if (pending.payload?.startsWith(PlannedReminder.payloadPrefix) ?? false)
        pending,
  ];

  @override
  Future<void> replace(List<PlannedReminder> planned) async {
    if (!_supported) return;
    await _init();
    final wanted = {for (final reminder in planned) reminder.notificationId};
    for (final pending in await _ours()) {
      if (!wanted.contains(pending.id)) await _plugin.cancel(id: pending.id);
    }
    for (final reminder in planned) {
      // The same id replaces the earlier schedule, so a repeat never duplicates.
      await _plugin.zonedSchedule(
        id: reminder.notificationId,
        title: reminder.title,
        body: reminder.body,
        payload: reminder.payload,
        scheduledDate: tz.TZDateTime.from(reminder.fireAtUtc, tz.UTC),
        notificationDetails: _details,
        // Inexact: no exact-alarm permission is asked, so it may come a few minutes late.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_supported) return;
    await _init();
    for (final pending in await _ours()) {
      await _plugin.cancel(id: pending.id);
    }
  }
}
