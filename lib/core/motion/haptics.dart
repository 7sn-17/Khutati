import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/theme_mode_controller.dart' show sharedPreferencesProvider;

/// Whether the app may use the device vibrator (PRD 5.11, Settings).
final NotifierProvider<HapticsController, bool> hapticsEnabledProvider =
    NotifierProvider<HapticsController, bool>(HapticsController.new);

class HapticsController extends Notifier<bool> {
  static const String storageKey = 'haptics_enabled';

  @override
  bool build() {
    return ref.watch(sharedPreferencesProvider).getBool(storageKey) ?? true;
  }

  Future<void> set(bool enabled) async {
    if (state == enabled) return;
    state = enabled;
    await ref.read(sharedPreferencesProvider).setBool(storageKey, enabled);
  }

  Future<void> toggle() => set(!state);
}

/// A small haptic vocabulary, mirroring the prototype's `navigator.vibrate`
/// calls but using Android's proper haptic channels.
///
/// * [selection] — switching tabs, toggling a chip
/// * [light]     — a step completed
/// * [medium]    — a task or day completed
/// * [success]   — a full session finished
class KhutatiHaptics {
  const KhutatiHaptics({required this.enabled});

  final bool enabled;

  void selection() {
    if (!enabled) return;
    // `selectionClick` is nearly imperceptible on many devices; a light impact
    // is what users actually feel as "vibration on touch".
    HapticFeedback.lightImpact();
  }

  void light() {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }

  void medium() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  void success() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  void heavy() {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
  }
}

final Provider<KhutatiHaptics> hapticsProvider = Provider<KhutatiHaptics>((Ref ref) {
  return KhutatiHaptics(enabled: ref.watch(hapticsEnabledProvider));
});
