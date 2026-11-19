# ARCHITECTURE — Technical Deep Dive

> Companion to `PROJECT_CONTEXT.md`. This file explains **how** the systems work
> and why they are shaped this way. Read §3 (write path), §4 (state machine) and
> §5 (native bridge) before touching progress, sync or the timer.

---

## 1. Layering and dependency rules

```
        ┌──────────────────────────────────────────────┐
        │ app/        composition root                 │
        │ main, MaterialApp, router, shell, theme      │
        └───────────────┬──────────────────────────────┘
                        │
        ┌───────────────▼──────────────────────────────┐
        │ features/   vertical slices                  │
        │ application/ (controllers, providers)        │
        │ presentation/ (screens, widgets)             │
        └───────┬───────────────────────┬──────────────┘
                │                       │
        ┌───────▼─────────┐     ┌───────▼──────────────┐
        │ data/           │     │ core/                │
        │ drift, repos,   │     │ design, device,      │
        │ import, sync    │     │ notifications, ...   │
        └───────┬─────────┘     └──────────────────────┘
                │
        ┌───────▼──────────────────────────────────────┐
        │ domain/   pure Dart rules (no Flutter/Drift) │
        └──────────────────────────────────────────────┘
```

Hard rules:

- `domain/` imports only `dart:core`/`dart:math` and other `domain/` files. It is
  unit-testable without a binding.
- `data/` owns every SQL statement and every network call.
- `features/*/presentation` never imports `data/database/app_database.dart`
  directly; it reads through providers and repositories.
- `core/` is a leaf that anything may import, and it imports nothing from
  `features/` or `data/` except `core/settings` reading `SharedPreferences`.

---

## 2. Read path: how Today is assembled

```
todayDataProvider (StreamProvider<TodayData?>)
   ├── planCalendarProvider   → PlanRow + PlanCalendar (plan start, day mapping)
   ├── todayClockProvider     → DateTime stream, ticks across midnight
   ├── templateRepository     → days, tasks, steps, breaks, subjects
   ├── userStateRepository    → task statuses, step progress for the day
   ├── planProgressRepository → aggregated percentages
   └── focusHistoryProvider   → focus sessions for today
                    ↓
              _buildToday(...)   (pure assembly, no I/O)
                    ↓
   TodayData { day, tasks, progress, hours, overdue, now }
                    ↓
              TodayScreen  (renders; never queries the DB itself)
```

`TodayData` is an immutable snapshot. Because the DB queries are watched
(`.watch()` / stream providers), any write — from the UI, from the sync pull, or
from the native timer — rebuilds the screen automatically. There is no manual
refresh path.

The Plan tab builds the same values from `allStepProgresses()`, so the two tabs
cannot disagree about whether a step is 0/50/100%.

---

## 3. Write path: one tap, end to end

This is the most important flow in the app. It is deliberately **synchronous
locally, asynchronous remotely**.

```
User taps a step chip
        │
        ▼
StepChips (presentation)
  • sets an optimistic override so the chip flips on the next frame
  • appends the tap to a per-step write queue (serialised per step id)
        │
        ▼
UserStateRepository.setStepCompleted(stepId, progress)
  1. INSERT OR REPLACE into user_step_states
       (step_id, completed, completed_at, progress.code, updated_at)
  2. SyncQueueRepository.enqueue('step_state', stepId, {json})
        │
        ▼
sync_queue  (SQLite, durable, survives process death)
  UNIQUE(entity, entity_id)  →  repeated taps REPLACE the snapshot
        │
        │   (no network on the tap path — the UI never waits)
        ▼
CloudSyncService  (every 5 min · on paused/detached · on resume · after sign-in)
  1. pending(limit: 400) ordered by (enqueued_at, id)
  2. group rows by entity
  3. one upsert per entity group:
       task_state    → user_task_states   onConflict user_id,task_id
       step_state    → user_step_states   onConflict user_id,step_id
       focus_session → focus_sessions     onConflict user_id,id
  4. removeIds(acknowledged) ; recordFailure(failed → attempts + 1)
```

### Why the queue deduplicates

The unique key is `(entity, entity_id)`, not the auto-increment id. Four taps on
one step in two seconds produce **one** row in `sync_queue` holding the final
state, therefore one upsert. Without the conflict target Drift would raise on the
unique index instead of replacing the snapshot, so the upsert explicitly names
`target: [entity, entityId]`.

Ordering is `(enqueued_at ASC, id ASC)`. The id is the tiebreaker for taps inside
the same millisecond, which keeps a backlog draining in the order it happened.

### Failure semantics

| Situation | Behaviour |
|---|---|
| No Supabase config in the build | `syncNow` returns early; outbox keeps growing; app fully usable |
| No signed-in user (guest) | Same: rows stay queued locally |
| Network error / timeout | Rows stay, `attempts + 1`, retried next tick |
| Partial group failure | Only the failed entity group is retried |
| Unknown entity (downgrade) | Row is dropped so the queue cannot wedge forever |
| Process killed mid-flush | Queue is a table, so nothing is lost; the next run re-reads it |

### Pull and conflict resolution

