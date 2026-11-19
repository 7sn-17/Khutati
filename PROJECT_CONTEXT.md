# PROJECT_CONTEXT — AI Handoff Guide

> **Read this file first.** It is written for an AI agent (or a developer) who has
> never seen this repository and needs to make correct changes on the first try.
> Read `ARCHITECTURE.md` second for the deep technical detail, and `README.md`
> for build/release setup.
>
> Current release: **0.8.1 (31)** · Flutter 3.29.3 · Dart 3.7+ · schema v4

---

## 1. What this app is

**خطتي (Khutati)** is an Arabic-first, offline-first Android study-plan app for a
fixed **68-day** curriculum (the "Professor MedX" plan). The plan is bundled with
the APK as `khutati_plan_data.json`; the app imports it into SQLite on first
launch and never downloads plan content.

Three product rules drive almost every design decision:

1. **Arabic, right-to-left, always.** The UI is Arabic even if the device locale
   is English. Directionality is forced in `lib/app/app.dart`; dates use the
   `ar` locale via `initializeDateFormatting('ar')`.
2. **Offline first.** Every user action must succeed with no network. SQLite is
   the source of truth; the cloud is a backup. No screen ever awaits the network
   to save progress.
3. **The HTML prototype is the visual truth.** `خطتي اليومية، الإصدار 3.html`
   (plus the three reference files in `design/`) defines layout, spacing, radii
   and colour. Design tokens are extracted from it automatically.

The app has five tabs in a persistent shell: **اليوم (Today)**, **الخطة (Plan)**,
**التركيز (Focus)**, **الإنجازات (Achievements)**, **الإعدادات (Settings)**.

---

## 2. Tech stack

| Concern | Choice | Notes |
|---|---|---|
| UI | Flutter 3.29.3 (stable) | Material 3 widgets, heavily restyled |
| State | `flutter_riverpod ^2.6.1` | `Notifier`, `NotifierProvider`, `StreamProvider`, `FutureProvider`, `Provider` |
| Navigation | `go_router ^14.6.2` | `StatefulShellRoute.indexedStack`, redirect-based auth gate |
| Local DB | `drift ^2.21.0` + `sqlite3_flutter_libs` | Generated code is **not** committed |
| Cloud | `supabase_flutter ^2.8.0` | Auth (Google ID token) + PostgREST tables with RLS |
| Auth | `google_sign_in 7.1.1` + `google_sign_in_android 7.0.3` | Credential Manager, **pinned** — see §8 |
| Native | Kotlin | Foreground service + `AlarmManager` exact alarms |
| Notifications | `flutter_local_notifications ^18.0.1` | Four channels, owned by one file |
| Audio | `audioplayers ^6.6.0` | Four bundled WAVs, pre-loaded in low-latency mode |
| Motion | `flutter_animate ^4.5.2`, custom `AnimationController`s | |
| Icons | `flutter_svg ^2.0.17` | Paths are parity-tested against the prototype |
| l10n | `flutter gen-l10n`, `lib/l10n/app_ar.arb` | Arabic only, synthetic package disabled |

No state-management code generation, no freezed, no json_serializable. Hand-written
models and companions keep the build fast and the diff readable.

---

## 3. Repository layout

```
lib/
  main.dart                 Entry point: prefs, notifications, sounds, Supabase, DB, runApp
  app/                      Composition root
    app.dart                MaterialApp.router + RTL + app-level bootstrap widgets
    bootstrap.dart          Opens DB and runs the idempotent plan import
    router.dart             Routes, auth gate, root navigator key
    router_transitions.dart Page transitions (auth entry fade+scale, standard fade+slide)
    shell/                  Bottom navigation shell
    theme/                  ThemeData for light/dark from tokens
  core/                     Cross-cutting, feature-agnostic
    design/                 Palette, tokens, icons, SVG paths, widget kit (K*)
    device/                 Battery + exact-alarm bridges and prompts
    motion/                 Haptics, press-scale, shared durations/curves
    notifications/          The single owner of the notification plugin
    settings/               Theme mode, notification preferences controllers
    sound/                  UI sound effects
    time/                   Local day clock (midnight-safe "today")
    typography/             Bundled font families
    utils/                  Arabic digits, date/number formatting
  data/                     Persistence and transport
    database/               Drift tables, database, provider
    import/                 Plan JSON importer (idempotent, hash-checked)
    repositories/           Template, user state, progress, sync queue
    sync/                   Cloud sync service, bootstrap, id helpers
    providers.dart          Repository providers
  domain/                   Pure Dart business rules (no Flutter, no Drift)
    plan/                   Calendar, dataset model, task model, progress, step state
  features/                 One folder per vertical slice
    <feature>/application/  Controllers, providers, read models
    <feature>/presentation/ Screens and feature widgets
    <feature>/domain/       Feature-local pure models (only `focus` has one)
    <feature>/data/         Feature-local transport (only `auth` has one)
```

