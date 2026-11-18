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
    this.requestId = 0,
  });

  final UpdateStatus status;
  final UpdateManifest? manifest;
  final UpdateSource? source;
  final DateTime? lastChecked;
  final int? skippedVersionCode;
  final String? error;

  /// Incremented by a manual check so the single app-level presenter can show
  /// the dialog again even when the available version did not change.
  final int requestId;

  bool get hasUpdate => status == UpdateStatus.available && manifest != null;
  bool get isChecking => status == UpdateStatus.checking;

  UpdateState copyWith({
    UpdateStatus? status,
    UpdateManifest? manifest,
    UpdateSource? source,
    DateTime? lastChecked,
    int? skippedVersionCode,
    String? error,
    int? requestId,
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
      requestId: requestId ?? this.requestId,
    );
  }
}

/// Silent update checks, throttled so a cold start never blocks or spams the
/// network. Failures are deliberately soft: the plan works fully offline.
///
/// Quota discipline (GitHub allows 60 anonymous requests per hour per IP):
///
/// * [maybeCheck] — background, cold start and resume — does nothing while the
///   last **successful** check is younger than [cooldown];
/// * a failed background check leaves the timestamp untouched, so the next
///   resume tries again instead of the app going quiet for an hour;
/// * the repository turns the request conditional with the stored ETag, so an
///   unchanged release list costs nothing.
class UpdateController extends Notifier<UpdateState> {
  static const String lastCheckKey = 'update_last_check_ms';
  static const String etagKey = 'update_etag';
  static const String skippedKey = 'update_skipped_version_code';

  /// Background checks are gated on this; a manual tap always bypasses it.
  static const Duration cooldown = Duration(minutes: 60);

  @override
  UpdateState build() {
    final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
    return UpdateState(skippedVersionCode: prefs.getInt(skippedKey));
  }

  Future<void> maybeCheck() async {
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    if (_isRecent(prefs.getInt(lastCheckKey), cooldown)) return;
    await check();
  }

  bool _isRecent(int? milliseconds, Duration window) {
    if (milliseconds == null) return false;
    final Duration age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(milliseconds),
    );
    return age >= Duration.zero && age < window;
  }

  /// The running check, if any. A manual tap that lands mid-background-check
  /// joins it instead of stacking a second request.
  Future<void>? _inFlight;

  /// [force] marks a manual check from Settings: it bypasses the cooldown, is
  /// allowed to re-open the dialog, and reports failures instead of staying
  /// silent.
  Future<void> check({bool force = false}) async {
    final Future<void>? running = _inFlight;
    if (running != null) {
      await running;
      return;
    }

    final Future<void> run = _runCheck(force: force);
    _inFlight = run;
    try {
      await run;
    } finally {
      if (identical(_inFlight, run)) _inFlight = null;
    }
  }

  Future<void> _runCheck({required bool force}) async {
    final UpdateState previous = state;
    final int requestId = force ? previous.requestId + 1 : previous.requestId;
    state = previous.copyWith(
      status: UpdateStatus.checking,
      clearError: true,
      requestId: requestId,
    );

    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    try {
      final String? etag = prefs.getString(etagKey);
      final UpdateCheckResult result = await ref
          .read(updateRepositoryProvider)
          .check(etag: etag);

      // Only a real 2xx/304 answer carries an ETag; the Atom fallback does not,
      // so it never replaces the cached validator.
      final String? nextEtag = result.etag;
      if (nextEtag != null && nextEtag.isNotEmpty && nextEtag != etag) {
        await prefs.setString(etagKey, nextEtag);
      }

      final DateTime now = DateTime.now();
      final AppVersion installed =
          (AppVersion.tryParse(AppInfo.versionName) ??
                  const AppVersion(major: 0, minor: 0, patch: 0))
              .withBuild(AppInfo.buildNumber);

      // No manifest (nothing published, or 304 Not Modified) and a release that
      // is not newer both mean the same thing to the user: up to date.
      final UpdateCheck? found = result.check;
      if (found == null || !found.manifest.isNewerThan(installed)) {
        state = UpdateState(
          status: UpdateStatus.upToDate,
          lastChecked: now,
          skippedVersionCode: previous.skippedVersionCode,
          requestId: requestId,
        );
        await _rememberCheck(now);
        return;
      }

      if (!force &&
          found.manifest.versionCode > 0 &&
          previous.skippedVersionCode == found.manifest.versionCode) {
        state = UpdateState(
          status: UpdateStatus.upToDate,
          lastChecked: now,
          skippedVersionCode: previous.skippedVersionCode,
          requestId: requestId,
        );
        await _rememberCheck(now);
        return;
      }

      state = UpdateState(
        status: UpdateStatus.available,
        manifest: found.manifest,
        source: found.source,
        lastChecked: now,
        skippedVersionCode: previous.skippedVersionCode,
        requestId: requestId,
      );
      await _rememberCheck(now);
    } catch (error) {
      if (force) {
        // Honest failure: never claim "up to date" when the check did not run.
        state = previous.copyWith(
          status: UpdateStatus.failed,
          error: error.toString(),
        );
      } else {
        // Background: restore the previous state untouched. No error, no
        // timestamp, so the next resume retries.
        state = previous;
      }
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