`syncNow(pull: true)` (resume, sign-in, first frame) also pulls, throttled to once
per 10 minutes:

- `user_task_states`: skip remote when `remote.updated_at <= local.updated_at`.
- `user_step_states`: same, but only when the local row also has an `updated_at`
  (legacy rows without one are overwritten once, then carry a timestamp).
- `focus_sessions`: matched by client-generated `id`; unknown ids are inserted,
  known ids are left alone (sessions are immutable once recorded).

Rule of thumb: **local wins on ties.** A clock-skewed server row must never
rewind the user's progress.

### Why the outbox exists at all

Writing directly to Supabase from the tap handler would make every tap depend on
latency and would lose data offline. Writing only to SQLite would lose data on
reinstall. The outbox is the only structure that satisfies both: instant local
durability plus eventual remote backup, with a single code path for both.

---

## 4. The 4-tap state machine

`lib/domain/plan/step_progress.dart` — a pure enum with a strict cycle:

```
        tap                tap                tap                tap
  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
  │ notStarted  │──▶│  partialUp  │──▶│  completed  │──▶│ partialDown │──┐
  │   code 0    │   │   code 1    │   │   code 2    │   │   code 3    │  │
  │    0%       │   │    50%      │   │    100%     │   │    50%      │  │
  └─────────────┘   └─────────────┘   └─────────────┘   └─────────────┘  │
         ▲                                                              │
         └──────────────────────────────────────────────────────────────┘
```

| State | `code` | `fraction` | `completed` column | Meaning |
|---|---|---|---|---|
| `notStarted` | 0 | 0.0 | false | untouched |
| `partialUp` | 1 | 0.5 | false | half done, next tap completes |
| `completed` | 2 | 1.0 | true | done |
| `partialDown` | 3 | 0.5 | false | half undone, next tap clears |

### Why two half states

The bug this replaced: a single "partial" value meant that after a restart the
third tap and the fourth tap both resolved to 50%, so the cycle stalled. Storing
`1` and `3` separately makes the cycle resumable from the database alone — no
session memory, no timers.

`tryParse` maps unknown integers to `notStarted` (forward compatibility) and
`_progressOf` maps `completed == true` with `progress == 0` to `completed`
(backward compatibility with schema v1 rows).

### Rapid taps

`StepChips` keeps a `Map<String, Future<void>>` of in-flight writes per step and
chains the next write onto the previous future. Two taps 30 ms apart therefore
commit in order instead of racing, and the optimistic map is pruned only when the
confirmed row arrives via the stream. Without this, the last writer could be the
first tap and the chip would jump backwards.

---

## 5. Native bridge (Flutter ⇄ Kotlin)

Two channels, both registered in `MainActivity.configureFlutterEngine`:

| Channel | Type | Direction | Purpose |
|---|---|---|---|
| `khutati/focus_timer` | `MethodChannel` | Dart → Kotlin | Timer control + device capabilities |
| `khutati/focus_events` | `EventChannel` | Kotlin → Dart | Notification actions (skip step, start break) |

### 5.1 Methods on `khutati/focus_timer`

| Method | Args | Returns | Notes |
|---|---|---|---|
| `start` | `durationMs, taskId, stepId, phase, taskTitle, hasNextStep, breakEnabled, breakMinutes, notificationsEnabled` | `null` | Starts `FocusTimerService` as a foreground service |
| `pause` | — | `null` | Persists `paused_remaining_ms` |
| `resume` | `durationMs` | `null` | Re-arms the exact alarm |
| `stop` | — | `null` | Cancels alarm + notification |
| `getState` | — | `{remainingMs, paused, phase, targetEndMs, plannedSeconds, running}` | Reconciliation source |
| `getRemaining` | — | `Long` | Lightweight variant |
| `setNotificationsEnabled` | `enabled` | `null` | Re-arms/cancels the live alarm, not just the channel |
| `canScheduleExactAlarms` | — | `bool` | `true` below Android 12 |
| `openExactAlarmSettings` | — | `bool` | `ACTION_REQUEST_SCHEDULE_EXACT_ALARM`, falls back to app details |
| `isIgnoringBatteryOptimizations` | — | `bool` | Battery row in Settings |
| `openBatterySettings` | — | `bool` | Three fallbacks, returns `false` only if all fail |

Dart wrappers: `core/device/exact_alarm_permission.dart`,
`core/device/battery_optimization.dart`, `core/settings/notification_prefs.dart`,
and `FocusController._native*` in `features/focus/application/focus_controller.dart`.

### 5.2 Who owns the countdown

The Dart isolate can be frozen by Doze. Therefore:

1. **Kotlin is authoritative for time.** `FocusTimerService` stores an absolute
   `target_end_ms` in `khutati_focus` preferences and arms
   `AlarmManager.setExactAndAllowWhileIdle` (falls back to `setAndAllowWhileIdle`
   when the permission is missing, and catches `SecurityException`).
2. **Dart mirrors it.** The ticker only repaints; on every resume `FocusController`
   calls `getState` and reconciles against `targetEndMs`. This is what removed the
   "ghost timer" that kept counting after the process was killed.
