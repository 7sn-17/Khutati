# Khutati (خطتي) — Product Requirements Document

**Version:** 1.1 (Lean MVP, private use) · **Platform:** Android (Flutter) · **Primary language:** Arabic (RTL) · **Status:** Draft for approval

---

## 0. Change Log (v1.0 → v1.1)

- The app is **private** (owner + friends only). No store release, no monetization, no public distribution.
- The plan is **date-anchored**: Day 1 = **19 November**, Day 68 = **25 January**.
- Accounts: **Google Sign-In required once on first launch, then the app works fully offline**. Cloud sync is removed from the MVP.
- Focus timers are **derived from video durations** by default; **Pomodoro is an optional mode** the user can choose freely.
- Scope reduced to a lean MVP. Deferred items are listed in section 1.2 and marked *(Deferred)* below.
- The HTML prototype is now attached and is the **design source of truth**.
- PDF extraction rules strengthened: 100% coverage, zero tolerance for text errors (section 3).
- Added a **local backup/restore file** (replaces cloud sync as the data-safety net).

---

## 1. Product Overview

**Khutati** ("My Plan") is an Arabic-first, offline-first study-plan app. It ships with a ready-made, fully structured **68-day study plan** (imported from the supplied PDF) and turns it into a living system: daily tasks, a focus timer that survives leaving the app, and real progress analytics.

The visual identity is defined by the approved **HTML prototype** (colors, fonts, layout, motion). The app must preserve that identity while fixing the prototype's functional limits (hard-coded sample data, fake rescheduling, static stats).

### 1.1 Goals

- After the one-time Google sign-in, the user immediately follows the full 68-day plan with zero setup.
- Every number in the UI (progress, hours, streaks) derives from real user activity.
- A focus timer that keeps running reliably in the background and matches the plan's own structure (watch a video, then study it for the same duration).
- Works fully offline after the first sign-in.
- A premium, distinctive Arabic experience.

### 1.2 Non-Goals

**Out of scope entirely:** public release, store listing, ads, subscriptions, social features, leaderboards, AI tutoring, iOS, English UI (architecture stays ready for it).

**Deferred beyond the MVP:**

- Cloud sync and multi-device restore
- Home-screen widgets
- Animated video Focus Scenes and ambient sounds
- Levels, badges, points, streak-freeze
- Completion certificate and shareable image
- Full plan editing (add/rename/reorder anything) and the smart rescheduling engine
- Multiple plans and custom plan creation

### 1.3 Target Audience

The owner and a small group of friends following the Professor MedX first-semester plan (Medical Chemistry, Medical Physics, Cell Biology, History of Medicine, English 1).

---

## 2. Product Decisions

| # | Area | Decision |
| --- | --- | --- |
| 1 | Product type | Study system with one ready-made plan |
| 2 | Distribution | Private, owner and friends only (APK shared directly) |
| 3 | Plan dates | Fixed start: Day 1 = 19 Nov; Day N = 19 Nov + (N − 1) days; Day 68 = 25 Jan |
| 4 | Plan management | One built-in plan |
| 5 | Plan completion | Simple completion screen with final stats; saved to history *(certificate and share image deferred)* |
| 6 | Task display | Hybrid: summary tasks, expandable into steps (attend, study, solve) |
| 7 | Plan editing | MVP: limited editing (postpone, change duration, personal tasks, notes) with restore-to-default |
| 8 | Accounts | Google Sign-In (via Supabase Auth) required once on first launch only |
| 9 | Connectivity | Fully offline after first sign-in; no cloud sync |
| 10 | Data safety | Local backup/restore file (export/import) |
| 11 | Onboarding | Short intro screens, then Google Sign-In, then straight to Today |
| 12 | UI | Keep the HTML prototype identity and four sections; improve navigation and UX |
| 13 | Notifications | Task reminders, daily summary, and a fully working background timer |
| 14 | Focus timer | Default: derived from the video duration. Optional: Pomodoro presets or custom. The user chooses freely, per session or as a default |
| 15 | Theme | Auto (follow system), Light, Dark; persisted |
| 16 | Language | Arabic only with RTL; i18n-ready |
| 17 | Tech stack | Flutter, Drift (SQLite), Supabase Auth |
| 18 | Motivation | Real streaks and hours only; rest days never break a streak |
| 19 | App name | خطتي (Khutati) |

---

## 3. Source Plan Data (from the PDF)

The PDF (74 pages) defines the structure the data model must reproduce exactly.

