import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/app_release.dart';

/// Update discovery: Supabase first, GitHub Releases as the offline-safe
/// fallback (the repository is public, so the fallback needs no secrets).
///
/// Three defences keep a background check from ever burning GitHub's anonymous
/// quota (60 requests/hour per IP):
///
/// 1. the controller's 60-minute cooldown, so a cold start plus a resume is not
///    two requests;
/// 2. conditional requests — the caller passes the stored ETag and GitHub
///    answers `304 Not Modified` for free when nothing changed;
/// 3. the `releases.atom` feed, a static file on github.com, used only when the
///    API itself fails (typically `403` rate limiting).
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

  /// Asset name CI publishes for every release; the Atom fallback has no asset
  /// list, so it reconstructs the download URL from the tag.
  static const String apkAssetName = 'Khutati.apk';

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

  /// Runs one check. [etag] is the ETag stored by the previous successful
  /// GitHub response; pass it to make the request conditional.
  ///
  /// Throws [UpdateException] only when **every** source failed. "No release
  /// exists" and "304 Not Modified" are successes and return a result with no
  /// manifest — the caller must not report those as errors.
  Future<UpdateCheckResult> check({String? etag}) async {
    // Both sources race. Sequential checks made a manual tap wait for Supabase
    // before GitHub even started; running them together keeps "Check for
    // updates" instant and still lets the newer of the two win.
    final Future<_SourceResult> supabaseFuture = _supabaseConfigured
        ? _fetchSupabase()
        : Future<_SourceResult>.value(const _SourceResult.ok(null));
    final Future<_GithubOutcome> githubFuture = _fetchGithub(etag);

    final _SourceResult supabase = await supabaseFuture;
    final _GithubOutcome github = await githubFuture;

    UpdateManifest? best = supabase.manifest;
    UpdateSource source = UpdateSource.supabase;
    if (github.manifest != null &&
        (best == null || _isNewerManifest(github.manifest!, best))) {
      best = github.manifest;
      source = UpdateSource.github;
    }
    if (best != null) {
      return UpdateCheckResult(
        check: UpdateCheck(manifest: best, source: source),
        etag: github.etag,
      );
    }

    // A 304 is only trustworthy as "nothing new" when the other configured
    // source also answered; otherwise we would be claiming to be up to date on
    // the strength of a source that may be hiding a release.
    if (github.notModified && supabase.ok) {
      return UpdateCheckResult.notModified(etag: github.etag ?? etag);
    }

    if (supabase.ok && github.ok) {
      // Every source answered and nothing has been published yet.
      return UpdateCheckResult(etag: github.etag);
    }

    final List<String> problems = <String>[
      if (!supabase.ok) 'supabase: ${supabase.error}',
      if (!github.ok) 'github: ${github.error}',
    ];
    throw UpdateException(problems.join(' · '));
  }

  Future<_SourceResult> _fetchSupabase() async {
    try {
      return _SourceResult.ok(await _fromSupabase());
    } catch (error) {
      return _SourceResult.failed('$error');
    }
  }

  /// GitHub, with two layers of fallback: a conditional API call first, then
  /// the static Atom feed if the API refuses or times out.
  Future<_GithubOutcome> _fetchGithub(String? etag) async {
    try {
      return await _fromGitHubApi(etag: etag);
    } catch (apiError) {
      try {
        final UpdateManifest? manifest = await _fromAtom();
        // An empty or unparseable feed tells us nothing; reporting it as "no
        // update" would be a guess dressed up as an answer.
        if (manifest == null) {
          return _GithubOutcome(error: '$apiError · atom: no release entry');
        }
        return _GithubOutcome(manifest: manifest);
      } catch (atomError) {
        return _GithubOutcome(error: '$apiError · atom: $atomError');
      }
    }
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

  Future<_GithubOutcome> _fromGitHubApi({String? etag}) async {
    final Uri uri = Uri.parse(
      'https://api.github.com/repos/$_githubRepo/releases',
    ).replace(queryParameters: <String, String>{'per_page': '10'});

    final http.Response response = await _get(
      uri,
      headers: <String, String>{
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        // GitHub requires a User-Agent; a stable one avoids anonymous 403s.
        'User-Agent': 'Khutati-Android',
        // Conditional request: unchanged releases cost no quota.
        if (etag != null && etag.isNotEmpty) 'If-None-Match': etag,
      },
    );
    final String? responseEtag = _header(response, 'etag') ?? etag;

    if (response.statusCode == 304) {
      return _GithubOutcome(notModified: true, etag: responseEtag);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateException('HTTP ${response.statusCode} from ${uri.host}');
    }

    final Object? decoded = _decodeJson(response);

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
        if (name.endsWith('.apk') && name == apkAssetName) {
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

    return _GithubOutcome(manifest: best, etag: responseEtag);
  }

  /// `https://github.com/<repo>/releases.atom` is a static file, not an API
  /// endpoint, so it keeps working when the API returns `403` for rate limiting.
  ///
  /// The feed carries the tag and the release page but no asset list, so the
  /// download URL is reconstructed from the convention CI publishes
  /// (`Khutati.apk` on every release). If that ever 404s, the release page is
  /// still available to the user.
  Future<UpdateManifest?> _fromAtom() async {
    final Uri uri = Uri.parse('https://github.com/$_githubRepo/releases.atom');
    final http.Response response = await _get(
      uri,
      headers: <String, String>{
        'Accept': 'application/atom+xml, application/xml;q=0.9',
        'User-Agent': 'Khutati-Android',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateException('HTTP ${response.statusCode} from ${uri.host}');
    }
    return _parseAtom(utf8.decode(response.bodyBytes));
  }

  UpdateManifest? _parseAtom(String xml) {
    // Entries are newest-first. Only the first one that carries a parseable
    // version tag matters.
    for (final RegExpMatch entry in _atomEntry.allMatches(xml)) {
      final String body = entry.group(1) ?? '';
      final String title = _unescape(
        _atomTitle.firstMatch(body)?.group(1) ?? '',
      ).trim();
      final String? pageUrl = _atomLink.firstMatch(body)?.group(1);

      // The tag in the release URL is authoritative (`v0.8.2`); the title is
      // the fallback. The `v` must stay in the download URL — GitHub asset
      // paths are built from the tag exactly as pushed.
      String tag = title;
      final Uri? page = pageUrl == null ? null : Uri.tryParse(pageUrl);
      final List<String> segments = page?.pathSegments ?? const <String>[];
      if (segments.length >= 2 && segments[segments.length - 2] == 'tag') {
        tag = segments.last;
      }

      final AppVersion? version = AppVersion.tryParse(tag);
      if (version == null) continue;

      final String? updated = _atomUpdated.firstMatch(body)?.group(1);

      return UpdateManifest(
        // Displayed version drops the `v`, like every other manifest source.
        versionName: tag.replaceFirst(RegExp(r'^v'), ''),
        // The feed has no Android build number; the semantic version decides.
        versionCode: 0,
        apkUrl:
            'https://github.com/$_githubRepo/releases/download/$tag/$apkAssetName',
        pageUrl: pageUrl,
        publishedAt: updated == null ? null : DateTime.tryParse(updated),
      );
    }
    return null;
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) {
    return _client.get(uri, headers: headers).timeout(_timeout);
  }

  Future<Object?> _getJson(Uri uri, {Map<String, String>? headers}) async {
    final http.Response response = await _get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateException('HTTP ${response.statusCode} from ${uri.host}');
    }
    return _decodeJson(response);
  }

  /// Decode explicitly as UTF-8: `response.body` decodes per the response's
  /// charset and defaults to Latin-1 when none is declared, which corrupts
  /// Arabic (and any non-ASCII) release notes into mojibake.
  static Object? _decodeJson(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes));

  static String? _header(http.Response response, String name) {
    for (final MapEntry<String, String> header in response.headers.entries) {
      if (header.key.toLowerCase() == name) return header.value;
    }
    return null;
  }

  static final RegExp _atomEntry = RegExp(
    r'<entry\b[^>]*>([\s\S]*?)</entry>',
    caseSensitive: false,
  );
  static final RegExp _atomTitle = RegExp(
    r'<title\b[^>]*>([\s\S]*?)</title>',
    caseSensitive: false,
  );
  static final RegExp _atomLink = RegExp(
    r'<link\b[^>]*\brel="alternate"[^>]*\bhref="([^"]+)"',
    caseSensitive: false,
  );
  static final RegExp _atomUpdated = RegExp(
    r'<updated\b[^>]*>([\s\S]*?)</updated>',
    caseSensitive: false,
  );

  static String _unescape(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  static void _requireHttps(String url, String source) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw UpdateException('$source returned an insecure APK url');
    }
  }
}

class _SourceResult {
  const _SourceResult.ok(this.manifest) : error = null;
  const _SourceResult.failed(this.error) : manifest = null;

  final UpdateManifest? manifest;
  final String? error;

  bool get ok => error == null;
}

class _GithubOutcome {
  const _GithubOutcome({
    this.manifest,
    this.etag,
    this.notModified = false,
    this.error,
  });

  final UpdateManifest? manifest;
  final String? etag;
  final bool notModified;
  final String? error;

  bool get ok => error == null;
}
