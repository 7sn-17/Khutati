import 'package:flutter/services.dart';

import '../notifications/focus_notifications.dart';
import 'exact_alarm_permission.dart';

/// The two permissions a reminder needs, and the two deep links that grant them.
///
/// They are separate grants on Android: `POST_NOTIFICATIONS` decides whether an
/// alert can be posted at all, `SCHEDULE_EXACT_ALARM` decides whether it can be
/// posted at the minute the user picked. Settings shows one row for both
/// because the user experiences them as one feature.
class AlarmPermissions {
  const AlarmPermissions({
    required this.notifications,
    required this.exactAlarms,
  });

  const AlarmPermissions.unknown() : notifications = false, exactAlarms = false;

  final bool notifications;
  final bool exactAlarms;

  bool get allGranted => notifications && exactAlarms;
}

abstract final class AlarmSettings {
  static const MethodChannel _channel = MethodChannel('khutati/focus_timer');

  /// Reads both grants. Never throws: a missing plugin is reported as denied.
  static Future<AlarmPermissions> read() async {
    final bool notifications = await FocusNotifications.areEnabled();
    final bool exact = await ExactAlarmPermission.canSchedule();
    return AlarmPermissions(notifications: notifications, exactAlarms: exact);
  }

  /// Opens this app's notification screen (`ACTION_APP_NOTIFICATION_SETTINGS`).
  static Future<bool> openNotificationSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Opens "Alarms & reminders" (`ACTION_REQUEST_SCHEDULE_EXACT_ALARM`).
  static Future<bool> openExactAlarmSettings() =>
      ExactAlarmPermission.request();

  /// Sends the user to the grant they are missing. When both are granted this
  /// still opens the notification screen, so the row is never a dead end.
  static Future<bool> openMissing(AlarmPermissions permissions) {
    if (!permissions.notifications) return openNotificationSettings();
    if (!permissions.exactAlarms) return openExactAlarmSettings();
    return openNotificationSettings();
  }
}