3. **The alert has two possible authors.** If the app is in the foreground, Dart
   posts the completion notification and drives the transition. If not,
   `FocusAlarmReceiver` fires, advances the native phase (arming the break alarm),
   and posts a `NotificationCompat` heads-up with sound. `MainActivity` writes
   `flutter.app_foreground` on resume/pause so the two never double-alert.
4. **Every command restores before it acts.** `FocusTimerService.restoreFromPrefs`
   runs at the top of `onStartCommand` for every action except `START`. Without it
   a process killed mid-session came back with default fields: a stale alarm
   invented a five-minute break, and the notification's pause became a no-op.
5. **The notification is drawn by the system.** The running notification uses
   `setUsesChronometer(true)` + `setChronometerCountDown(true)` with
   `when = targetEndMillis`, so nothing wakes up once a second just to repaint a
   countdown. Only phase changes repost it.
6. **Muting alerts never stops the timer.** `FocusAlarmReceiver` always hands the
   expiry to the service (through `ContextCompat.startForegroundService`) and only
   skips the audible notification. The service calls `startForeground` before
   touching state, which keeps the Android 8+ foreground-service contract even
   when the alarm is the thing starting it.

### 5.3 Notification actions and cold start

`FocusTimerService`'s action buttons carry `focus_action` in the launch intent.
`MainActivity.persistPendingAction`:

- If a Dart engine is alive, the action is emitted immediately on
  `khutati/focus_events`.
- Otherwise it is written to `flutter.pending_focus_action` in shared preferences,
  and `FocusController` reads it on first build.

Tapping the notification body carries **no** action, so merely opening the app can
never end a session.

The ongoing notification exposes, depending on state: pause/resume, end, and one
"move on" action — skip to the next step, start the planned break, or skip a
running break. Pause/resume/end are `PendingIntent.getService` calls handled
entirely in Kotlin; skip/break open the app and travel as `focus_action`.
`FocusScreen` consumes a queued action **before** reconciling with the service
(`_reconcile`), so an "end" that arrived while the app was closed wins over a
stale in-app deadline and the service is not re-armed by mistake.

### 5.4 Exact-alarm permission flow

```
app start
  └─ _NotificationPermissionBootstrap._request()
       ├─ requestPermission() → POST_NOTIFICATIONS (Android 13+)
       ├─ if granted OR areEnabled():
       │     └─ _ensureExactAlarms()          (retries once if the router has
       │           │                           not produced a navigator yet)
       │           └─ maybePromptExactAlarms(rootNavigatorKey.currentContext)
       │                 ├─ canSchedule() == true  → done
       │                 └─ false → KDialog → "فتح الإعدادات" → openExactAlarmSettings()
       └─ else → KDialog rationale → "السماح" → request again
on resume
  └─ if notifications are enabled → _ensureExactAlarms() (silent re-check)
Focus tab opened
  └─ maybePromptExactAlarms(context)            (no force, at most once/process)
Settings → "تذكير المهام" / "تنبيهات الجلسات" turned ON
  └─ maybePromptExactAlarms(context, force: true)
```

`maybePromptExactAlarms` is the only place that decides to show the dialog. It
guards against stacking (`_showing`) and against nagging a user who chose
"لاحقاً" (`_prompted`), and re-checks `context.mounted` after every `await`.

**The manifest must declare `SCHEDULE_EXACT_ALARM` only.** `USE_EXACT_ALARM` is
auto-granted by Android 13+, which forces `canScheduleExactAlarms()` to return
`true` forever: the system hides the "Alarms & reminders" toggle, the app never
prompts, and the timer silently degrades to inexact alarms. It is also reserved
for alarm-clock/calendar apps on Play. Removing it is what makes the prompt fire.

`MainActivity.openExactAlarmSettings()` launches
`Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM` with `package:<applicationId>`,
and falls back to the app's details page when an OEM blocks that screen. It
returns `false` only when every option failed, so the caller can report it.

---

## 6. Database schema

SQLite is the source of truth. `schemaVersion = 5` in
`lib/data/database/app_database.dart`.

### 6.1 Template tables (imported once, never mutated)

| Table | Row class | Contents |
|---|---|---|
| `plans` | `PlanRow` | plan id, dataset version, start date, day counts, total minutes |
| `subjects` | `SubjectRow` | subject key/name/instructor/accent, page-2 totals |
| `chapters` | `ChapterRow` | chapter per subject |
| `lessons` | `LessonRow` | foundation/lecture with attendance+study minutes |
| `days` | `DayRow` | day number, week, type (normal/practical/rest), clocks, note |
| `tasks` | `TaskRow` | task per day/subject, type, group title, typed minutes |
| `steps` | `StepRow` | attend/study/questions with minutes and suggested clocks |
| `breaks` | `BreakRow` | break/free-time blocks per day |

Keeping these immutable is what makes "restore to default" possible: user edits
belong in the user tables as overrides.

### 6.2 User tables (the only ones that sync)

