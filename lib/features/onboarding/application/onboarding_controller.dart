import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/settings/theme_mode_controller.dart'
    show sharedPreferencesProvider;

/// Whether the welcome screens have been seen.
///
/// Versioned so a future redesign can introduce a new flow without re-showing
/// this one to existing users.
final NotifierProvider<OnboardingController, bool> onboardingSeenProvider =
    NotifierProvider<OnboardingController, bool>(OnboardingController.new);

class OnboardingController extends Notifier<bool> {
  static const String storageKey = 'onboarding_seen_v1';

  @override
  bool build() {
    final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(storageKey) ?? false;
  }

  /// Marks the flow complete *before* the caller navigates, so the router's
  /// redirect does not bounce the user back to `/onboarding`.
  Future<void> complete() async {
    if (state) return;
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(storageKey, true);
  }
}
