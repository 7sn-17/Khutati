import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Injected in `main()` once `SharedPreferences.getInstance()` resolves, so the
/// first frame already has the persisted theme (no light-to-dark flash).
final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
  (Ref ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  ),
);

/// Theme selection: auto (follow system), light, or dark (PRD section 2, #15).
final NotifierProvider<ThemeModeController, ThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const String storageKey = 'theme_mode';

  @override
  ThemeMode build() {
    final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
    return decode(prefs.getString(storageKey));
  }

  /// Persists the choice. The prototype cycles auto -> dark -> light -> auto.
  Future<void> set(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    await ref.read(sharedPreferencesProvider).setString(storageKey, encode(mode));
  }

  Future<void> cycle() {
    return set(switch (state) {
      ThemeMode.system => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.light => ThemeMode.system,
    });
  }

  static ThemeMode decode(String? raw) => switch (raw) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };

  static String encode(ThemeMode mode) => switch (mode) {
        ThemeMode.dark => 'dark',
        ThemeMode.light => 'light',
        ThemeMode.system => 'system',
      };
}