| Table | Row class | Key | Notes |
|---|---|---|---|
| `user_task_states` | `UserTaskStateRow` | `task_id` | status, completed_at, updated_at |
| `user_step_states` | `UserStepStateRow` | `step_id` | `progress` code 0–3, completed, completed_at, updated_at |
| `focus_sessions` | `FocusSession` | auto id + unique `client_id` | mode, phase, planned/actual seconds, started/ended |
| `user_overrides` | `UserOverrideRow` | auto id | target type/id + field + JSON value (edits without migrations) |
| `schedule_overrides` | `ScheduleOverrideRow` | `task_id` | manual placement: `day_number`, optional `position`/`start_clock`, `updated_at` |
| `user_additions` | `UserAdditionRow` | auto id | personal items added to a day |
| `notes` | `NoteRow` | auto id | per-task notes |
| `review_flags` | `ReviewFlagRow` | `task_id` | "mark for review" |
| `app_settings` | `SettingRow` | `key` | local key/value settings |

### 6.3 Sync tables

| Table | Row class | Notes |
|---|---|---|
| `sync_queue` | `SyncQueueRow` | durable outbox: entity, entity_id, JSON payload, enqueued_at, attempts; unique `(entity, entity_id)` |

### 6.4 Migration history

| Version | Change | Compatibility handling |
|---|---|---|
| v2 | `user_step_states.progress` | legacy rows read as `completed` |
| v3 | `focus_sessions.mode`, `.task_title` | nullable/defaulted |
| v4 | `user_step_states.updated_at`, `focus_sessions.client_id`, `sync_queue` + indexes | existing progress codes preserved exactly |
| v5 | `schedule_overrides` + unique index on `task_id` | empty table means "fully automatic"; existing schedules untouched |

Indexes are created explicitly (not only by Drift) so their names stay stable:
`idx_days_day_number`, `idx_tasks_day`, `idx_tasks_subject`, `idx_steps_task`,
`idx_breaks_day`, `idx_sessions_started`, `idx_overrides_target`,
`idx_focus_client_id` (partial unique), `idx_sync_queue_entity`,
`idx_schedule_override_task` (unique).

`beforeOpen` enables `PRAGMA foreign_keys = ON`; without it the template/user
separation is decorative.

### 6.5 Remote schema (Supabase)

Applied by `supabase/migrations/202611180001_sync_tables.sql`:

| Table | Primary key | RLS |
|---|---|---|
| `user_task_states` | `(user_id, task_id)` | owner-only, `for all` using/with check `auth.uid() = user_id` |
| `user_step_states` | `(user_id, step_id)` | owner-only |
| `focus_sessions` | `(user_id, id)` | owner-only |
| `user_schedule_overrides` | `(user_id, task_id)` | owner-only (`202611190004`) |

`anon` is revoked on all of them; `authenticated` gets
select/insert/update/delete.
`public.app_versions` (migration `202611190001`) is the opposite: public read,
writes only via CI with the service role. The earlier `app_updates` table was
dropped (migration `202611190002`) once the waterfall stopped reading it.

---

## 7. Notifications

One file owns the plugin: `lib/core/notifications/focus_notifications.dart`.

| Channel | Id | Notification id | Importance |
|---|---|---|---|
| تذكير المهام | `khutati_reminders_tasks_v1` | 2001 | high |
| ملخص اليوم | `khutati_reminders_daily_v1` | 2002 | high |
| مراجعة المهام | `khutati_reminders_review_v1` | 2003 | high |
| تنبيهات الجلسات | `khutati_timer_alerts` | 1001 focus / 1002 break | max |

Key behaviours:

- Android fixes importance at first creation; changing it requires a new id
  suffix. That is why the reminder ids end in `_v1`.
- Turning a toggle **off deletes the channel**. Not posting is not enough: an
  existing channel keeps its own sound/vibration settings and would still be
  usable. Only the timer channel cancels `id + 1`, because only it owns two ids.
- `_timerEnabled` mirrors the preference so `showCompletion` can never post on a
  channel the user disabled, even if the native alarm fires.
- The native service keeps its own `khutati_focus_alerts_v2` channel
  (`IMPORTANCE_HIGH`, sound + vibration) because it must alert with the app dead.

---

## 8. In-app updates

```
UpdateController (60 min cooldown on the last SUCCESSFUL check)
   └─ UpdateRepository.check(etag: stored)        (timeout: 8 s)
        ├─ 1. GitHub API   GET api.github.com/repos/{repo}/releases
        │      If-None-Match: <etag>  → 304 = success, zero quota
        ├─ 2. GitHub Atom  GET github.com/{repo}/releases.atom
        │      only if the API failed (403 rate limit, 5xx, timeout, DNS)
        └─ 3. Supabase     GET {url}/rest/v1/app_versions?order=created_at.desc&limit=1
               only if neither GitHub path produced a release
        ↓  strict waterfall: the first source with a manifest wins
   compare with AppInfo.versionCode
        ↓
   UpdateBootstrap (single app-level presenter, rootNavigatorKey)
        └─ KDialog → open apkUrl / pageUrl via url_launcher
```

**The waterfall.** Sources are tried in order and each one falls through only
when it produced nothing. GitHub is first because it is the authoritative record
(CI publishes there); the Atom feed covers a rate-limited API; Supabase covers
the case the first two cannot — github.com itself being unreachable or blocked.
A source that answers "no release" is a success and does not throw, so the UI
can still distinguish "nothing new" from "could not check".