**Dependency direction:** `features` → `data` → `domain`; `core` may be imported
by anything and imports nothing from `features` or `data`. `domain/` is pure Dart:
if you find yourself importing `package:flutter` or `package:drift` there, the
logic belongs in a repository instead.

---

## 4. Boot sequence (exact order)

`lib/main.dart` runs before the first frame, deliberately:

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `initializeDateFormatting('ar')` — Arabic month names are needed by Today/Plan.
3. `SharedPreferences.getInstance()` — settings are read before any widget exists
   so there is no theme flash.
4. `FocusNotifications.init(...)` with the four real preferences — channels whose
   toggle is OFF are **deleted** here, so an off switch is never cosmetic.
5. `SoundEffects.init(enabled:)` — preloads the four UI players.
6. `SupabaseAuth.initialize()` inside `try/catch` — a build without credentials
   must still render; the login button then reports that sign-in is unconfigured.
7. `bootstrapDatabase()` — opens SQLite and runs the idempotent import.
8. `runApp(ProviderScope(overrides: [prefs, database], child: KhutatiApp()))`

Then `lib/app/app.dart` wraps the routed child in, outermost first:
`Directionality(rtl)` → `SyncBootstrap` → `UpdateBootstrap` →
`_NotificationPermissionBootstrap`.

`SyncBootstrap` starts the 5-minute sync clock and flushes on lifecycle changes.
`UpdateBootstrap` is the single app-level update presenter. The notification
bootstrap asks for `POST_NOTIFICATIONS`, and the instant it is granted it checks
`AlarmManager.canScheduleExactAlarms()` and prompts if needed. It waits until
onboarding is finished: asking for a permission on top of the first slide is the
worst possible moment.

Router start location: `/splash` on every cold start. The splash holds for 2.5 s
and then goes to `/onboarding` while `onboarding_seen_v1` is false, otherwise to
`/today` (or `/login` when there is no session and no persisted guest choice).
`redirect` lets `/splash` through unconditionally, evaluates the onboarding gate
next, and re-runs on every auth event, so signing in or out clears the stack in
both directions. `launchReadyProvider` flips when the splash hands over; the
update dialog and the notification prompt wait for it instead of a timer.

---

## 5. Implemented features

### 5.1 Plan engine (`lib/domain/plan`, `lib/data/import`)

- `khutati_plan_data.json` is the **only** source of plan content. It is
  validated by `tools/validate_plan_data.mjs` (21 checks, reconciles against the
  PDF: totals, per-day minutes, rest days, ids).
- `PlanImporter.ensureImported` compares a dataset hash and writes once; every
  later launch is a no-op. Template tables are never mutated afterwards.
- `PlanCalendar` resolves the plan start date and maps any local date to a day
  number. `LocalDayClock` handles midnight rollover and timezone changes.
- `PlanProgress` aggregates step states into day/subject/plan percentages,
  crediting **half** the step's minutes for either partial state.

### 5.2 Today (`lib/features/today`)

- `todayDataProvider` is a `StreamProvider` that joins the calendar, template
  tasks, user task statuses, step progress and focus history into one read model.
- Step chips use **optimistic UI**: the chip flips immediately, the DB write is
  queued per step id (writes for the same step are serialized so rapid taps can
  never interleave), and the override is dropped once the row is confirmed.
- A debounced toast (420 ms) shows progress; completing a step plays the success
  chime.
- Rotating dhikr in the quote section, keyed by local day index (stable while the
  user reads, changes at midnight).
- Overdue alert opens `/past-tasks?day=N`.
- `/past-tasks` is a list of day accordions, all closed on load: each header is a
  card with the day title, a red count badge («٧ مهام متأخرة») and a chevron that
  turns 180°. Tapping expands the day's `TaskCard`s over 320 ms `easeInOut`; the
  one exception is the `?day=N` drill-down, which opens that single day.

### 5.3 Plan (`lib/features/plan`)

Weeks → days → tasks browser with calendar strip and search. Reads the same
`StepProgress` values as Today, so a half-done step shows 50% in both tabs.

