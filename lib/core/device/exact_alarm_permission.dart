import 'package:flutter/services.dart';

/// Exact-alarm permission (Android 12+ `SCHEDULE_EXACT_ALARM`).
///
/// The focus timer relies on exact alarms to fire its completion alert while
/// the app is frozen, so this helper exposes a check + a settings deep-link.
abstract final class ExactAlarmPermission {
  static const MethodChannel _channel = MethodChannel('khutati/focus_timer');

  /// `AlarmManager.canScheduleExactAlarms()` (always `true` below Android 12).
  static Future<bool> canSchedule() async {
    try {
      return await _channel.invokeMethod<bool>('canScheduleExactAlarms') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens the "Alarms & reminders" settings screen. Returns `true` when a
  /// screen was launched or the permission is already granted.
  static Future<bool> request() async {
    try {
      return await _channel.invokeMethod<bool>('openExactAlarmSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}
