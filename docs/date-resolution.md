# Date resolution

The plan owns a **fixed** calendar: Day 1 is **19 November 2026** and Day 68 is
**25 January 2027**. Those dates are stored once in `khutati_plan_data.json` and
never move. Only the question "which plan day is it now?" is resolved against
the device's local date.

## The rule

`PlanCalendar.resolveToday(DateTime now)` reads only the local year, month and
day of `now` and returns a `ResolvedPlanDay`:

| Device-local date | Result | Window | Days remaining |
| --- | --- | --- | --- |
| 18 Nov 2026 (any time) | Day 1 preview, 19 Nov | `beforeStart` | 68 |
| 19 Nov 2026 | Day 1 | `active` | 67 |
| 20 Nov 2026 | **Day 2** | `active` | 66 |
| 21 Nov 2026 | **Day 3** | `active` | 65 |
| 25 Jan 2027 | Day 68 | `active` | 0 |
| 26 Jan 2027 (any time) | Day 68, 25 Jan | `afterEnd` | 0 |

- **Time of day is ignored.** 20 Nov at 00:00 and 23:59:59 are both Day 2.
- **Before the start** the UI previews Day 1 (`hasStarted == false`) and reports
  the full plan remaining. It does not invent a Day 0 or a negative number.
- **After the end** the UI keeps the final day (`hasEnded == true`), so the
  screen still has a valid day to render; nothing is counted as remaining.
  Overdue totals still include unfinished work from earlier days.
- **Rest and practical days** are ordinary dates in the same rule. Their type
  (`rest`, `practical`, `normal`) comes from the dataset, never from the date
  arithmetic.
- **Midnight rollover** happens at the device's local midnight. Today listens
  to `LocalDayClock`, which re-emits when the local calendar date changes. It
  checks at least once a minute, so the new day appears within a minute even if
  the midnight timer was throttled while the app was in the background.
- **Timezone changes** move the local date, so the resolved day moves with it.
  The plan dates do not shift. This also covers travel across UTC offsets.
- **Locale and formatting** do not affect the calculation. The day number is
  computed from Gregorian `year/month/day`; `intl` and the ARB only format the
  date line for display (Arabic month names, Western digits).
- **Input contract:** `now` must be device-local wall clock
  (`DateTime.now()`, or an instant converted with `toLocal()`). A UTC `DateTime`
  is read by its UTC fields, which is why the app always passes `DateTime.now()`.

## Implementation

- `lib/domain/plan/plan_calendar.dart` — `resolveToday`, `ResolvedPlanDay`,
  `PlanWindow`. `currentDayNumber`, `hasStarted`, `hasEnded`,
  `daysAfterToday` and `daysIncludingToday` all delegate to this one rule.
- `lib/data/providers.dart` — the calendar's start date is read from the
  dataset's date **text**, not the SQLite `start_date` instant. A stored
  timestamp is converted to the current local timezone when read, which could
  move Day 1 by a day after travel; the dataset text cannot shift.
- `lib/core/time/local_day_clock.dart` — emits the local time on date changes,
  with a one-minute fallback poll for midnight, timezone jumps and resume.
- `lib/features/today/application/today_controller.dart` — watches the clock
  and rebuilds Today from the resolved day; the greeting and weekday quote use
  the same timestamp.

## Tests

`test/plan_today_resolution_test.dart` runs in CI and covers the two acceptance
examples (20 Nov → Day 2, 21 Nov → Day 3), time-of-day independence, before and
after the window, rest/practical days, midnight, timezone jumps and every one
of the 68 dataset dates. `test/plan_calendar_matrix_test.dart` keeps the full
date/week matrix reconciled with the dataset.
