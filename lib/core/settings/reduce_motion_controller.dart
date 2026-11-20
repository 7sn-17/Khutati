import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_mode_controller.dart' show sharedPreferencesProvider;

/// User-facing "Reduce Motion" preference.
///
/// This is deliberately separate from the Android accessibility switch. The
/// system flag is honoured automatically by Flutter; this setting lets someone
/// keep system animations on while trading the app's heavier motion and blur
/// for battery life on an older phone.
final NotifierProvider<ReduceMotionController, bool> reduceMotionProvider =
    NotifierProvider<ReduceMotionController, bool>(ReduceMotionController.new);

class ReduceMotionController extends Notifier<bool> {
  static const String storageKey = 'reduce_motion';

  @override
  bool build() {
    final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
    return decode(prefs.getBool(storageKey));
  }

  Future<void> set(bool value) async {
    if (state == value) return;
    state = value;
    await ref.read(sharedPreferencesProvider).setBool(storageKey, value);
  }

  Future<void> toggle() => set(!state);

  static bool decode(bool? raw) => raw ?? false;
}
