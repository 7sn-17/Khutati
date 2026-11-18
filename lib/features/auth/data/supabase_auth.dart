import 'package:google_sign_in/google_sign_in.dart';
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
  ///
  /// This is also passed to the native Google Sign-In plugin as
  /// `serverClientId`: Android's Credential Manager returns an ID token with
  /// this audience, which is exactly what Supabase verifies before creating
  /// the session. No browser redirect is involved.
  static const String googleWebClientId =
      '700504267004-ooujpe4jvpuj14mk24fi9vr9ub7pptq9.apps.googleusercontent.com';

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
  static Future<void>? _googleSignInReady;

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

  /// Starts the native Google account picker and exchanges its ID token for a
  /// Supabase session.
  ///
  /// This is deliberately not an OAuth browser flow: on Android the plugin
  /// uses Credential Manager, which shows the system account sheet and returns
  /// a signed ID token directly to the app.
  static Future<void> signInWithGoogle() async {
    final GoTrueClient auth = _auth;
    try {
      await _ensureGoogleSignInReady();
      final GoogleSignInAccount account = await GoogleSignIn.instance
          .authenticate();
      final String? idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthFailure('تعذّر الحصول على رمز Google. حاول مرة أخرى.');
      }
      await auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
    } on AuthFailure {
      rethrow;
    } on GoogleSignInException catch (error) {
      throw AuthFailure(_googleMessageFor(error));
    } on AuthException catch (error) {
      throw AuthFailure(_messageFor(error));
    }
  }

  /// `initialize` may only run once per process. The future is memoized so a
  /// second tap, or the Settings button after Login, reuses the same setup.
  static Future<void> _ensureGoogleSignInReady() {
    return _googleSignInReady ??= _initializeGoogleSignIn();
  }

  static Future<void> _initializeGoogleSignIn() async {
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: SupabaseConfig.googleWebClientId,
      );
    } catch (_) {
      // Let a later attempt retry if Play Services was temporarily unavailable.
      _googleSignInReady = null;
      rethrow;
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

  static String _googleMessageFor(GoogleSignInException error) {
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled => 'أُلغي تسجيل الدخول.',
      GoogleSignInExceptionCode.interrupted =>
        'توقف تسجيل الدخول. حاول مرة أخرى.',
      GoogleSignInExceptionCode.clientConfigurationError =>
        'إعداد تسجيل الدخول غير مكتمل على هذا الإصدار. '
            'حدّث التطبيق ثم حاول مرة أخرى.',
      GoogleSignInExceptionCode.providerConfigurationError =>
        'تعذّر تهيئة Google على هذا الجهاز. '
            'حدّث تطبيق Google Play ثم حاول مرة أخرى.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'تعذّر فتح نافذة اختيار حساب Google. حاول مرة أخرى.',
      GoogleSignInExceptionCode.userMismatch =>
        'الحساب المختار لا يطابق الجلسة الحالية. '
            'سجّل الخروج ثم حاول مرة أخرى.',
      GoogleSignInExceptionCode.unknownError =>
        'تعذّر تسجيل الدخول عبر Google. حاول مرة أخرى.',
    };
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
