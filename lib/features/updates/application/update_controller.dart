import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_info.dart';
import '../../../core/settings/theme_mode_controller.dart';
import '../data/update_repository.dart';
import '../domain/app_release.dart';

enum UpdateStatus { idle, checking, upToDate, available, failed }

class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.manifest,
    this.source,
    this.lastChecked,
    this.skippedVersionCode,
    this.error,
  });

  final UpdateStatus status;
  final UpdateManifest? manifest;
  final UpdateSource? source;
  final DateTime? lastChecked;
  final int? skippedVersionCode;
  final String? error;

  bool get hasUpdate => status == UpdateStatus.available && manifest != null;
  bool get isChecking => status == UpdateStatus.checking;

  UpdateState copyWith({
    UpdateStatus? status,
    UpdateManifest? manifest,
    UpdateSource? source,
    DateTime? lastChecked,
    int? skippedVersionCode,
    String? error,
    bool clearManifest = false,
    bool clearError = false,
  }) {
    return UpdateState(
      status: status ?? this.status,
      manifest: clearManifest ? null : (manifest ?? this.manifest),
      source: source ?? this.source,
      lastChecked: lastChecked ?? this.lastChecked,
      skippedVersionCode: skippedVersionCode ?? this.skippedVersionCode,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Silent update checks, throttled so a cold start never blocks or spams the
/// network. Failures are deliberately soft: the plan works fully offline.
class UpdateController extends Notifier<UpdateState> {
  static const String lastCheckKey = 'update_last_check_ms';
  static const String lastAttemptKey = 'update_last_attempt_ms';
  static const String skippedKey = 'update_skipped_version_code';
  static const Duration checkInterval = Duration(hours: 6);
  static const Duration failureRetryInterval = Duration(minutes: 15);

  @override
  UpdateState build() {
    final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
    return UpdateState(skippedVersionCode: prefs.getInt(skippedKey));
  }

  Future<void> maybeCheck() async {
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    if (_isRecent(prefs.getInt(lastCheckKey), checkInterval)) return;
    // While offline, a failed check should not retry on every resume.
    if (_isRecent(prefs.getInt(lastAttemptKey), failureRetryInterval)) return;
    await check();
  }

  bool _isRecent(int? milliseconds, Duration window) {
    if (milliseconds == null) return false;
    final Duration age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(milliseconds),
    );
    return age >= Duration.zero && age < window;
  }

  /// [force] ignores the skip and the throttle; used by the Settings button.
  Future<void> check({bool force = false}) async {
    if (state.status == UpdateStatus.checking) return;

    state = state.copyWith(status: UpdateStatus.checking, clearError: true);

    try {
      final UpdateCheck? result = await ref
          .read(updateRepositoryProvider)
          .check();
      final DateTime now = DateTime.now();
      final AppVersion installed =
          (AppVersion.tryParse(AppInfo.versionName) ??
                  const AppVersion(major: 0, minor: 0, patch: 0))
              .withBuild(AppInfo.buildNumber);

      if (result == null || !result.manifest.isNewerThan(installed)) {
        state = UpdateState(
          status: UpdateStatus.upToDate,
          lastChecked: now,
          skippedVersionCode: state.skippedVersionCode,
        );
        await _rememberCheck(now);
        return;
      }

      if (!force &&
          result.manifest.versionCode > 0 &&
          state.skippedVersionCode == result.manifest.versionCode) {
        state = UpdateState(
          status: UpdateStatus.upToDate,
          lastChecked: now,
          skippedVersionCode: state.skippedVersionCode,
        );
        await _rememberCheck(now);
        return;
      }

      state = UpdateState(
        status: UpdateStatus.available,
        manifest: result.manifest,
        source: result.source,
        lastChecked: now,
        skippedVersionCode: state.skippedVersionCode,
      );
      await _rememberCheck(now);
    } catch (error) {
      state = state.copyWith(
        status: UpdateStatus.failed,
        error: error.toString(),
      );
      await ref
          .read(sharedPreferencesProvider)
          .setInt(lastAttemptKey, DateTime.now().millisecondsSinceEpoch);
    }
  }

  Future<void> skip() async {
    final UpdateManifest? manifest = state.manifest;
    if (manifest == null) return;
    // A release without a build number (raw GitHub fallback) cannot be skipped
    // safely: the code would hide every later build too.
    final int code = manifest.versionCode > 0 ? manifest.versionCode : 0;
    if (code > 0) {
      await ref.read(sharedPreferencesProvider).setInt(skippedKey, code);
    }
    state = state.copyWith(
      status: UpdateStatus.upToDate,
      clearManifest: true,
      skippedVersionCode: code > 0 ? code : null,
      clearError: true,
    );
  }

  /// Opens the APK in the browser. Android handles the install confirmation;
  /// silent install would need REQUEST_INSTALL_PACKAGES and is intentionally
  /// avoided for a private side-loaded app.
  Future<bool> openDownload(UpdateManifest manifest) async {
    final Uri? uri = Uri.tryParse(manifest.apkUrl);
    if (uri == null || uri.scheme != 'https') return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _rememberCheck(DateTime at) {
    return ref
        .read(sharedPreferencesProvider)
        .setInt(lastCheckKey, at.millisecondsSinceEpoch);
  }
}

final Provider<http.Client> updateHttpClientProvider = Provider<http.Client>((
  Ref ref,
) {
  final http.Client client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final Provider<UpdateRepository> updateRepositoryProvider =
    Provider<UpdateRepository>((Ref ref) {
      return UpdateRepository(ref.watch(updateHttpClientProvider));
    });

final NotifierProvider<UpdateController, UpdateState> updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