Each task line carries a «تغيير موعد المهمة» action that opens
`showTaskScheduleSheet` (`task_schedule_sheet.dart`): day chips limited to the
task's week (rest days excluded), a position picker, and a start-time stepper
(−15 / +15 / «تلقائي»). The sheet previews the result live — new day, clock,
order, how many other tasks shift, or the exact reason the move is refused
(rest day, prerequisite, dependant, overlap, past midnight). Saving writes one
`schedule_overrides` row; a gold `edit_calendar_rounded` badge marks overridden
tasks, and «إرجاع للجدولة التلقائية» removes the override.

### 5.4 Focus timer (`lib/features/focus` + Kotlin)

- Two modes: **linked** (a task/step handed over from Today) and **pomodoro**
  (focus/break rounds).
- Dart owns the UI state machine; Kotlin owns the foreground notification and the
  exact alarm that survives Doze. `targetEndMs` is the authority — on resume Dart
  reconciles against it rather than trusting a ticker.
- Notification actions (skip step, start break) arrive through an `EventChannel`;
  a cold start reads a persisted pending action instead.
- Sessions are written to `focus_sessions` and enqueued for sync.

### 5.5 Achievements (`lib/features/achievements`)

68-day map with per-day cells (done / partial / missed / rest / today / selected),
legend, medals, study-hours breakdown and per-subject progress. "فائت" (missed) is
red; today's border and the selected border are visually distinct in both themes.

### 5.6 Auth & account (`lib/features/auth`)

- Google sign-in through the native account picker: the plugin returns an ID
  token, and the app exchanges it with `signInWithIdToken`. No browser redirect.
- **Guest mode** is a persisted local flag; it opens the app without a session and
  keeps the auth gate for everyone else. Signing in clears it.
- Account card: hexagon pattern, "متزامن مع حسابك" indicator when signed in,
  "زائر" avatar plus an in-card Google button for guests.
- Display-name edit (1–60 chars), sign-out with `SignOutScope.local` so other
  devices stay signed in.

### 5.7 Offline-first sync (`lib/data/sync`, `lib/data/repositories`)

- Every user write goes to SQLite first, then to a deduplicated outbox
  (`sync_queue`, `UNIQUE(entity, entity_id)`).
- `CloudSyncService` drains it every **5 minutes**, on `paused`/`detached`, and on
  resume/sign-in. Pulls are throttled to every **10 minutes**.
- Only server-acknowledged rows are deleted; failures increment `attempts` and are
  retried. Unknown entities are dropped so a downgrade cannot wedge the queue.
- Pull compares `updated_at` before overwriting, so a stale remote row can never
  downgrade local progress. Focus sessions are matched by client id.
- Entities: `task_state`, `step_state`, `focus_session`.

### 5.8 Notifications & alarms

Four channels, one owner (`lib/core/notifications/focus_notifications.dart`):
`tasks` (2001), `daily` (2002), `review` (2003), `timer` (1001/1002). Settings
toggles create or **delete** the channel; the timer toggle also re-arms or cancels
the native alarm through `setNotificationsEnabled`.

### 5.9 In-app updates

`UpdateRepository` walks a strict waterfall: GitHub Releases API (conditional,
with `If-None-Match`), then the static `releases.atom` feed when the API is rate
limited, then the Supabase `app_versions` table when github.com is unreachable.
The first source with a manifest wins; an empty answer is a success, so the UI
can tell "nothing new" from "could not check". Background checks run at most
once every 60 minutes (measured from the last **successful** check; failures do
not reset the clock). A manual check bypasses the cooldown and must report the
real outcome: up to date on success, an explicit error on failure — never "up to
date" when nothing was checked. "Skip this version" is supported. The dialog is
a `KDialog`, never a Material alert.

### 5.10 Design system (`lib/core/design`)

`design/tokens.json` is generated from the HTML prototype by
`tools/extract_tokens.mjs`, and `lib/core/design/tokens.dart` is generated from
that. Widgets: `KButton`, `KChip`, `KCard`, `KPill`, `KTag`, `KSectionHeader`,
`KBreakDivider`, `KProgressBar`, `KProgressRing`, `KEcgLine`, `KConfetti`,
`KBrandMark`, `KDialog`/`showKDialog`, `showKToast`, `KPressable`/`KInkSurface`
(the tactile layer), plus `KhutatiPalette` for colours. Motion primitives live in
`core/motion` (press scale, haptics, shared durations). Sounds live in
`core/sound` — four pre-loaded `KSound` entries whose gain is mastered into the
WAV files (`tools/master_sounds.mjs`), because Android's low-latency path ignores
`setVolume`.

