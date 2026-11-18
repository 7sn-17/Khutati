/// Compile-time identity of this build.
///
/// Kept in one Dart constant so the update checker, Settings and the release CI
/// manifest agree. `tools/check_version.mjs` guards it against `pubspec.yaml`.
abstract final class AppInfo {
  static const String versionName = '0.4.0';
  static const int buildNumber = 20;

  static const String versionLabel = '$versionName ($buildNumber)';
  static String get tag => 'v$versionName';
}