| Step | Cost | Answers | Falls through when |
|---|---|---|---|
| GitHub API | 0 (304) or 1 of 60/h | version, build, notes, assets | any non-2xx, timeout |
| GitHub Atom | free (static file) | tag + date; URL rebuilt from the tag | non-2xx, unparseable feed |
| Supabase | free | `version`, `download_url`, `release_notes` | non-2xx, row without an HTTPS URL |

**Quota discipline.** GitHub allows 60 anonymous requests per hour per IP, so
the app must not spend one per launch:

- `maybeCheck()` (cold start, resume) returns immediately while
  `update_last_check_ms` is younger than 60 minutes. A **failed** background
  check never writes that key, so the next resume retries instead of going
  quiet for an hour.
- The repository sends the stored ETag (`update_etag`) as `If-None-Match`. A
  `304` is a successful check with no update, and costs no quota.
- If the API fails, `releases.atom` (a static file on github.com, outside the
  API quota) supplies the newest tag. It has no asset list, so the APK URL is
  reconstructed from the CI convention `releases/download/<tag>/Khutati.apk`;
  the tag keeps its `v`.

**Supabase mirror.** `supabase/migrations/202611190001_app_versions.sql` creates
`app_versions` (`id uuid`, `version`, `download_url`, `release_notes`,
`created_at`) with RLS and a public `select` policy for the anon key; a unique
index on `version` lets CI upsert. The release job mirrors every published
release into it with the service role, so the last-resort row always describes
the APK that is actually on GitHub. `UpdateManifest.fromJson` already reads
`download_url` and `release_notes`, so no row shape is special-cased.

**Honest UI.** A manual check bypasses the cooldown, shows the button spinner
immediately, and reports the outcome: `updateUpToDate` on success, `updateFailed`
("تعذر التحقق من التحديثات…") on failure. Background failures are silent and
restore the previous state, so a previously found update stays visible.

`skip()` persists `update_skipped_version_code`; a `force` check from Settings
ignores both the cooldown and the skip. If Supabase is unconfigured the GitHub
path alone still works, which is why local builds update correctly.

---

## 9. Audio, motion and touch

**Sounds.** `SoundEffects` owns one pre-loaded `AudioPlayer` per entry in the
`KSound` enum (`PlayerMode.lowLatency`, `ReleaseMode.stop`). Preparation is
shared through a single future, so the startup call in `main.dart` and the
settings provider never configure the same player twice.

**The mix lives in the assets, not in Dart.** On Android the low-latency path
(SoundPool) applies gain when a sample is loaded, so `AudioPlayer.setVolume`
never reached the mix — two releases shipped a quieter constant and played
exactly the same level. `tools/master_sounds.mjs` normalises each file to a fixed
peak instead (`--apply`, idempotent), which no platform path can skip:

| `KSound` | Asset | Peak | Used by |
|---|---|---|---|
| `tap` | `sounds/click.wav` | −35 dBFS | `KButton`, `KCard(onTap:)`, nav items, generic pressables |
| `toggle` | `sounds/toggle.wav` | −30 dBFS | `KChip` (the 4-tap cycle), settings switches, week selector, focus mode segments |
| `success` | `sounds/success.wav` | −21 dBFS | A step reaching 100%, a focus session completing |
| `timer` | `sounds/timer.wav` | −24 dBFS | Focus start/pause and end |

The tap asset is synthesised by `tools/synth_click.mjs`: a 210 Hz body that glides
down to about 172 Hz, one quiet partial, a 1.6 ms attack ramp and a 26 ms decay.
It is a wooden tick rather than a click — the old file's bright transient was
what made repeated taps tiring.

The timer cue is `tools/synth_timer.mjs`: one warm 392 Hz note settling to
370 Hz, a quiet octave, an 8 ms raised-cosine attack and a 20 ms cosine tail,
260 ms in total. It replaced a filtered-noise whoosh that read as escaping air
on a phone speaker; a mallet note is a signal, not a texture.

The sound fires inside `InkWell.onTap`, never on press-down, so a scroll that
starts on a button stays silent. `SoundEffects.enabled` gates every call, which
is what the settings switch flips — muting is instant and total.

**Touch.** `core/design/widgets/pressable.dart` is the one tactile layer:

- `KInkSurface` = `RepaintBoundary` → `Material` (fill + shape + `Clip.antiAlias`)
  → `InkWell` (splash, sound). Its key property is *placement*: when a widget
  animates its own background (chips, cards, nav items), the ink surface goes
  **inside** the decorated container. A splash painted on an ancestor `Material`
  would sit underneath that fill and be invisible.
- `KPressable` = `Semantics(button)` → `PressScale(0.96, 100 ms down / 140 ms
  release)` → `KInkSurface`. It owns its colour, so it is used where there is no
  parent decoration (`KButton`).
- Full-width `KCard`s squish to 0.98 instead of 0.96: four percent on a card the
  width of the screen reads as a layout jump, not a press.

