import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/app_release.dart';

/// Update discovery: Supabase first, GitHub Releases as the offline-safe
/// fallback (the repository is public, so the fallback needs no secrets).
///
/// Network failures never block the app; the controller treats them as a soft
/// error and retries on the next launch or manual check.
class UpdateRepository {
  UpdateRepository(
    this._client, {
    String? supabaseUrl,
    String? supabaseAnonKey,
    String githubRepo = defaultGithubRepo,
    Duration timeout = const Duration(seconds: 8),
  }) : _supabaseUrl = supabaseUrl ?? _envSupabaseUrl,
       _supabaseAnonKey = supabaseAnonKey ?? _envSupabaseAnonKey,
       _githubRepo = githubRepo,
       _timeout = timeout;

  static const String defaultGithubRepo = '7sn-17/Khutati';
  static const String channel = 'stable';

  // Supplied through --dart-define in CI once the Supabase project exists.
  // Without them the GitHub fallback is used directly.
  static const String _envSupabaseUrl = String.fromEnvironment(
    'KHUTATI_SUPABASE_URL',
  );
  static const String _envSupabaseAnonKey = String.fromEnvironment(
    'KHUTATI_SUPABASE_ANON_KEY',
  );

  final http.Client _client;
  final String _supabaseUrl;
  final String _supabaseAnonKey;
  final String _githubRepo;
  final Duration _timeout;

  bool get _supabaseConfigured =>
      _supabaseUrl.trim().isNotEmpty && _supabaseAnonKey.trim().isNotEmpty;

  /// Returns the newest published manifest, or `null` when no release exists.
  ///
  /// Both sources are consulted so a stale Supabase row can never hide a newer
  /// GitHub release. Supabase wins ties because it is the curated channel.
  Future<UpdateCheck?> check() async {
    final List<String> problems = <String>[];
    UpdateCheck? best;

    if (_supabaseConfigured) {
      try {
        final UpdateManifest? manifest = await _fromSupabase();
        if (manifest != null) {
          best = UpdateCheck(manifest: manifest, source: UpdateSource.supabase);
        }
      } catch (error) {
        problems.add('supabase: $error');
      }
    }

    try {
      final UpdateManifest? manifest = await _fromGitHub();
      if (manifest != null) {
        if (best == null || _isNewerManifest(manifest, best.manifest)) {
          best = UpdateCheck(manifest: manifest, source: UpdateSource.github);
        }
      }
    } catch (error) {
      problems.add('github: $error');
    }

    if (best != null) return best;
    if (problems.isEmpty) return null;
    throw UpdateException(problems.join(' · '));
  }

  static bool _isNewerManifest(
    UpdateManifest candidate,
    UpdateManifest current,
  ) {
    final AppVersion? next = candidate.version;
    final AppVersion? installed = current.version;
    if (next == null) return false;
    if (installed == null) return true;

    final int semantic = next.withoutBuild.compareTo(installed.withoutBuild);
    if (semantic != 0) return semantic > 0;

    final int nextBuild = candidate.versionCode > 0
        ? candidate.versionCode
        : next.build;
    final int currentBuild = current.versionCode > 0
        ? current.versionCode
        : installed.build;
    return nextBuild > currentBuild;
  }

  Future<UpdateManifest?> _fromSupabase() async {
    final String base = _supabaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final Uri uri = Uri.parse('$base/rest/v1/app_updates').replace(
      queryParameters: <String, String>{
        'select': '*',
        'platform': 'eq.android',
        'channel': 'eq.$channel',
        'order': 'published_at.desc',
        'limit': '1',
      },
    );

    final Object? decoded = await _getJson(
      uri,
      headers: <String, String>{
        'apikey': _supabaseAnonKey.trim(),
        'Authorization': 'Bearer ${_supabaseAnonKey.trim()}',
        'Accept': 'application/json',
      },
    );

    final List<Map<String, dynamic>> rows = listOfMaps(decoded);
    if (rows.isEmpty) return null;

    final UpdateManifest manifest = UpdateManifest.fromSupabaseRow(rows.first);
    _requireHttps(manifest.apkUrl, 'Supabase');
    return manifest;
  }

  Future<UpdateManifest?> _fromGitHub() async {
    final Uri uri = Uri.parse(
      'https://api.github.com/repos/$_githubRepo/releases',
    ).replace(queryParameters: <String, String>{'per_page': '10'});

    final Object? decoded = await _getJson(
      uri,
      headers: <String, String>{
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        // GitHub requires a User-Agent; a stable one avoids anonymous 403s.
        'User-Agent': 'Khutati-Android',
      },
    );

    UpdateManifest? best;
    for (final Map<String, dynamic> release in listOfMaps(decoded)) {
      if (release['draft'] == true) continue;

      String? apkUrl;
      String? manifestUrl;
      for (final Map<String, dynamic> asset in listOfMaps(release['assets'])) {
        final String? name = asset['name'] as String?;
        final String? url = asset['browser_download_url'] as String?;
        if (name == null || url == null) continue;
        if (name == 'update.json') manifestUrl = url;
        if (name.endsWith('.apk') && name == 'Khutati.apk') {
          apkUrl = url;
        } else if (name.endsWith('.apk') && name.contains('arm64-v8a')) {
          apkUrl ??= url;
        }
      }
      if (apkUrl == null && manifestUrl == null) continue;

      UpdateManifest? candidate;
      if (manifestUrl != null && Uri.tryParse(manifestUrl)?.scheme == 'https') {
        try {
          final Object? raw = await _getJson(Uri.parse(manifestUrl));
          if (raw is Map<String, dynamic>) {
            candidate = UpdateManifest.fromJson(
              raw,
              fallbackApkUrl: apkUrl,
              fallbackPageUrl: release['html_url'] as String?,
            );
          }
        } catch (_) {
          // A missing/broken rolling manifest must not hide the release; fall
          // back to the tag + APK asset below.
        }
      }
      candidate ??= UpdateManifest.fromGitHubRelease(
        release,
        updateManifestApkUrl: apkUrl,
      );

      if (candidate.apkUrl.isEmpty) continue;
      _requireHttps(candidate.apkUrl, 'GitHub');

      final AppVersion? candidateVersion = candidate.version;
      if (candidateVersion == null) continue;
      final AppVersion? bestVersion = best?.version;
      if (bestVersion == null ||
          candidateVersion.withoutBuild.compareTo(bestVersion.withoutBuild) >
              0) {
        best = candidate;
      }
    }

    return best;
  }

  Future<Object?> _getJson(Uri uri, {Map<String, String>? headers}) async {
    final http.Response response = await _client
        .get(uri, headers: headers)
        .timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateException('HTTP ${response.statusCode} from ${uri.host}');
    }
    return jsonDecode(response.body);
  }

  static void _requireHttps(String url, String source) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw UpdateException('$source returned an insecure APK url');
    }
  }
}