### 5.11 Settings

Theme (light/dark/system), UI sound toggle, four notification toggles, battery
optimisation row, update panel, About and Developer modals, and «مشاركة التطبيق»
(share_plus, with the invitation text in the ARB). Every modal closes
with a `KButton`, not an unlabeled icon. The «المنبهات والمذكرات» row reports the
live state of both grants — green check when notifications **and** exact alarms
are allowed, «غير مفعل» otherwise — re-reads them on every resume, and deep-links
to whichever one is missing (`ACTION_APP_NOTIFICATION_SETTINGS` /
`ACTION_REQUEST_SCHEDULE_EXACT_ALARM`). The battery row is the same widget with
the same rule for `isIgnoringBatteryOptimizations`, and opens
`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, falling back to the battery list
and then app details on OEM skins that block the sheet.

A compact «الخطة» section holds the «أيام العملي» navigation row
(`_SettingsNavRow`: 36 px tinted icon, title, one-line subtitle, chevron). It
pushes `/settings/practical-days`; the weekday selector itself lives there, not
in Settings. The section is shaped so a future «تعديل الخطة» row can sit beside
it without restructuring.

### 5.12 Launch and onboarding (`lib/features/onboarding`)

The native window paints `#0D1A2D` everywhere, including Android 12's own splash
(`values-v31`), so there is no light flash before Flutter starts. `SplashScreen`
then draws three glowing waves and reveals «خطتي» plus a short quote with
`Curves.easeOutExpo`, holds 2.5 s, and hands over to the welcome flow or Today.
Three welcome slides follow ("منهاجك كله في 68 يوماً" / "يوم واحد في كل مرة" /
"شاهد نفسك تتقدم"), shown once and never again. Everything is painted with
`CustomPainter` — no SVG library — with the prototype's exact CSS delays and
durations (road 3.2 s from 0.4 s, stars on a 7 s float, trend line on a 12 s
draw/hold/fade). A static `HillsPainter` per slide lives in its own
`RepaintBoundary` and never repaints; the foreground is driven by a 7 s entrance
clock and a 2-hour ambient clock, so no two infinite animations share a period.
Swiping applies parallax + fade + scale (0.9 → 1.0) via `AnimatedBuilder` with the
slide passed as `child`, so a drag rebuilds only the transform.
`onboarding_seen_v1` is written on Skip/ابدأ, and both the router gate and the
notification bootstrap key off it. Details: ARCHITECTURE §10.

---

## 6. Critical rules (do not violate)

1. **The HTML prototype is the absolute visual truth.**
   `خطتي اليومية، الإصدار 3.html` plus `design/achievements_reference.html`,
   `design/focus_reference.html`, `design/login_reference.html`. If code and
   prototype disagree, the prototype wins. After changing a colour, radius or
   spacing in the prototype, run `node tools/extract_tokens.mjs`; CI runs
   `--check` and fails on drift.

