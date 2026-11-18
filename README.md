# خطتي (Khutati)

تطبيق عربي أولاً، يعمل دون إنترنت، لخطة دراسة من 68 يوماً. يُحفظ التقدّم محلياً في
SQLite فوراً، ويُرفع إلى السحابة على دفعات، ويعمل مؤقّت التركيز في الخلفية عبر خدمة
Kotlin أصلية. النموذج HTML (`خطتي اليومية، الإصدار 3.html`) هو المرجع البصري الوحيد،
ومحتوى الخطة يأتي حصراً من `khutati_plan_data.json`.

> **للمطوّرين والوكلاء:** ابدأ بـ [`PROJECT_CONTEXT.md`](PROJECT_CONTEXT.md) ثم
> [`ARCHITECTURE.md`](ARCHITECTURE.md). هذا الملف يشرح البناء والنشر فقط.

---

An Arabic-first, offline-first Android study-plan app for a fixed 68-day
curriculum. Progress is written to SQLite immediately and uploaded to Supabase in
batches; the focus timer runs in a native Kotlin foreground service with exact
alarms. The UI is Arabic and RTL by design.

| | |
|---|---|
| Package | `com.khutati.app` |
| Current version | **0.8.1 (31)** |
| Min Android | 8.0 (API 26) |
| Stack | Flutter 3.29.3 · Riverpod · Drift · Supabase · Kotlin |
| CI | GitHub Actions — `.github/workflows/android.yml` |

---

## 1. Requirements

- **Flutter 3.29.x** (Dart 3.7+) — CI pins `3.29.3`
- **JDK 17** (Temurin in CI)
- **Node.js 18+** — only for the scripts in `tools/`
- **Android SDK** with build-tools (`apksigner` is used to verify releases)
- On Linux, **`libsqlite3-dev`** for the Drift database tests

## 2. Build and run locally

```bash
flutter pub get

# Generated sources are NOT committed. Both steps are required.
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs

flutter analyze
flutter test
flutter run
```

The app runs without Supabase credentials: it starts as a guest and the login
button reports that sign-in is not configured for this build. To enable auth and
sync locally:

```bash
flutter run \
  --dart-define=KHUTATI_SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=KHUTATI_SUPABASE_ANON_KEY=<anon-key>
```

Guards that also run in CI:

```bash
node tools/extract_tokens.mjs --check      # tokens match the HTML prototype
node tools/check_version.mjs               # AppInfo matches pubspec.yaml
node tools/validate_plan_data.mjs          # 21 dataset checks
node tools/validate_plan_data.mjs --self-test
```

## 3. Project structure

```
lib/
  app/        entry, router, shell, theme, transitions
  core/       design system, device bridges, notifications, settings, sound
  data/       Drift tables + repositories + plan import + cloud sync
  domain/     pure Dart rules (calendar, progress, step state)
  features/   onboarding · today · plan · focus · achievements · settings · auth · updates
android/      Kotlin: MainActivity, FocusTimerService, FocusAlarmReceiver, FocusEvents
supabase/     SQL migrations (sync tables, update manifest)
design/       tokens.json + HTML reference screens
tools/        Node guards for tokens, dataset, version, launcher icons
docs/         focused notes: date resolution, updates, APK size, signing
test/         130 tests (domain, data, design parity, updates, launch, widgets)
```

## 4. Design system

Every widget is a direct transcription of a rule in the prototype — no personal
interpretation. Tokens are generated, never typed by hand:
`HTML → design/tokens.json → lib/core/design/tokens.dart`.

| Widget | Prototype source |
|---|---|
| `KCard` | `.hero` / `.pd` — thin border, hexagon pattern, optional accent |
| `KPill` | `.pill` — 32dp capsule with a gold value |
| `KTag` | `.tag` — solid subject colour, dark text |
| `KChip` | `.chip` — 52dp step key, filled card, thin progress bar |
| `KButton` | `.btn` / `.btn2` — 44dp, red fill or thin outline |
| `KProgressBar` | `.bar` — 8dp, rounded, `--redtx` |
| `KProgressRing` | `.ring` — 240dp, r104, 10px stroke, round cap, −90° start |
| `KEcgLine` | `.ecg` — same path, mirrored, drawn in 600 ms |
| `KBreakDivider` | `.br` — centred label between two hairlines |
| `KSectionHeader` | `h2` — 24/12 margins |
| `showKToast` / `KConfetti` | `#toast` / `.cf` — inverted capsule, 26-piece burst |
| `KBrandMark` | Telegram/WhatsApp marks from Simple Icons, in the About modal |
| `KDialog` | modal surface — tinted scrim, 28px radius, `KButton` actions |
| `KPressable` / `KInkSurface` | the tactile layer — 0.96 squish, clipped ripple, sound on tap |

