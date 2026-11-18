import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/theme_mode_controller.dart';

/// Whether this install chose «المتابعة كزائر».
///
/// Guest mode is a persisted, local-only decision: it lets the router open the
/// app without a Supabase session while still keeping the Auth gate for every
/// normal install. Signing in with Google clears it again.
final NotifierProvider<GuestModeController, bool> guestModeProvider =
    NotifierProvider<GuestModeController, bool>(GuestModeController.new);

class GuestModeController extends Notifier<bool> {
  static const String storageKey = 'is_guest';

  @override
  bool build() {
    return ref.watch(sharedPreferencesProvider).getBool(storageKey) ?? false;
  }

  /// Enables guest mode immediately (the router reads the notifier state) and
  /// persists the choice before the caller navigates to Today.
  Future<void> enter() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(storageKey, true);
  }

  /// Leaves guest mode, either because the user signed in or signed out.
  Future<void> leave() async {
    state = false;
    await ref.read(sharedPreferencesProvider).setBool(storageKey, false);
  }
}