2. **Never bypass the sync queue.**
   User data is written through a repository (`UserStateRepository`,
   `FocusController`'s session writer), which writes Drift **and** enqueues. Do not
   call Supabase directly from a widget, controller or screen. Do not await the
   network on a tap.

3. **No default Material dialogs, and modals must open instantly.**
   Use `showKDialog` + `KDialog` + `KDialogAction` (tinted scrim, 28 px radius,
   `KButton` actions). Zero `showDialog`/`AlertDialog` calls exist in `lib/`; keep
   it that way. If you show a dialog from a widget that lives in
   `MaterialApp.builder` (above the Navigator), anchor it to
   `rootNavigatorKey.currentContext`, not the builder context.
   Performance contract, learned the hard way: never put a `BackdropFilter` (or
   any full-screen blur) inside an animated route — it re-blurs the whole window
   on every frame of the entry transition and reads as a freeze. The scrim is a
   flat tint; only the card fades/scales (200 ms, `easeOut`, 0.95→1.0). Builders
   must be pure: pass already-loaded objects in, and never run a database query or
   `await` inside `builder`. If a dialog needs fresh data, show it immediately
   with a loading state and let a provider fill it in.

4. **Every tappable surface goes through the tactile layer.**
   `core/design/widgets/pressable.dart` is the only place a press is defined:
   `KPressable` when the surface owns its colour (`KButton`), `KInkSurface`
   *inside* a decorated container when the background animates (`KChip`, `KCard`
   with `onTap`, nav items). Never add a bare `GestureDetector` to something that
   should feel pressable, and never put the ink surface *outside* the fill — the
   splash would be painted underneath it and be invisible. Sounds fire on
   `onTap`, not on press-down, and `SoundEffects.enabled` (the settings switch)
   gates all of them.

5. **Google nonce is handled server-side.**
   The native Credential Manager does not mint a nonce, so the Supabase Google
   provider must have **"Skip nonce check"** enabled
   (`external_google_skip_nonce_check = true`). This is a dashboard/server
   setting, not a Dart parameter. Never add a fake nonce to the client, and never
   disable the check by weakening anything else.

6. **Secrets never enter git.**
   The anon key is public-by-design but still injected at build time through
   `--dart-define`. The service-role key must never ship in the app. Signing
   material lives only in GitHub secrets (`README.md` §4 lists the names).

7. **Drift generated code is not committed.**
   `*.g.dart` is git-ignored and produced by
   `dart run build_runner build --delete-conflicting-outputs` (CI does this).
   Never hand-edit generated files; never reference a table class by guesswork —
   check `@DataClassName` in `lib/data/database/tables.dart` first.

8. **Channel and notification ids are permanent.**
   Android fixes a channel's importance the first time it is created. To change
   importance, bump the id suffix (`..._v2`) — do not edit the existing one. When
   cancelling, remember the timer channel owns **two** ids (1001 focus, 1002
   break); reminder channels own one.

9. **Arabic and RTL are not optional.**
   All user-facing strings are Arabic. Use `context.l10n` for shared strings and
   Arabic literals for one-off copy. Use `core/utils/format.dart` for Arabic-Indic
   digits and dates; do not call `intl` directly in a screen.

10. **Track work in `bd`, not in markdown.**
   See §9. Do not create TODO lists in files or use TodoWrite-style trackers.

---

## 7. Verification (CI is the gate)

CI is the only real gate. Locally you can still run the fast checks:

```bash
node tools/extract_tokens.mjs --check      # design tokens match the prototype
node tools/check_version.mjs               # AppInfo == pubspec version
node tools/validate_plan_data.mjs          # 21 dataset checks
node tools/validate_plan_data.mjs --self-test
dart format --output=none lib test         # parse check (does not write)
```

`dart analyze` is **not** usable in a container without a Flutter SDK:
`analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`, which
cannot resolve there, and the Drift `.g.dart` files are absent until codegen runs.
Do not "fix" that error; use `flutter analyze` where the SDK exists, or let CI do
it.

CI (`Android CI`) runs: pub get → `libsqlite3-dev` → `gen-l10n` → build_runner →
the four Node checks → `flutter analyze --no-fatal-infos --no-fatal-warnings`
(errors fail) → `flutter test` → signed release build. The suite includes
`test/domain/schedule_override_test.dart` (engine: 1/2/3 practical days, fourth
rejected, determinism, overrides, pinned starts, every rejection path) and the
`manual scheduling` group in `test/data/schedule_repository_test.dart`
(preview-writes-nothing, commit, rest-day refusal, dependency refusal, override
persistence, overlap, clear/clear-all, progress preservation, reconciliation).

---

## 8. Gotchas that cost time last time

- **Drift closure types.** With `@DataClassName('SyncQueueRow')`, the table class
  is `$SyncQueueTable` and the row is `SyncQueueRow`. Closures passed to
  `orderBy`/`where` take `$SyncQueueTable`; the `DoUpdate` callback also takes
  `$SyncQueueTable` (not the row). `customUpdate(updates: ...)` wants
  `Set<ResultSetImplementation>`, i.e. `{db.syncQueue}` — not `TableUpdate`.
- **Dialogs above the Navigator.** Anything built inside `MaterialApp.builder`
  has no Navigator above it. `showKDialog` from there throws
  "No Navigator widget found" — use `rootNavigatorKey.currentContext`.
- **`KDialog` needs a `Material` ancestor** for its `InkWell`s; `dialogs.dart`
  already wraps the surface in `Material(type: MaterialType.transparency)`.
  Do not remove it.
- **Google Sign-In is pinned** to `7.1.1` / `7.0.3`. Newer Android
  implementations expect a newer AGP/Kotlin toolchain than this project uses.
  Upgrading requires bumping Gradle/AGP/Kotlin together and rebuilding.
- **Gradle plugin-portal flakes.** A build can fail with "Could not find
  org.jetbrains.kotlin:kotlin-stdlib:2.0.21" from `plugins.gradle.org` while
  nothing in `android/` changed. Re-run the job before touching Gradle files.
- **Legacy rows.** Step rows written before schema v2 have only `completed`;
  `_progressOf` reads them as fully done so upgrades never downgrade progress.
  Code `1` is `partialUp` (what older builds wrote for their single half state).
- **Focus timer authority.** Never trust a Dart `Timer` for completion. The
  native `targetEndMs` and the exact alarm are authoritative; Dart reconciles.
- **`USE_EXACT_ALARM` must stay out of the manifest.** It is auto-granted on
  Android 13+, so `canScheduleExactAlarms()` returns `true` forever, the system
  hides the "Alarms & reminders" toggle, and the app never prompts. Only
  `SCHEDULE_EXACT_ALARM` is declared; that is what makes the permission flow
  reachable (see `ARCHITECTURE.md` §5.4).

---

## 9. Working with `bd` (Beads)

Issues live in a local Dolt database; the code lives in git. `AGENTS.md` and
`CLAUDE.md` contain the managed block. The essentials:

```bash
bd prime                      # full workflow context, read this once per session
bd ready                      # issues with no open blockers
bd show <id>                  # description, parent, notes
bd update <id> --claim        # atomically take ownership
bd close <id> --reason "..."  # complete, with a one-line reason
bd dolt push                  # sync issue data to refs/dolt/data on the remote
```

Conventions in this repo:

- Epics are `Khutati-<id>` (e.g. `Khutati-2qm` Phase 5/6); sub-issues are
  `Khutati-<id>.<n>` and each one is a shippable goal.
- Claim before working, close only when the work is verified (CI green), and put
  the release/commit context in the close reason.
- `bd dolt push` is separate from `git push` and is not automatic. If you close
  issues, say so at handoff and let the user decide when to sync.
- Do not create parallel task lists in markdown; `bd` is the only tracker.

---

## 10. What is done, what is next

**Done and shipped through 1.0.0:** auth (Google + guest), offline-first sync outbox,
4-tap step state machine, focus timer with native alarms, notification toggles,
premium dialogs, account card, sound effects, post-login transition, achievements
map fixes, rotating quotes, update system, settings polish, practical-weekday
redistribution (Settings → Plan/Today/achievements, reset, cloud sync), the focus
log, and the hardened background timer (state restore, chronometer notification,
working action buttons).

**Done and awaiting CI:** one-to-three practical days with a dedicated screen and
a real preview, the sequential redistribution engine, manual task scheduling
(move / reorder / pinned start) with dependency and overlap validation,
`schedule_overrides` persistence + sync, the «تعديل يدوي» badge, and restore to
automatic scheduling.

**Next (already in `bd`, status `in_progress`):**

- `Khutati-h7n.3` — **Day detail screen** (P3.3): a full day view with its tasks,
  breaks, times and per-task progress.
- `Khutati-h7n.4` — **Task detail & notes** (P3.4): step list, notes, review flag,
  "start focus" handoff.

Both must follow the same rules: tokens from the prototype, `KDialog` for modals,
writes through `UserStateRepository` so the outbox is never bypassed, and Arabic
copy throughout.

**Known open epics (not started):** Phase 4 focus hardening (`Khutati-03x`),
Phase 2 editing/restore (`Khutati-djx`), Phase 3 plan search (`Khutati-h7n.2`),
Phase 6 streaks (`Khutati-99q`), Phase 7 QA (`Khutati-3xt`), Phase 8 manifest
discipline (`Khutati-gwe`).

---

## 11. First 30 minutes for a new agent

1. `git log --oneline -10` and `bd list` — see what changed and what is claimed.
2. Read `ARCHITECTURE.md` §3 (write path) and §4 (state machine) — those two
   explain 80% of the code.
3. Open `lib/app/app.dart`, `lib/app/router.dart`, `lib/data/database/tables.dart`.
4. Run the four Node checks; they must pass before you change anything.
5. Pick a `bd` issue, claim it, and make the smallest change that satisfies it.
6. Verify locally with the Node checks, then let CI run the analyzer and tests.
   Committing and pushing are **not** automatic: the repository profile is
   conservative, so commit/push only when the user or orchestrator asks. At
   handoff, report the changed files, the validation output, and the exact
   commands still to run.
