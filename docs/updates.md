# In-app updates

The app checks for a newer APK without blocking startup or breaking offline use.

## Sources and order

1. **Supabase** — `public.app_updates` via PostgREST. Used when
   `KHUTATI_SUPABASE_URL` and `KHUTATI_SUPABASE_ANON_KEY` are compiled in
   (`--dart-define`). This is the primary channel because rows can be edited
   from the dashboard without shipping a release.
2. **GitHub Releases** — `7sn-17/Khutati`, newest non-draft release. Every
   release built by CI carries `update.json` plus `Khutati.apk`, so this
   fallback needs no secrets and works even if Supabase is down.

Both sources are consulted and the newest version wins, so a stale Supabase row
can never hide a newer GitHub release; Supabase wins ties. A failed source is
ignored when the other one succeeds. If both fail, the UI shows a soft message
and the plan keeps working offline.

## Client behaviour

- `UpdateBootstrap` runs a silent check after the first frame and on resume.
- Checks are throttled to once every 6 hours (`update_last_check_ms`); a failed
  check retries after 15 minutes (`update_last_attempt_ms`) so offline launches
  do not hammer the network.
- A skipped version is stored in `update_skipped_version_code`; "check now" in
  Settings bypasses the skip and the throttle.
- Versions compare semantically first, then by Android `versionCode`, so a
  rebuilt APK with the same marketing version can still be delivered.
- Only `https://` APK URLs are accepted. The app ships a single `Khutati.apk`
  built for modern 64-bit ARM devices (arm64-v8a) only.
- "Update now" opens the APK in the browser; Android shows the install
  confirmation. Silent install is intentionally not used (no
  `REQUEST_INSTALL_PACKAGES`), which suits a private side-loaded app.

## Supabase setup

Apply `supabase/migrations/202611170001_app_updates.sql` (the Supabase MCP or
the SQL editor both work). The table is public read-only through RLS; writes
stay in the dashboard or service role.

Publish a release by inserting/updating a row:

```sql
insert into public.app_updates
  (platform, channel, version_name, version_code, apk_url, notes)
values
  ('android', 'stable', '0.3.0', 3,
   'https://github.com/7sn-17/Khutati/releases/download/v0.3.0/Khutati.apk',
   'إصلاحات وتحسينات لمؤقت التركيز.');
```

`platform` must be `android` and `channel` must be `stable`.

Then provide the build-time config as repository secrets (or local
`--dart-define`s):

```
KHUTATI_SUPABASE_URL=https://<project-ref>.supabase.co
KHUTATI_SUPABASE_ANON_KEY=<anon/publishable key>
```

The anon key is public by design; never use the service-role key here.

## GitHub fallback

`.github/workflows/android.yml` writes `update.json` next to the APKs:

```json
{
  "versionName": "0.2.0",
  "versionCode": 2,
  "notes": "commit subject",
  "apkUrl": "https://github.com/7sn-17/Khutati/releases/download/latest/Khutati.apk",
  "pageUrl": "https://github.com/7sn-17/Khutati/releases/tag/latest",
  "publishedAt": "2026-11-17T12:00:00Z"
}
```

Tagged releases publish `vX.Y.Z`; pushes to `main` publish a rolling `latest`
pre-release. The client reads `update.json` from the newest release and falls
back to the release's `Khutati.apk` asset if the manifest is missing.

## Release signing

Android only installs an update over an existing app when both APKs share the
same signing certificate. Configure the four `ANDROID_KEYSTORE_*` /
`ANDROID_KEY_*` repository secrets described in the README, and keep the
keystore backed up outside the repository. Losing it means every user has to
uninstall the app once before installing a later build.

CI now **requires** those secrets: the release job fails rather than publishing
a debug-signed APK, validates the keystore with `keytool`, and verifies the
built APK's SHA-256 certificate fingerprint against the keystore before the
release is written. See [`release-signing.md`](release-signing.md). Local
release builds still fall back to debug signing when `android/key.properties`
is absent.

## Version discipline

`lib/core/app_info.dart` must match `pubspec.yaml`. CI runs
`node tools/check_version.mjs` and fails on any mismatch, because the check
compares the installed build number with the manifest.

Bump both the marketing version and the build number before publishing a new
release (`flutter build` uses `version:` as `versionName+versionCode`). Merely
pushing another commit does not create a newer update, because the build number
stays the same. An installed build whose `versionCode` equals the manifest's is
reported as up to date; raising it is what makes "check now" offer the APK.
