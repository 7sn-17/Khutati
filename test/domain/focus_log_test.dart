import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/features/focus/domain/focus_log.dart';

final DateTime _now = DateTime(2026, 11, 19, 12);

FocusLogEntry _entry({
  required String id,
  required DateTime at,
  int seconds = 25 * 60,
  int planned = 25 * 60,
  String mode = 'pomodoro',
  String phase = 'focus',
  bool completed = true,
  String? taskTitle,
}) {
  return FocusLogEntry(
    id: id,
    startedAt: at,
    endedAt: at.add(Duration(seconds: seconds)),
    mode: mode,
    phase: phase,
    plannedSeconds: planned,
    actualSeconds: seconds,
    completed: completed,
    taskTitle: taskTitle,
  );
}

void main() {
  test('sub-minute rows never enter the log', () {
    final List<FocusLogEntry> entries = <FocusLogEntry>[
      _entry(id: 'a', at: _now.subtract(const Duration(minutes: 5))),
      _entry(
        id: 'tap',
        at: _now.subtract(const Duration(minutes: 3)),
        seconds: 12,
      ),
    ];

    final FocusLogStats stats = FocusLog.stats(entries, now: _now);
    expect(stats.sessionCount, 1);
    expect(stats.focusSeconds, 25 * 60);
    expect(FocusLog.group(entries).single.entries, hasLength(1));
  });

  test('stats separate focus from breaks and keep the mode split', () {
    final List<FocusLogEntry> entries = <FocusLogEntry>[
      _entry(
        id: 'a',
        at: DateTime(2026, 11, 19, 9),
        seconds: 25 * 60,
        mode: 'pomodoro',
      ),
      _entry(
        id: 'b',
        at: DateTime(2026, 11, 19, 10),
        seconds: 50 * 60,
        mode: 'linked',
        taskTitle: 'مراجعة الفصل',
      ),
      _entry(
        id: 'break',
        at: DateTime(2026, 11, 19, 10, 55),
        seconds: 5 * 60,
        phase: 'break',
        completed: false,
      ),
    ];

    final FocusLogStats stats = FocusLog.stats(entries, now: _now);
    expect(stats.focusSeconds, 75 * 60);
    expect(stats.breakSeconds, 5 * 60);
    expect(stats.sessionCount, 2);
    expect(stats.completedCount, 2);
    expect(stats.secondsByMode['pomodoro'], 25 * 60);
    expect(stats.secondsByMode['linked'], 50 * 60);
    expect(stats.averageSeconds, (75 * 60 / 2).round());
    expect(stats.completionRate, 1.0);
  });

  test('ranges are inclusive calendar windows', () {
    final List<FocusLogEntry> entries = <FocusLogEntry>[
      _entry(id: 'today', at: DateTime(2026, 11, 19, 9)),
      _entry(id: 'yesterday', at: DateTime(2026, 11, 18, 9)),
      _entry(id: 'week', at: DateTime(2026, 11, 14, 9)),
      _entry(id: 'old', at: DateTime(2026, 10, 1, 9)),
    ];

    expect(
      FocusLog.filter(entries, FocusLogRange.today, now: _now),
      hasLength(1),
    );
    expect(
      FocusLog.filter(entries, FocusLogRange.week, now: _now),
      hasLength(3),
    );
    expect(
      FocusLog.filter(entries, FocusLogRange.month, now: _now),
      hasLength(3),
    );
    expect(
      FocusLog.filter(entries, FocusLogRange.all, now: _now),
      hasLength(4),
    );
  });

  test('a mode filter only keeps that mode', () {
    final List<FocusLogEntry> entries = <FocusLogEntry>[
      _entry(id: 'a', at: DateTime(2026, 11, 19, 9)),
      _entry(id: 'b', at: DateTime(2026, 11, 19, 10), mode: 'free'),
    ];

    final List<FocusLogEntry> free = FocusLog.filter(
      entries,
      FocusLogRange.today,
      now: _now,
      mode: 'free',
    );
    expect(free.map((FocusLogEntry entry) => entry.id), <String>['b']);
  });

  test('the streak counts consecutive active days and survives today', () {
    final List<FocusLogEntry> entries = <FocusLogEntry>[
      _entry(id: '1', at: DateTime(2026, 11, 19, 9)),
      _entry(id: '2', at: DateTime(2026, 11, 18, 9)),
      _entry(id: '3', at: DateTime(2026, 11, 17, 9)),
      // A gap on the 16th stops the run at three days.
      _entry(id: '4', at: DateTime(2026, 11, 15, 9)),
    ];
    expect(FocusLog.stats(entries, now: _now).streakDays, 3);

    // Nothing recorded today yet: yesterday's run is still alive.
    final List<FocusLogEntry> noToday = <FocusLogEntry>[
      _entry(id: '2', at: DateTime(2026, 11, 18, 9)),
      _entry(id: '3', at: DateTime(2026, 11, 17, 9)),
    ];
    expect(FocusLog.stats(noToday, now: _now).streakDays, 2);

    // Two empty days end the streak.
    final List<FocusLogEntry> stale = <FocusLogEntry>[
      _entry(id: 'old', at: DateTime(2026, 11, 16, 9)),
    ];
    expect(FocusLog.stats(stale, now: _now).streakDays, 0);
  });

  test('days are grouped newest first with per-day totals', () {
    final List<FocusLogEntry> entries = <FocusLogEntry>[
      _entry(id: 'morning', at: DateTime(2026, 11, 19, 8), seconds: 20 * 60),
      _entry(id: 'evening', at: DateTime(2026, 11, 19, 20), seconds: 30 * 60),
      _entry(id: 'yesterday', at: DateTime(2026, 11, 18, 9), seconds: 25 * 60),
    ];

    final List<FocusLogDay> days = FocusLog.group(entries);
    expect(days, hasLength(2));
    expect(days.first.day, DateTime(2026, 11, 19));
    expect(days.first.focusSeconds, 50 * 60);
    expect(days.first.entries.first.id, 'evening');
    expect(days.last.day, DateTime(2026, 11, 18));
  });

  test('the activity strip keeps empty days and drops old ones', () {
    final List<FocusLogEntry> entries = <FocusLogEntry>[
      _entry(id: 'today', at: DateTime(2026, 11, 19, 9)),
      _entry(id: 'window', at: DateTime(2026, 11, 10, 9)),
      _entry(id: 'outside', at: DateTime(2026, 10, 1, 9)),
    ];

    final List<FocusLogDay> strip = FocusLog.activity(
      entries,
      now: _now,
      days: 14,
    );
    expect(strip, hasLength(14));
    expect(strip.last.day, DateTime(2026, 11, 19));
    expect(strip.last.focusSeconds, 25 * 60);
    expect(strip.first.day, DateTime(2026, 11, 6));
    // 10 Nov is inside the window; 1 Oct is not.
    expect(strip.where((FocusLogDay day) => day.focusSeconds > 0).length, 2);
    expect(
      strip.any((FocusLogDay day) => day.day == DateTime(2026, 11, 11)),
      isTrue,
    );
    expect(strip.first.entries, isEmpty);
  });

  test('the best day is the day with the most focus time', () {
    final List<FocusLogEntry> entries = <FocusLogEntry>[
      _entry(id: 'a', at: DateTime(2026, 11, 17, 9), seconds: 20 * 60),
      _entry(id: 'b', at: DateTime(2026, 11, 18, 9), seconds: 60 * 60),
      _entry(id: 'c', at: DateTime(2026, 11, 18, 20), seconds: 30 * 60),
    ];

    final FocusLogStats stats = FocusLog.stats(entries, now: _now);
    expect(stats.bestDay, DateTime(2026, 11, 18));
    expect(stats.bestDaySeconds, 90 * 60);
    expect(stats.activeDays, 2);
  });
}
