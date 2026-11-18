# In-app updates

The app checks for a newer APK without blocking startup or breaking offline use.

## Sources and order

A strict waterfall. Each step runs only when the one before it produced nothing.

1. **GitHub Releases API** — `7sn-17/Khutati`, newest non-draft release. Every
   release built by CI carries `update.json` plus `Khutati.apk`, so this path
   needs no secrets and is the authoritative record.
2. **GitHub Atom feed** — `https://github.com/<repo>/releases.atom`, a static
   file outside the API quota, read when the API fails (typically `403` rate
   limiting). It has no asset list, so the APK URL is reconstructed as
   `releases/download/<tag>/Khutati.apk`; the tag keeps its `v`. The release
   page is kept as a secondary link.
3. **Supabase** — `public.app_versions` via PostgREST. Used when both GitHub
   paths fail, which is the case the others cannot cover: github.com being
   unreachable or blocked on the user's network. Requires
   `KHUTATI_SUPABASE_URL` and `KHUTATI_SUPABASE_ANON_KEY` at build time
   (`--dart-define`); without them the GitHub path runs alone.

A source that answers "no release" is a **success**, not a failure. Only when
every step fails does the check throw, and then the UI says so plainly.

GitHub's anonymous API allows 60 requests per hour per IP, so the GitHub path
has two extra layers:

4. **Conditional requests** — the ETag of the last successful response is stored
   and sent as `If-None-Match`. `304 Not Modified` is a successful check with no
   update and costs no quota.
5. **Cooldown** — background checks run at most once every 60 minutes, measured
   from the last successful check.

## Client behaviour

- `UpdateBootstrap` runs a silent check after the first frame and whenever the
  app returns to the foreground — **only** if the last successful check is older
  than 60 minutes (`update_last_check_ms`).
- A failed background check is silent, leaves `update_last_check_ms` untouched
  (so the next resume retries), and never changes what the user sees. There is
  no separate failure throttle: an offline launch fails fast and tries again on
  the next resume.
- A manual check from Settings bypasses the cooldown, shows the button spinner
  immediately, and reports the real outcome: "أنت تستخدم أحدث إصدار" only on
  success, and "تعذر التحقق من التحديثات. يرجى التحقق من اتصالك بالإنترنت" on
  failure. A failure is never rendered as "up to date".
- When a newer release is found, the shared branded dialog opens over the app.
  It shows the version, its Arabic "what's new" notes and the update/later/skip
  actions. Settings offers the same dialog through "عرض التحديث".
- A skipped version is stored in `update_skipped_version_code`; "check now" in
  Settings bypasses the skip and the cooldown.
- Versions compare semantically first, then by Android `versionCode`, so a
  rebuilt APK with the same marketing version can still be delivered.
- Only `https://` APK URLs are accepted, from every source. A Supabase row whose
  `download_url` is not HTTPS is treated as broken, not as a release.
- The app ships a single `Khutati.apk` built for modern 64-bit ARM devices
  (arm64-v8a) only.
- "Update now" opens the APK in the browser; Android shows the install
  confirmation. Silent install is intentionally not used (no
  `REQUEST_INSTALL_PACKAGES`), which suits a private side-loaded app.

## Supabase setup

Apply `supabase/migrations/202611190001_app_versions.sql` (the SQL editor or the
Management API both work). It creates:

```sql
create table public.app_versions (
  id uuid primary key default gen_random_uuid(),
  version text not null,
  download_url text not null,
  release_notes text,
  created_at timestamptz not null default now()
);
```

with RLS enabled and a `select` policy for `anon`/`authenticated`; a unique
index on `version` lets CI upsert instead of appending duplicates. Writes stay
with the service role.

CI mirrors every published release into the table in the
"Mirror the release into Supabase" step, so the row always describes the APK
that is actually on GitHub. That step needs one more secret:

```
KHUTATI_SUPABASE_SERVICE_KEY=<service-role key>
```

It is used only inside the release job, never compiled into the app. If the
secret is absent the step warns and skips, and the waterfall simply ends after
GitHub.

To publish a row by hand:

```sql
insert into public.app_versions (version, download_url, release_notes)
values
  ('0.8.7+37',
   'https://github.com/7sn-17/Khutati/releases/latest/download/Khutati.apk',
   'مشاركة التطبيق، واحتياطي تحديث ثالث، وقائمة متأخرة أقصر.')
on conflict (version) do update
  set download_url = excluded.download_url,
      release_notes = excluded.release_notes;
```

`version` may carry the build number (`0.8.7+37`); the client parses it with the
same `AppVersion` rules as every other source.

Then provide the build-time config as repository secrets (or local
`--dart-define`s):

```
KHUTATI_SUPABASE_URL=https://<project-ref>.supabase.co
KHUTATI_SUPABASE_ANON_KEY=<anon/publishable key>
```

The anon key is public by design; never compile the service-role key into the
app.

## GitHub

Release notes are authored in Arabic in `release_notes/ar.txt`. CI rejects a
missing or non-Arabic file, uses it for `update.json` and publishes the same text
as the GitHub release body. Edit that file as part of every release.

`.github/workflows/android.yml` writes `update.json` next to the APKs:

```json
{
  "versionName": "0.8.7",
  "versionCode": 37,
  "notes": "ملاحظات الإصدار العربية من release_notes/ar.txt",
  "apkUrl": "https://github.com/7sn-17/Khutati/releases/latest/download/Khutati.apk",
  "pageUrl": "https://github.com/7sn-17/Khutati/releases/tag/v0.8.7",
  "publishedAt": "2026-11-19T00:00:00Z"
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
