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

From run [44074164459](https://github.com/7sn-17/Khutati/actions/runs/44074164459)
(commit `6286698`):

| Artifact | Before | After |
| --- | --- | --- |
| Release `Khutati.apk` (arm64) | none (build failed) | 20,696,051 bytes (19.7 MiB) |
| Debug `app-debug.apk` | universal, ~200 MB extracted | 91,109,098 bytes (86.9 MiB) |
| Debug artifact (zipped) | 96,350,289 bytes (91.9 MiB) | 53,633,135 bytes (51.1 MiB) |
| Release artifact (zipped) | none | 11,752,301 bytes (11.2 MiB) |

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
3. **Existing trimming.** `resourceConfigurations += ["ar"]`, bundled-only
   fonts, and no deferred components keep the release APK near 20 MiB.

## Guards

`.github/workflows/android.yml`:

- Release: fails if `Khutati.apk` exceeds 40 MiB.
- Debug: fails if the arm64 `app-debug.apk` exceeds 90 MiB.
- Both print the exact byte size and MiB in the GitHub step summary.

The ceilings are deliberately above today's sizes (2x for release, close to
today's debug size) so a real regression fails CI rather than a minor
fluctuation. Tighten them when a dependency intentionally grows the app.

## Signing caveat

Without the four `ANDROID_KEYSTORE_*` / `ANDROID_KEY_*` secrets the release APK
is debug-signed (CI prints a warning). That does not change its size, but
Android will not install it over an APK signed with a different key. See
[`updates.md`](updates.md#release-signing).