- **68 days** total; **64 study days** and **4 rest days** (days 15, 30, 45, 60 — pages 21, 36, 51, 66 contain only a rest-day heading).
- **480 hours 9 minutes** of study. Internal calculations must use the exact value.
- **Five subjects:** Medical Chemistry, Medical Physics, Cell Biology, History of Medicine, English 1.
- **Phase 1 (days 1–47):** Chemistry (until day 27) then Physics, alternating each day with English and History. **Phase 2 (days 48–68):** Cell Biology only.
- **Practical days:** 20 days (days 2 and 5 of each week), at half the normal study time; the user can move them.
- **Time accounting rules:**
  - Video attendance (watching) counts as study time.
  - Studying the video right after is a separate timed step of the same duration.
  - Course-question solving: one hour after finishing each chapter.
  - Foundation videos: study time is half the video duration, and they have no course questions.
  - Breaks and free time are **excluded** from study hours.
- Each day also contains fixed clock times (start 8:00 AM on normal days, 4:00 PM on practical days), 15-minute breaks, and a 2-hour free block on normal days. These are kept as **suggested times** and never counted as study time.

### 3.1 Extraction Requirements (zero-error)

- **Full coverage:** every page, day, period, video, break, free block, course-question hour, and chapter heading in the PDF must be captured. Nothing may be skipped or summarized.
- **Any method is allowed** (text-layer extraction, position-based parsing, OCR, page-image reading), and methods may be combined.
- **Arabic text must be exact:** the PDF's text layer is visually reversed/garbled in places (for example the rest-day pages and some titles), so every Arabic string must be verified against the page image. No typos, no wrong letters, no broken ligatures, no reversed word order, no spelling "improvements". Original wording is kept as written, including original spelling quirks.
- **Structured output:** one JSON dataset with stable IDs, produced by script and never typed into UI code.
- **Validation (all must pass before the dataset is accepted):**
  1. Per-day study total equals the "study X h Y min" value printed on that day's page header.
  2. Per-subject attendance, study, and course totals equal the table on page 2.
  3. Grand total equals 480 h 9 min.
  4. Day count, rest-day positions, practical-day positions, and phase boundaries match section 3.
  5. Every video's attendance and study intervals add up to the printed durations.
  6. A visual spot-check report (extracted text vs page image) for every page; discrepancies are fixed, not ignored.
- Any ambiguity or unreadable item is **reported to the owner explicitly** instead of guessed.

> **Data integrity requirement:** the dataset is the only source for plan content in the app. No plan content is hard-coded in UI code.

---

## 4. Information Architecture

Four primary sections, preserved from the prototype:

1. **Today (اليوم)** — the home and center of the app.
2. **Plan (الخطة)** — weeks, days, subjects, calendar view.
3. **Focus (التركيز)** — the timer.
4. **Achievements (الإنجازات)** — analytics and history.

Secondary: Settings, Notes, Task detail, Day detail, Search, Onboarding, Completion screen.

---

## 5. Functional Requirements

### 5.1 Onboarding & Authentication

- Short, skippable intro screens on first launch only (plan, tracking, timer, offline use).
- Google Sign-In through Supabase Auth, **required once**. After a successful sign-in the session is stored and the app never needs the network again.
- After sign-in the user lands on **Today** with the 68-day plan already loaded from the app bundle (no download).
- Sign-out available in Settings. Signing out must warn clearly that signing in again needs internet.

### 5.2 Today Screen

- Greeting, day number, and the real date for that day.
- Animated daily progress indicator.
- Current task and next task.
- Time remaining to finish the day's plan.
- One-tap **Start Focus** button.
- Expandable task list for the day.
- This week's study-hours summary.
- Overdue alert listing unfinished tasks from earlier days, with a postpone action per task.
- **Continue where you left off** card: if the user left mid-task, show it with options to resume the timer or mark it complete.

### 5.3 Plan Screen

- Weeks and days overview with status (completed, current, upcoming, overdue, rest day), aligned to real dates.
- Day detail with all tasks, planned vs actual time.
- Subject and chapter views.
- Calendar view.
- Search for any lesson, video, or chapter.

### 5.4 Tasks (Hybrid Model)

Each day shows main tasks in a compact list; each task expands into steps (attend video, study video, solve chapter questions).

**MVP capabilities:**

- Complete / uncomplete per task and per step; day progress updates instantly.
- Status: not started, in progress, completed, postponed.
- Postpone to another day.
- Notes per task.
- Flag **Review later**; a Review list aggregates flagged items.
- Launch a focus session linked to the task or step.
- Planned time vs actual time (from real focus sessions).
- Secondary actions via long-press or a compact menu.