**Motion.** Primitives live in `core/motion`: `PressScale`, shared durations
(240 ms dialogs, 360 ms theme cross-fade, 400 ms auth entry), and haptics.
Route transitions: `authEntryPage` = fade + scale 0.95→1.0 over 400 ms (used
only for `/today`, i.e. the post-login landing); `khutatiPage` = fade + 2% slide
for secondary routes.

---

## 10. Launch and onboarding (`lib/features/onboarding`)

The launch is one continuous dark surface in three phases: the native window, the
Flutter splash, and the three welcome slides. Nothing in the sequence may show a
lighter colour than `#0D1A2D`, or the hand-offs become visible seams.

### 10.1 Native window

`values/styles.xml` paints `windowBackground`, the status bar and the navigation
bar in `launch_background` (`#0D1A2D`) for both the launch and normal themes.
Android 12+ ignores `windowBackground` for its own splash and draws the launcher
icon on a system-chosen surface instead, which is the blue tile users saw first;
`values-v31/styles.xml` (and its `-night` twin) sets
`windowSplashScreenBackground` and `windowSplashScreenAnimatedIcon` to the same
colour, so the system phase is a blank dark screen and the Flutter splash picks
up from exactly there.

### 10.2 Splash

`SplashScreen` draws three glowing waves from the inline-start edge plus a radial
halo, then reveals the wordmark and the quote with `Curves.easeOutExpo`. It holds
`SplashScreen.hold` (2500 ms) and then goes to `/onboarding` or `/today`
depending on `onboarding_seen_v1`. Two app-level surfaces are gated on
`launchReadyProvider` so they never interrupt it: the update dialog and the
notification-permission prompt.

`/splash` is the router's `initialLocation` and the only route `redirect` lets
through unconditionally — it is the thing that reads the persisted state.

### 10.3 Welcome slides

Three slides, shown exactly once, before login. `khutati-onboarding.html` is the
visual source; the Flutter version replaces its inline SVG and CSS keyframes with
canvas painting and tickers, so the same scene runs at 120 Hz without a
`flutter_svg` decode on the first frame.

**Gate.** `onboardingSeenProvider` (`OnboardingController`, `Notifier<bool>`)
reads `onboarding_seen_v1` from `SharedPreferences` synchronously inside
`build()`. While the flag is false, `redirect` sends every route except
`/onboarding` to `/onboarding`; once `complete()` flips it, `/onboarding`
resolves to `/today` or `/login` depending on the session. The flag is written on
Skip or ابدأ only — never on a swipe.

**Art.** Each slide is exactly two painters:

- `HillsPainter` — the static backdrop (back hill, front hill, clipped radial
  glow at 0.32, 56×64 hexagon tile at 6% white). It sits in its own
  `RepaintBoundary` and `shouldRepaint` returns `false`: rasterised once per
  size, never touched again.
- the slide's foreground painter, constructed with
  `super(repaint: Listenable.merge([enter, ambient]))`.

`enterDesignSpace(canvas, size)` reproduces the SVG's
`preserveAspectRatio="xMidYMax meet"` for a 390×540 box, so every coordinate in
the painters is the literal number from the HTML. The hills stretch full-bleed
instead, so no aspect ratio leaves an unpainted edge.

**Timing.** The master clock is real seconds, not a normalised 0→1: `enter` is a
7 s linear controller replayed when a slide becomes active, and `ambient` is a
2-hour controller played once. Every element then applies its own CSS delay and
duration through `stage(elapsed, delay:, duration:)` and `cycle(elapsed, period:)`,
which is what keeps the prototype's deliberate pacing:

| Element | Delay | Duration / period |
|---|---|---|
| road draw | 0.4 s | 3.2 s, ease-out |
| nodes (ring, dot) | 2.0 → 4.4 s, 0.6 apart | 1.2 s, `cubic-bezier(.3,1.6,.5,1)` |
| node halos | 4.8 → 8.8 s | 5 s loop |
| flag pole / banner | 3.8 s / 4.6 s | 1.6 s grow / 1.2 s pop |
| banner wave | — | 4.6 s loop |
| travelling light | 5.6 s | 14 s loop |
| floating stars | 0 / 2.6 / 4 s | 7 s loop |
| clock ticks / arc | 0.1 s apart / 1.0 s | 1.2 s / 4.4 s |
| task rows / checks | 1.0 / 1.5 / 2.0 s | 1.4 s slide / 1.0 s draw |
| bars | 0.3 → 1.74 s, 0.36 apart | 1.6 s grow |
| trend line | — | 12 s: draw 6 s, hold, fade |
| star + particles | — | 12 s burst |

The ambient controller is two hours long on purpose: 4.6, 5, 7, 12 and 14 s have
no common short multiple, so a shared 12 s loop would visibly jump. With a
non-repeating clock each animation keeps its own period and no wrap is ever seen.
Reduced motion parks the scene at `enter = 1`, `ambient = 7 s` — a composed still,
not an empty one.

Shared helpers: `dashPath` uses `PathMetric.extractPath` for the road's dashed
centre line, and `paintText` lays Arabic out with `TextPainter` anchored by
`maxIntrinsicWidth` (`width` is the layout constraint, not the ink extent).

