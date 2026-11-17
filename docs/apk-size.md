# APK size

The app is a normal offline study app, so the shipped download must stay small.
CI now reports both APK sizes in the job summary and fails when either grows
past its ceiling.

## Before

The release job never produced an APK: R8 failed on unresolved Play Core
classes referenced by Flutter's embedding (`minifyReleaseWithR8`). The only
downloadable build was the debug job's universal APK, which bundles the debug
engine for `armeabi-v7a`, `arm64-v8a` and `x86_64`. The extracted APK was about
200 MB; even the zipped CI artifact was 96,350,289 bytes (~92 MiB) for run
[44062995542](https://github.com/7sn-17/Khutati/actions/runs/44062995542).

## After

From run [44079881006](https://github.com/7sn-17/Khutati/actions/runs/44079881006)
(commit `e3cc590`, after the launcher-icon and font-registration fixes):

| Artifact | Before | After |
| --- | --- | --- |
| Release `Khutati.apk` (arm64) | none (build failed) | 20,078,660 bytes (19.1 MiB) |
| Debug `app-debug.apk` | universal, ~200 MB extracted | 87,562,306 bytes (83.5 MiB) |
| Debug artifact (zipped) | 96,350,289 bytes (91.9 MiB) | 50,408,977 bytes (48.1 MiB) |
| Release artifact (zipped) | none | 11,017,790 bytes (10.5 MiB) |

The first size-fix run (commit `6286698`) measured 20,696,051 bytes for the
release APK and 91,109,098 bytes for the debug APK. Declaring the bundled fonts
in `pubspec.yaml` and dropping the `google_fonts` runtime package removed its
code and duplicate asset handling, saving about 0.6 MiB in release and 3.5 MiB
in debug.

The release APK is published as `Khutati.apk` with `update.json` on the
`latest` GitHub release.

## What reduced it

1. **R8 unbroken.** `proguard-rules.pro` now marks the unused Play Core
   deferred-component classes as `dontwarn`, so `minifyReleaseWithR8` completes.
   Release keeps `isMinifyEnabled` and `isShrinkResources` from
   `android/app/build.gradle.kts`, plus `--obfuscate --split-debug-info` and
   icon tree-shaking in the Flutter build.
2. **One ABI.** Release was already arm64-only. The debug build now passes
   `--target-platform android-arm64`, dropping the two other debug engines
   (~half the artifact).
3. **Existing trimming.** `resourceConfigurations += ["ar"]`, no deferred
   components, and fonts that are declared once (instead of both bundled as
   assets and registered by `google_fonts`) keep the release APK near 20 MiB.

## Guards

`.github/workflows/android.yml`:

- Release: fails if `Khutati.apk` exceeds 40 MiB.
- Debug: fails if the arm64 `app-debug.apk` exceeds 90 MiB.
- Both print the exact byte size and MiB in the GitHub step summary.

The ceilings are deliberately above today's sizes (2x for release, close to
today's debug size) so a real regression fails CI rather than a minor
fluctuation. Tighten them when a dependency intentionally grows the app.

## Signing caveat

CI requires the four `ANDROID_KEYSTORE_*` / `ANDROID_KEY_*` secrets and fails
rather than publishing a debug-signed APK. It also verifies the APK certificate
against the keystore before release. That does not change the size, but Android
will not install it over an APK signed with a different key. See
[`release-signing.md`](release-signing.md).