`/gallery` renders all of them against the live theme (opened from Today in debug
builds). Tests compare the ECG path, ring geometry, hexagon tile and navigation
icons against the HTML so the prototype stays authoritative.

## 5. CI/CD

Runs on every push to `main`, every `v*` tag, every pull request, and manually
(`workflow_dispatch`). Concurrency cancels superseded runs on the same ref.

### Job 1 — `verify` (the gate)

| Step | Fails when |
|---|---|
| `flutter pub get` | dependency resolution breaks |
| `apt-get install libsqlite3-dev` | (setup) |
| `flutter gen-l10n` | ARB keys are missing or duplicated |
| `build_runner build` | Drift schema or generated code is broken |
| `extract_tokens.mjs --check` | tokens drifted from the prototype |
| `check_version.mjs` | `AppInfo` ≠ `pubspec.yaml` |
| `validate_plan_data.mjs` | dataset no longer reconciles with the PDF |
| `validate_plan_data.mjs --self-test` | the validator stopped catching corruption |
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | **errors** fail; warnings/infos are printed |
| `flutter test --reporter expanded` | any failing test |

### Job 2 — `build-release` (only after `verify` passes)

1. Checks `release_notes/ar.txt` contains Arabic characters.
2. Decodes the keystore from secrets and opens it with `keytool` **before** the
   long Gradle build, so a bad secret fails fast.
3. Builds one arm64 APK, obfuscated, with split debug info:
   ```bash
   flutter build apk --release --split-per-abi \
     --target-platform android-arm64 \
     --obfuscate --split-debug-info=build/symbols \
     --dart-define=KHUTATI_SUPABASE_URL=... \
     --dart-define=KHUTATI_SUPABASE_ANON_KEY=...
   ```
4. Renames the output to `Khutati.apk`.
5. Verifies the APK with `apksigner` and compares its SHA-256 fingerprint to the
   keystore's. A debug-signed APK is refused.
6. Fails if the APK exceeds **40 MiB** (currently ~21 MiB).
7. Writes `update.json` from the pubspec version plus `release_notes/ar.txt`.
8. Uploads the artifact and publishes a GitHub Release under `v<versionName>`.

### Required GitHub secrets (names only — never commit values)

| Secret | Used for |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | base64 of the release `.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |
| `KHUTATI_SUPABASE_URL` | injected with `--dart-define` |
| `KHUTATI_SUPABASE_ANON_KEY` | injected with `--dart-define` (public by design, RLS-scoped) |

The service-role key is **never** used by the app and must never be added here.

## 6. Supabase setup

### 6.1 Database

Create a project, then run both migrations in the SQL editor (or
`supabase db push` with the CLI):

```
supabase/migrations/202611170001_app_updates.sql   -- legacy update manifest (superseded)
supabase/migrations/202611180001_sync_tables.sql   -- user_task_states, user_step_states, focus_sessions + RLS
supabase/migrations/202611190001_app_versions.sql  -- public release history (update waterfall)
```

Both are idempotent. After applying, confirm RLS is enabled on all three sync
tables and the `*_owner` policies exist; `anon` must have no grants on them.

### 6.2 Google sign-in

1. **Google Cloud Console → Credentials:**
   - **Web client** — its client id is the app's `serverClientId`, defined in
     `lib/features/auth/data/supabase_auth.dart` as `googleWebClientId`. Replace
     it there if you use your own project.
   - **Android client** — package `com.khutati.app` plus the **release keystore
     SHA-1** (and SHA-256). Without it Credential Manager returns no ID token.
2. **Supabase Dashboard → Authentication → Providers → Google:** enable it and
   paste the Web client id and secret.
3. **Supabase Dashboard → Authentication → Providers → Google → Skip nonce
   check: ON.**

Step 3 is mandatory. The native Credential Manager does not mint a nonce, so
Supabase's nonce verification must be disabled **on the server**
(`external_google_skip_nonce_check = true`). It is not a Dart parameter and must
never be emulated by weakening the client. If it is off, the Google picker
succeeds and the token exchange fails.

4. Authentication → URL configuration: no redirect URLs are needed for the native
   flow, but keep the site URL set.

### 6.3 Client configuration

The URL and anon key are compile-time values:

```dart
String.fromEnvironment('KHUTATI_SUPABASE_URL')
String.fromEnvironment('KHUTATI_SUPABASE_ANON_KEY')
```

If either is empty, `SupabaseConfig.isConfigured` is false, `SupabaseAuth` stays
uninitialized, `CloudSyncService.syncNow` returns early, and the app works fully
offline as a guest. This is intentional: a contributor build must not write to
production.

### 6.4 Update manifest

`app_versions` is the last step of the update waterfall and is read with the
anon key (public by design). CI upserts a row on every release, so the table
normally needs no manual work; to publish one by hand:

```sql
insert into public.app_versions (version, download_url, release_notes)
values
  ('0.8.7+37',
   'https://github.com/7sn-17/Khutati/releases/latest/download/Khutati.apk',
   'إصلاحات وتحسينات…')
