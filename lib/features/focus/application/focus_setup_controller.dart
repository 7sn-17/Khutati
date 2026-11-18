import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/settings/theme_mode_controller.dart'
    show sharedPreferencesProvider;
import '../domain/focus_setup.dart';

/// Persists the user's setup choices (mode, preset, lengths) so the Focus tab
/// always reopens exactly as it was left.
class FocusSetupController extends Notifier<FocusSetup> {
  static const String storageKey = 'focus_setup_v1';

  @override
  FocusSetup build() {
    try {
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      final String? raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return const FocusSetup();
      return FocusSetup.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
        const FocusSetup(),
      );
    } catch (_) {
      return const FocusSetup();
    }
  }

  void setMode(FocusMode mode) => _update((FocusSetup s) => s.copyWith(mode: mode));

  void setPreset(PomodoroPreset preset) =>
      _update((FocusSetup s) => s.withPreset(preset));

  void setFocusMinutes(int minutes) => _update(
    (FocusSetup s) => s.copyWith(
      preset: PomodoroPreset.custom,
      focusMinutes: minutes.clamp(FocusSetup.minMinutes, FocusSetup.maxMinutes),
    ),
  );

  void setBreakMinutes(int minutes) => _update(
    (FocusSetup s) => s.copyWith(
      preset: PomodoroPreset.custom,
      breakMinutes: minutes.clamp(1, 60),
    ),
  );

  void setFreeMinutes(int minutes) => _update(
    (FocusSetup s) => s.copyWith(
      freeMinutes: minutes.clamp(FocusSetup.minMinutes, FocusSetup.maxMinutes),
    ),
  );

  void setAutoBreak(bool enabled) =>
      _update((FocusSetup s) => s.copyWith(autoBreak: enabled));

  void _update(FocusSetup Function(FocusSetup) transform) {
    state = transform(state);
    try {
      unawaited(
        ref
            .read(sharedPreferencesProvider)
            .setString(storageKey, jsonEncode(state.toJson())),
      );
    } catch (_) {
      // Preferences are best-effort; the in-memory setup is still correct.
    }
  }
}

final NotifierProvider<FocusSetupController, FocusSetup> focusSetupProvider =
    NotifierProvider<FocusSetupController, FocusSetup>(
      FocusSetupController.new,
    );
