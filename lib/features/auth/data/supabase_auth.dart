import 'package:supabase_flutter/supabase_flutter.dart';

/// Compile-time Supabase identity, supplied by CI through `--dart-define`.
///
/// The anon key is a public, RLS-scoped key; the values are still injected at
/// build time so a contributor build cannot accidentally point at production
/// without opting in.
abstract final class SupabaseConfig {
  static const String url = String.fromEnvironment('KHUTATI_SUPABASE_URL');
  static const String anonKey = String.fromEnvironment(
    'KHUTATI_SUPABASE_ANON_KEY',
  );

  /// The Web OAuth client created for Khutati. Google is the only provider.
  static const String googleWebClientId =
      '700504267004-ooujpe4jvpuj14mk24fi9vr9ub7pptq9.apps.googleusercontent.com';

  /// Must match Authentication → URL Configuration in the Supabase project and
  /// the intent-filter in AndroidManifest.xml.
  static const String redirectUrl = 'com.khutati.app://login-callback';

  static bool get isConfigured =>
      url.trim().isNotEmpty && anonKey.trim().isNotEmpty;
}

/// A sign-in failure that is safe to show to the user in Arabic.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thin, testable wrapper around Supabase Auth.
///
/// Session persistence and refresh are handled by `supabase_flutter` (token is
/// stored in SharedPreferences), which is what lets the app start on Today
/// without a network connection after the first successful sign-in.
abstract final class SupabaseAuth {
  static bool _initialized = false;

  static bool get isAvailable => _initialized && SupabaseConfig.isConfigured;

  static Future<void> initialize() async {
    if (!SupabaseConfig.isConfigured || _initialized) return;
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
    _initialized = true;
  }

  static GoTrueClient get _auth {
    if (!isAvailable) {
      throw const AuthFailure(
        'تسجيل الدخول غير مهيأ في هذا الإصدار. تحقق من اتصالك ثم أعد المحاولة.',
      );
    }
    return Supabase.instance.client.auth;
  }

  static Session? get currentSession =>
      isAvailable ? _auth.currentSession : null;

  static User? get currentUser => isAvailable ? _auth.currentUser : null;

  static Stream<AuthState> get authStateChanges =>
      isAvailable ? _auth.onAuthStateChange : const Stream<AuthState>.empty();

  /// Opens the Google consent screen in the browser. Supabase returns to
  /// [SupabaseConfig.redirectUrl], which Android routes back into the app.
  static Future<void> signInWithGoogle() async {
    final auth = _auth;
    try {
      final bool launched = await auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseConfig.redirectUrl,
        queryParams: const <String, String>{'prompt': 'select_account'},
      );
      if (!launched) {
        throw const AuthFailure('تعذّر فتح صفحة Google. حاول مرة أخرى.');
      }
    } on AuthException catch (error) {
      throw AuthFailure(_messageFor(error));
    }
  }

  static Future<void> updateDisplayName(String name) async {
    final String value = name.trim();
    if (value.isEmpty || value.length > 60) {
      throw const AuthFailure('اكتب اسماً بين حرف واحد و60 حرفاً.');
    }
    try {
      await _auth.updateUser(
        UserAttributes(
          data: <String, dynamic>{'full_name': value, 'name': value},
        ),
      );
    } on AuthException catch (error) {
      throw AuthFailure(_messageFor(error));
    }
  }

  /// Local scope keeps other devices signed in; the user asked to leave this
  /// phone, not to revoke every session.
  static Future<void> signOut() async {
    try {
      await _auth.signOut(scope: SignOutScope.local);
    } on AuthException catch (error) {
      throw AuthFailure(_messageFor(error));
    }
  }

  static String _messageFor(AuthException error) {
    final String code = (error.code ?? '').toLowerCase();
    final String message = error.message.toLowerCase();
    if (code.contains('network') ||
        message.contains('socket') ||
        message.contains('network') ||
        message.contains('failed host lookup')) {
      return 'تعذّر الاتصال بالإنترنت. تحقق من الشبكة وحاول مرة أخرى.';
    }
    if (code.contains('cancel') || message.contains('cancel')) {
      return 'أُلغي تسجيل الدخول.';
    }
    return 'تعذّر إكمال العملية. حاول مرة أخرى.';
  }
}