*(Deferred: priority levels, splitting tasks, task history timestamps.)*

### 5.5 Plan Editing & Reset

**MVP editing:** change a task's duration, postpone tasks, add and delete personal tasks, move practical days, mark a day as rest.

**Restore to default:** per item (task or day) and for the whole plan, with a confirmation dialog showing what will be reverted. Completion history and focus sessions are kept wherever the original item still exists.

Requires stable IDs for every original plan item and a **separation of the read-only template from user overrides**.

*(Deferred: full editing of everything, and the smart rescheduling engine that redistributes overdue work by the original rules.)*

### 5.6 Focus Timer

**Timer modes (the user chooses freely):**

- **Video-linked (default):** a session for a video step uses the planned duration from the plan data. Attendance step = video duration; study step = the study duration defined for that video.
- **Pomodoro (optional):** presets 25/5, 50/10, 90/20, and Custom; can be set as the default in Settings or picked per session.
- **Free timer:** manual duration.

**Core behavior:**

- Circular animated timer with smooth transitions.
- Shows subject and lesson name.
- Pause and resume without losing time.
- Optional auto-transition between focus and break.
- Full-screen mode, plain dark background.
- When a video-linked session ends, offer to mark the step complete.
- Sessions are saved and feed analytics and task actual-time.

**Background reliability (core requirement):**

- The timer keeps running when the user leaves the app or the screen turns off.
- Android foreground service plus timestamp-based calculation (store start time and target end time; never rely on a ticking counter alone).
- Exact alarm or equivalent scheduled alert when a session or break ends.
- State survives process death and app restart.
- Handle OEM battery-saver restrictions: guide the user to exempt the app when needed.

**Persistent interactive notification:** task name, remaining time, state (Focus / Break); actions Pause, Resume, End session, Start next break.

*(Deferred: animated video scenes and ambient sounds.)*

### 5.7 Achievements & Analytics

All figures derived from real data:

- Total actual study hours; separate totals for attendance, study, and course-question solving.
- Progress by subject, by chapter, daily, weekly.
- Planned vs actual time.
- Completed and overdue task counts.
- Streak and commitment days. **Scheduled rest days never break a streak.**
- Plan completion map (day grid).

**Tone guardrail:** messaging stays encouraging; no shaming copy for missed days.

*(Deferred: levels, badges, points, streak-freeze.)*

### 5.8 Plan Completion

When all 68 days are complete, the plan auto-marks as completed and a dedicated completion screen shows the final statistics, saved to history. *(Certificate and share image deferred.)*

### 5.9 Notifications & Reminders

Individually toggleable:

- Task reminders and heads-up shortly before a task is due.
- Daily progress summary.
- Review-later reminders.
- Timer notifications (see 5.6).

Android 13+ notification permission and exact-alarm permission flows must be handled gracefully, with fallbacks if denied.

### 5.10 Home-Screen Widgets

*(Deferred.)* The architecture must not block adding native widgets later.

### 5.11 Settings

- Theme: Auto / Light / Dark.
- Notification preferences by type.
- Focus defaults: timer mode, Pomodoro presets, sound, haptics.
- Rest-day management.
- **Backup and restore:** export all user data (progress, edits, sessions, notes, settings) to a file and import it back. This is the only protection against losing data when changing or resetting a phone, so it must be reliable and tested.
- Restore plan to default.
- Account: sign-out.
- Language (Arabic now; selector hidden until English exists).

---

## 6. Data Model & Storage

### 6.1 Principles

- **Local-only:** the local SQLite database is the source of truth. Every write is saved locally.
- **Original vs user data are separate.** Plan template data ships in the app (versioned, read-only). User data (progress, overrides, additions, sessions, notes, settings) is stored separately, so editing never corrupts the template and reset is always possible.
- Stable unique IDs for every template entity.
- Dates are computed from the fixed start date (19 Nov) and never stored in the template.

### 6.2 Core Entities

`Plan` · `Subject` · `Chapter` · `Lesson/Video` · `Day` · `Task` · `Step` · `Break` · `UserTaskState` · `UserOverride` · `UserAddition` · `FocusSession` · `Note` · `Settings`

Template tasks carry typed time fields: attendance minutes, study minutes, question-solving minutes, task type (foundation / lecture / course questions), suggested clock times, and break flags, so hours can be recomputed exactly.

### 6.3 Backup

- Export produces a single versioned file containing all user data.
- Import validates the version and shows a summary before replacing local data.

### 6.4 Authentication Data

Supabase is used for authentication only. No plan or progress data is stored in the cloud in the MVP. *(Cloud sync with Row Level Security is deferred.)*

