import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_auth.dart';

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
    Provider<AuthController>((Ref ref) => const AuthController());

/// UI-facing auth actions. Every method throws [AuthFailure] with a message
/// that is ready for a KToast.
class AuthController {
  const AuthController();

  Future<void> signInWithGoogle() => SupabaseAuth.signInWithGoogle();

  Future<void> updateDisplayName(String name) =>
      SupabaseAuth.updateDisplayName(name);

  Future<void> signOut() => SupabaseAuth.signOut();
}
