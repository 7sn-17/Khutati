/// Version and manifest model for in-app updates.
///
/// Pure Dart so the comparison rules are unit-tested without Flutter, network
/// or Android. The repository only ever hands a validated manifest to the app.
library;

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => 'UpdateException: $message';
}

enum UpdateSource { supabase, github }

class AppVersion implements Comparable<AppVersion> {
  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.build = 0,
  });

  final int major;
  final int minor;
  final int patch;

  /// Android versionCode when known; 0 otherwise.
  final int build;

  static final RegExp _pattern =
      RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?');

  static AppVersion? tryParse(String raw) {
    final RegExpMatch? match = _pattern.firstMatch(raw.trim());
    if (match == null) return null;
    return AppVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      build: match.group(4) == null ? 0 : int.parse(match.group(4)!),
    );
  }

  AppVersion get withoutBuild => AppVersion(major: major, minor: minor, patch: patch);

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  String get label => '$major.$minor.$patch';

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch &&
      other.build == build;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);

  @override
  String toString() => build > 0 ? '$label+$build' : label;
}

/// Everything the UI needs to describe and link to a release.
class UpdateManifest {
  const UpdateManifest({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    this.notes,
    this.pageUrl,
    this.publishedAt,
    this.mandatory = false,
    this.minSupportedVersion,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String? notes;
  final String? pageUrl;
  final DateTime? publishedAt;
  final bool mandatory;
  final String? minSupportedVersion;

  AppVersion? get version => AppVersion.tryParse(versionName);

  /// True when this release should replace [installed].
  ///
  /// Semantic version wins; the Android build number breaks ties so a rebuilt
  /// APK with the same marketing version can still be delivered.
  bool isNewerThan(AppVersion installed) {
    final AppVersion? release = version;
    if (release == null) return false;

    final int semantic = release.withoutBuild.compareTo(installed.withoutBuild);
    if (semantic != 0) return semantic > 0;

    final int releaseBuild = versionCode > 0 ? versionCode : release.build;
    return releaseBuild > installed.build;
  }

  factory UpdateManifest.fromJson(
    Map<String, dynamic> json, {
    String? fallbackApkUrl,
    String? fallbackPageUrl,
  }) {
    final String versionName = _firstString(
          json,
          <String>['versionName', 'version_name', 'version', 'tag_name'],
        ) ??
        '';
    if (versionName.isEmpty) {
      throw const UpdateException('manifest has no version name');
    }

    final String apkUrl =
        _firstString(json, <String>['apkUrl', 'apk_url', 'downloadUrl', 'url']) ??
            fallbackApkUrl ??
            '';
    if (apkUrl.isEmpty) {
      throw const UpdateException('manifest has no APK url');
    }

    final String? published = _firstString(
      json,
      <String>['publishedAt', 'published_at', 'created_at'],
    );

    return UpdateManifest(
      versionName: versionName.replaceFirst(RegExp(r'^v'), ''),
      versionCode: _firstInt(
            json,
            <String>['versionCode', 'version_code', 'buildNumber', 'build_number'],
          ) ??
          0,
      apkUrl: apkUrl,
      notes: _firstString(json, <String>['notes', 'notes_ar', 'releaseNotes', 'body']),
      pageUrl: _firstString(json, <String>['pageUrl', 'page_url', 'html_url', 'htmlUrl']) ??
          fallbackPageUrl,
      publishedAt: published == null ? null : DateTime.tryParse(published),
      mandatory: _firstBool(json, <String>['mandatory', 'force']) ?? false,
      minSupportedVersion: _firstString(
        json,
        <String>['minSupportedVersion', 'min_supported_version'],
      ),
    );
  }

  factory UpdateManifest.fromSupabaseRow(Map<String, dynamic> row) =>
      UpdateManifest.fromJson(row);

  factory UpdateManifest.fromGitHubRelease(
    Map<String, dynamic> release, {
    String? updateManifestApkUrl,
    String? updateManifestNotes,
    String? updateManifestVersionName,
  }) {
    final String tag =
        _firstString(release, <String>['tag_name', 'name']) ?? '';
    final List<Map<String, dynamic>> assets =
        listOfMaps(release['assets']);

    String? apkUrl;
    for (final Map<String, dynamic> asset in assets) {
      final String? name = _firstString(asset, <String>['name']);
      final String? url =
          _firstString(asset, <String>['browser_download_url', 'url']);
      if (name == null || url == null) continue;
      if (name.endsWith('.apk') && name == 'Khutati.apk') {
        apkUrl = url;
        break;
      }
      if (name.endsWith('.apk') && name.contains('arm64-v8a')) {
        apkUrl = url;
        break;
      }
      if (name.endsWith('.apk')) apkUrl ??= url;
    }

    final String? published =
        _firstString(release, <String>['published_at', 'created_at']);

    return UpdateManifest(
      versionName: (updateManifestVersionName ?? tag).replaceFirst(RegExp(r'^v'), ''),
      versionCode: 0,
      apkUrl: updateManifestApkUrl ?? apkUrl ?? '',
      notes: updateManifestNotes ??
          _firstString(release, <String>['body', 'name']),
      pageUrl: _firstString(release, <String>['html_url']),
      publishedAt: published == null ? null : DateTime.tryParse(published),
    );
  }
}

class UpdateCheck {
  const UpdateCheck({required this.manifest, required this.source});

  final UpdateManifest manifest;
  final UpdateSource source;
}

// Tolerant readers shared with the repository. Kept here so all manifest
// shapes (Supabase row, generated `update.json`, GitHub release) agree.
String? _firstString(Map<String, dynamic> map, List<String> keys) {
  for (final String key in keys) {
    final Object? value = map[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

int? _firstInt(Map<String, dynamic> map, List<String> keys) {
  for (final String key in keys) {
    final Object? value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final int? parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

bool? _firstBool(Map<String, dynamic> map, List<String> keys) {
  for (final String key in keys) {
    final Object? value = map[key];
    if (value is bool) return value;
    if (value is String) {
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
  }
  return null;
}

/// Converts a decoded JSON list into maps, ignoring anything else.
List<Map<String, dynamic>> listOfMaps(Object? value) {
  if (value is! List<Object?>) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final Object? entry in value)
      if (entry is Map<String, dynamic>) entry
      else if (entry is Map<Object?, Object?>) entry.cast<String, dynamic>(),
  ];
}