---

## 7. Technical Architecture

| Layer | Choice |
| --- | --- |
| App framework | Flutter + Dart |
| Local DB | SQLite via Drift |
| Sign-in | Supabase Auth + Google Sign-In (first launch only) |
| State management | A single approved solution (for example Riverpod) |
| Native Android layer | Kotlin via platform channels: foreground service, exact alarms, interactive notifications |
| Notifications | Local notifications plus native foreground-service notification |

**Layering:** UI (Flutter) → application/domain logic (plan engine, progress, hours) → repositories → Drift. The plan engine contains no UI code, so screens can be redesigned without touching schedule calculations.

**RTL / i18n:** all strings externalized from day one; layouts use directional (start/end) properties; ready to add English.

---

## 8. Design Requirements

- The attached HTML prototype (خطتي اليومية — version 3) is the **source of truth** for colors, typography, spacing, card style, shapes, and motion character. A token list (colors, fonts, radii, shadows, animation curves) is extracted from it before UI work starts.
- Preserve the four-section structure and visual personality; improve navigation, task cards, stats, and phone-size adaptation.
- Light and dark themes both polished.
- Motion: smooth page transitions, staggered card appearance, animated progress, subtle completion effects, press feedback. Never at the cost of responsiveness.
- Accessibility: readable Arabic type sizes, sufficient contrast, tap targets of at least 48dp, support for system font scaling, reduced-motion option.
- Avoid clutter: secondary actions live in menus or long-press.

---

## 9. Non-Functional Requirements

- **Performance:** cold start under 2.5 s on a mid-range device; smooth 60 fps lists and transitions.
- **Reliability:** timer accuracy within 1 second after any background period; no data loss on crash or kill.
- **Offline:** every feature except the first sign-in works with no connection.
- **Privacy:** minimal data collection; all data stays on the device except the sign-in identity.
- **Compatibility:** Android 8.0 (API 26) and above, with specific handling for Android 12–14 background and alarm restrictions.

---

## 10. Delivery Roadmap

| Phase | Scope |
| --- | --- |
| 0 | Finalize PRD; extract and validate the 68-day dataset; extract design tokens from the HTML prototype |
| 1 | Foundation: Flutter project, design system, RTL, navigation, Drift schema, theming |
| 2 | Plan engine: template import, date mapping, tasks/steps, progress and hours calculation, limited editing and reset |
| 3 | Core screens: Today, Plan, Day, Task detail, Settings |
| 4 | Focus system: native timer service, notifications, video-linked and Pomodoro modes, sessions log |
| 5 | Google sign-in and local backup/restore |
| 6 | Achievements: analytics, streaks, completion screen |
| 7 | QA and release: timer and battery tests on real devices, signed APK |

Builds are produced as signed APKs (for example via GitHub Actions) for phone-based testing and direct sharing with friends.

---

## 11. Success Criteria (personal use)

- The imported plan matches the PDF exactly (all validation checks in section 3.1 pass).
- Timer drift under 2 seconds after background periods.
- Zero progress-loss incidents; backup/restore round-trips without loss.
- Crash-free daily use across the plan period.

---

## 12. Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| PDF extraction errors (garbled RTL text) | Multi-method extraction, hour reconciliation, page-by-page visual verification |
| Background timer killed by OEM battery managers | Foreground service, exact alarms, in-app guidance, testing on real devices |
| Losing data without cloud sync | Reliable export/import backup; periodic backup reminder |
| Needing internet again after sign-out or reinstall | Clear warning before sign-out; keep the session persistent |
| Editing breaks plan integrity | Template/override separation, validation warnings, restore-to-default |
| Flutter-native bridge complexity | Isolate native code behind a small, tested channel API |

---

## 13. Open Questions

1. Arabic-Indic vs Western digits in the UI (recommendation: Western digits, matching the PDF).
2. Backup file format and where it is saved (device storage, share sheet).
3. Whether Pomodoro presets should be adjustable per subject.
4. Whether the user's name appears on the Today greeting (taken from the Google account).

---

## 14. Appendix A — Sample Task Record (illustrative)

```json
{
  "id": "d001-chem-t01",
  "day": 1,
  "dayType": "normal",
  "subject": "medical_chemistry",
  "type": "foundation",
  "title": "فيديو تأسيسي الذرة 1",
  "attendanceMinutes": 23,
  "studyMinutes": 12,
  "suggestedAttendance": "08:00-08:23",
  "suggestedStudy": "08:23-08:35"
}
```

This shows the intended shape only; real values come from validated PDF extraction.
