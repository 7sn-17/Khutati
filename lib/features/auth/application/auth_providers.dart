import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/sync/cloud_sync_service.dart';
import '../data/supabase_auth.dart';
import 'guest_mode.dart';

/// Broadcast stream of Supabase auth events. Empty when the build has no
/// Supabase credentials, so the login screen still renders in development.
final StreamProvider<AuthState> authStateProvider = StreamProvider<AuthState>((
  Ref ref,
) {
  return SupabaseAuth.authStateChanges;
});

/// The signed-in user, kept in sync with [authStateProvider].
///
/// The synchronous fallback matters for the first frame: the stream has not
/// emitted yet but the persisted session is already available.
final Provider<User?> currentUserProvider = Provider<User?>((Ref ref) {
  final AsyncValue<AuthState> auth = ref.watch(authStateProvider);
  return auth.valueOrNull?.session?.user ?? SupabaseAuth.currentUser;
});

final Provider<bool> isSignedInProvider = Provider<bool>((Ref ref) {
  return ref.watch(currentUserProvider) != null ||
      SupabaseAuth.currentSession != null;
});

final Provider<AuthController> authControllerProvider =
    Provider<AuthController>((Ref ref) => AuthController(ref));

/// UI-facing auth actions. Every method throws [AuthFailure] with a message
/// that is ready for a KToast.
class AuthController {
  AuthController(this._ref);

  final Ref _ref;

  /// A successful Google account picker signs the user in and upgrades them
  /// from guest mode, so signing out later returns to the login screen.
  Future<void> signInWithGoogle() async {
    await SupabaseAuth.signInWithGoogle();
    await _ref.read(guestModeProvider.notifier).leave();
    // The router moves to Today immediately; restoring the account's cloud
    // rows runs alongside the entrance animation instead of blocking it.
    unawaited(_ref.read(cloudSyncServiceProvider).syncNow());
  }

  Future<void> updateDisplayName(String name) =>
      SupabaseAuth.updateDisplayName(name);

  Future<void> signOut() async {
    await SupabaseAuth.signOut();
    await _ref.read(guestModeProvider.notifier).leave();
  }
}