**Transitions.** `PageView` + `PageController`. `_ParallaxPage` wraps each slide
in `AnimatedBuilder(animation: controller, child: slide)` — the `child` is passed
through, so a drag never rebuilds the slide subtree. With the signed page delta
`d = index - page` and `e = easeOutCubic(min(1, |d|))`:

| Property | Formula |
|---|---|
| translate | `Offset(-0.18 * d * width, 0)` |
| opacity | `1 - 0.75 * e` |
| scale | `1 - 0.10 * e` |

A page's slot already travels one full width with the scroll, so the counter
translation makes the outgoing page trail the finger (net 0.82 of a width) while
the incoming page leads it (1.18). The outgoing page shrinks to 0.9 and fades as
it leaves; the incoming one grows back to 1.0. Only the transform is eased — the
horizontal tracking stays linear so the page still follows the finger exactly.

**Chrome.** The skip pill (`onboarding-skip`) sits at the visual top-left — the
inline-end edge in RTL — which also keeps it clear of the red flag in the first
illustration. `_Dots` animate 8→28 px, `redSoft` when active, and expose
`Semantics(selected:, label: 'الشاشة n')`. The primary button
(`onboarding-primary`) reads التالي and becomes ابدأ on page 3. The page reserves
`148 + safe.bottom` so the body copy can never collide with the footer on phones
with a gesture bar.

---

## 11. Performance rules ("zero jank")

The app is only tested in release/profile, so debug-mode smoothness proves
nothing. These are the rules that keep the release build at 60 fps:

**Modals.** `showKDialog` never blurs the backdrop. A full-screen
`BackdropFilter` inside an animated route re-runs a GPU pass over the whole
window on every frame of the entry transition — that was the reported "freeze".
The scrim is a static `ModalBarrier` tint (painted once, then composited), and
only the card fades/scales for 200 ms. The card's own surface is
`RepaintBoundary`-wrapped inside its decorated box so a repaint caused by the
dialog (typing, a loading button) cannot dirty the page.

**Persistent blur.** The only remaining `BackdropFilter` in a scrolling context
is the floating nav bar. It is wrapped in `RepaintBoundary` and kept at sigma 10
(it re-runs whenever content scrolls behind it, so the radius is a direct cost).
The login button's blur is on a static screen and can stay.

**Repaint isolation.** Widgets that animate or repaint independently are in their
own layers: `KEcgLine` (Today), `KProgressRing` (Plan), the focus ring + numeral
(repaints every second while a session runs), the nav bar, and every dialog card.

