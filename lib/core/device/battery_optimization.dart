import 'package:flutter/services.dart';

/// Battery-optimisation exemption (the OEM "unrestricted" switch).
///
/// A foreground service survives Doze only when the app is exempt, so the focus
/// timer asks once and remembers the answer. Both calls are total: they return
/// `false` instead of throwing when the platform has no implementation.
abstract final class BatteryOptimization {
  static const MethodChannel _channel = MethodChannel('khutati/focus_timer');

  /// `PowerManager.isIgnoringBatteryOptimizations(packageName)`.
  static Future<bool> isUnrestricted() async {
    try {
      return await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system sheet, then the battery list, then app details.
  /// Returns `true` when a screen was launched or the app was already exempt.
  static Future<bool> requestUnrestricted() async {
    try {
      return await _channel.invokeMethod<bool>('openBatterySettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}