on conflict (version) do update
  set download_url = excluded.download_url,
      release_notes = excluded.release_notes;
```

The client queries the newest row, races it against the GitHub Releases API and
keeps the higher `versionCode`.

## 7. Versioning and release notes

Three places must agree; two are enforced by CI.

| File | Field | Enforced by |
|---|---|---|
| `pubspec.yaml` | `version: 0.8.1+31` | source of truth for the build |
| `lib/core/app_info.dart` | `versionName = '0.8.1'`, `buildNumber = 31` | `tools/check_version.mjs` |
| `release_notes/ar.txt` | Arabic notes for this release | CI requires Arabic characters |

Release procedure:

1. Bump `versionName` **and** `buildNumber` in both files. The `+31` is the
   Android `versionCode`; it must increase or the update checker will not see the
   new build.
2. Update `release_notes/ar.txt`: first line `إصدار X.Y.Z — …`, then bullets, then
   a footer `• الإصدار: X.Y.Z (build). بياناتك المحلية وخطتك تبقى محفوظة…`.
3. Run `node tools/check_version.mjs`.
4. Commit and push to `main`; CI publishes `vX.Y.Z` automatically. Push a `v*`
   tag only when you want to force a specific tag name.
5. The release carries `Khutati.apk` and `update.json`. The in-app checker reads
   the Supabase row first and falls back to the GitHub manifest.

Never reuse a build number: the dialog compares `versionCode`, so re-publishing
the same code hides the update from installed devices.

## 8. Conventions

- No colour, radius or font size outside `lib/core/design/tokens.dart`.
- No plan content outside `khutati_plan_data.json`.
- Shared user-facing strings live in `lib/l10n/app_ar.arb` and are read through
  `context.l10n`; one-off copy may be an Arabic literal in the widget.
- Use direction-aware properties (`start`/`end`), never `left`/`right`.
- Numbers are Western Arabic digits everywhere (PRD §13.1); dates and durations
  go through `core/utils/format.dart`.
- Dialogs are `KDialog`; there is no `showDialog`/`AlertDialog` in `lib/`.

## 9. Where to read more

| Document | Contents |
|---|---|
| [`PROJECT_CONTEXT.md`](PROJECT_CONTEXT.md) | AI handoff: stack, features, hard rules, `bd` workflow, gotchas |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | write path, 4-tap state machine, native bridge, schema, sync semantics |
| [`docs/date-resolution.md`](docs/date-resolution.md) | how "today" is resolved from the local clock |
| [`docs/updates.md`](docs/updates.md) | update channels and manifest details |
| [`docs/release-signing.md`](docs/release-signing.md) | keystore setup and fingerprint checks |
| [`docs/apk-size.md`](docs/apk-size.md) | size budget and the 40 MiB guard |
| [`docs/data-validation.md`](docs/data-validation.md) | the 21 dataset checks |
| [`AGENTS.md`](AGENTS.md) · [`CLAUDE.md`](CLAUDE.md) | agent instructions and Beads integration |

## 10. Troubleshooting

**`Could not find org.jetbrains.kotlin:kotlin-stdlib:2.0.21` in the Gradle build.**
Transient failure of `plugins.gradle.org`. Nothing in `android/` is wrong — re-run
the failed job before touching Gradle files.

**`Target of URI doesn't exist: 'app_database.g.dart'`.** Codegen has not run:
`dart run build_runner build --delete-conflicting-outputs`.

**`package:flutter_lints/flutter.yaml` cannot be resolved.** You are running
`dart analyze` without a Flutter SDK. Use `flutter analyze` or CI.

**Sign-in opens the account picker, then fails.** "Skip nonce check" is off in the
Supabase Google provider, or the Android OAuth client lacks the release SHA-1.

**Progress saves but never reaches another device.** The outbox is not draining:
check the build has both `--dart-define` values and that the three sync tables
have their RLS policies.

**The alert does not fire with the screen off.** Exact alarms are denied. The app
prompts on first launch and offers a shortcut in Settings; battery optimisation
can also kill the service.