**Rebuild isolation.** `ref.watch(...).select(...)` is used where a widget needs
one field of a large read model (e.g. the Plan header's points/streak pills), so
it does not rebuild on unrelated changes. The focus timer is the one provider
that emits at 1 Hz; the screen genuinely needs that state, and its repaint is
confined to the ring.

**Lists.** Every unbounded list is lazy: the plan week strip is a horizontal
`ListView.separated`, the focus history is a `ListView.builder`, and the
achievements day map is bounded by design (68 cells). Day-sized `Column`s inside
an outer `ListView` are intentional — converting them to shrink-wrapped lists
would build the same widgets and add layout cost.

**CustomPainter.** Every `shouldRepaint` compares the fields it actually paints
(the hexagon pattern returns `false` unconditionally). Never return `true` "to be
safe": that repaints on every ancestor rebuild.

**Shadows.** Two `BoxShadow`s exist in feature code. Do not add shadows to
scrolling list items; they are rasterised per item per frame.

---

## 12. Testing strategy

`flutter test` runs the suite across:

| Area | File(s) | What is pinned |
|---|---|---|
| Step state machine | `test/domain/step_progress_test.dart` | full 8-tap sequence, distinct 1/3 codes, both halves = 0.5 |
| Sync outbox | `test/data/sync_queue_repository_test.dart` | coalescing, ordering, batch cap, ack-only deletion, attempt counting, re-enqueue reset |
| Database | `test/data/app_database_test.dart` | schema, progress persistence, sync queue insert |
| Schedule engine | `test/domain/schedule_engine_test.dart` | partition, rest days, forwarding, times, invalid input |
| Schedule repository | `test/data/schedule_repository_test.dart` | default mirror, id/week preservation, preview, reset, remote wins, one outbox row |
| Focus log | `test/domain/focus_log_test.dart` | sub-minute filtering, ranges, streak, grouping, activity strip, best day |
| Plan engine | `test/plan_engine_test.dart`, `plan_calendar_matrix_test.dart`, `plan_today_resolution_test.dart` | date mapping, midnight, totals |
| Design parity | `test/design/*` | SVG paths and tokens match the prototype |
| Formatting | `test/core/format_test.dart` | Arabic digits, durations |
| Updates | `test/updates/update_repository_test.dart`, `update_controller_test.dart` | `If-None-Match`/304, 403 → Atom fallback, Supabase last-resort row, empty table is a success, non-HTTPS row rejected, waterfall order, both-fail throws, 60-minute cooldown, silent background failure, honest manual failure, cached ETag |
| Onboarding | `test/onboarding/onboarding_test.dart` | next→start, skip and start persist the flag, dot jump, `complete()` idempotence |
| Launch | `test/onboarding/splash_test.dart` | wordmark and quote render, the 2.5 s hold, first run → onboarding, `launchReadyProvider` unlocks |
| Widgets | `test/design/widgets_test.dart`, `test/today/task_card_layout_test.dart` | layout invariants |

Rules for new tests: database tests use `AppDatabase.memory()` and close in
`tearDown`; never test against the real file DB; keep domain tests free of a
`WidgetsFlutterBinding`.

---

## 13. Error-handling philosophy

- **User actions never fail visibly because of infrastructure.** A failed sync,
  a missing audio sink, a denied permission or a missing native channel is
  swallowed at the boundary and retried later; the UI stays consistent because
  SQLite already has the write.
- **Errors that the user must act on get an Arabic explanation.** Auth failures
  map to specific Arabic messages (`AuthFailure`), never raw exception text.
- **No silent data loss.** The only destructive path is an explicit reset, and it
  deletes user rows only — template tables are untouched.

---

## 14. Practical-weekday schedule and manual placement

The user picks **one to three** practical weekdays in
`/settings/practical-days`. The template is never edited; the effective
schedule is derived, and manual placements sit on top as a second, independent
layer.

- **Persistence.** `ScheduleRepository` stores the weekday choice in
  `app_settings` (`schedule.practical_weekdays_v1`) plus an `updated_at`
  sibling. Removing the key restores the original plan exactly, which is what
  the reset action does. Manual placements live in `schedule_overrides`, one
  row per task; deleting the row restores automatic scheduling for that task.
- **Engine.** `domain/plan/schedule_engine.dart` is pure Dart. Each week's
  ordered task list is partitioned into contiguous groups (one per study day) by
  a DP that minimises squared deviation from a 2:1 normal/practical workload.
  Rest days never move and never receive tasks; a selected weekday that lands on
  a rest day is forwarded to the nearest free day (the original plan's
  Friday-rest → Saturday-practical rule), recomputed **per week** so a partial
  final week still resolves correctly. No task is split or re-identified, so
  progress keyed by task/step id survives a change.
- **Capacity is a target, not a limit.** `~8h55m` normal and `~4h30m`
  practical are the reference loads; the DP may land slightly above or below.
  It never splits an indivisible task to fill minutes, and changing the number
  of practical days is allowed to change total capacity — the preview shows the
  finish-date and per-day load impact instead of hiding it.
- **Manual overrides.** `ScheduleOverrideInput{dayNumber, position?,
  startClock?}` is applied by `_applyOverrides` (custom path) or
  `_patchOriginal` (original path). The original path re-times only the days
  whose task list or pinned clock changed, so one manual move leaves the other
  67 printed days exactly as imported. Overrides are removed from their
  automatic group and re-inserted at the requested position; a pinned start is
  honoured exactly (no break or free block is inserted before it).
- **Validation.** Day-granularity sequence is enforced: a task may not move
  before an earlier task's day or after a later task's day. Ordering *within* a
  day is a soft user preference. Rest-day targets, unknown tasks, overlapping
  pinned starts, past-midnight finishes and malformed clocks are rejected with
  a `TaskMoveIssue` the sheet renders in Arabic.
- **Previews write nothing.** `preview(calendar, selected)` and
  `previewMove(...)` return a proposal (`SchedulePreview`, `TaskMovePreview`)
  with the before/after day types, per-day load deltas, moved-task counts,
  finish-date impact and any overrides that cannot survive. `save` and
  `commitMove` re-resolve and write in a single transaction.
- **Reconciliation.** When a weekday change makes an override unsatisfiable,
  `_resolve` drops overrides newest-first until the schedule builds and reports
  them in `SchedulePreview.droppedOverrides`; the confirmation dialog lists
  them in gold and `save` deletes exactly those rows.
- **One snapshot.** `ScheduleSnapshot` is built once per (weekdays, overrides)
  pair and is read by Plan, Today, progress and achievements. Both controllers
  watch the setting stream, the override table and the sync queue, so a save
  rebuilds every view without a restart.
- **Sync.** A weekday save enqueues `schedule_settings`
  (`practical_weekdays`); each override write enqueues `schedule_override`
  (full row) or a `{deleted: true}` tombstone. `CloudSyncService` upserts to
  `user_schedule_settings` / `user_schedule_overrides` and applies remote values
  with the usual "local wins on ties" rule; an empty weekday array means
  "original".

## 15. Focus log

`features/focus/domain/focus_log.dart` aggregates recorded sessions without
touching Flutter or SQLite: range filters, per-day grouping, totals, completion
rate, streak, best day, per-mode split, and a 14-day activity strip. Rows under
one minute are ignored everywhere, matching the write-side guard in
`FocusController._recordSession`.

`focusLogProvider` streams the table newest-first; `/focus/log` renders it with
range/mode filters, a summary card, the activity chart, a mode breakdown, and a
day-grouped list with a detail sheet. The history button on the focus screen
pushes that route.
