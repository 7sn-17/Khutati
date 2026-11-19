/// Pure aggregation for the focus log.
///
/// The log never reads the database itself: the controller maps rows to
/// [FocusLogEntry] and every number on the screen comes from here, so the
/// statistics are testable without Flutter or SQLite.
library;

/// The ranges offered at the top of the log.
enum FocusLogRange { today, week, month, all }

/// One recorded focus (or break) session, normalised away from Drift.
class FocusLogEntry {
  const FocusLogEntry({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.mode,
    required this.phase,
    required this.plannedSeconds,
    required this.actualSeconds,
    required this.completed,
    this.taskId,
    this.taskTitle,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// `pomodoro`, `free` or `linked`.
  final String mode;

  /// `focus` or `break`.
  final String phase;

  final int plannedSeconds;
  final int actualSeconds;
  final bool completed;
  final String? taskId;
  final String? taskTitle;

  bool get isFocus => phase == 'focus';

  /// Rows written before the one-minute floor existed are still in the table.
  /// They are ignored everywhere so the log stays honest.
  bool get isCountable => actualSeconds >= minimumSeconds;

  static const int minimumSeconds = 60;

  /// Calendar day in local time, used for grouping and streaks.
  DateTime get day => DateTime(startedAt.year, startedAt.month, startedAt.day);

  bool inRange(FocusLogRange range, DateTime now) {
    if (range == FocusLogRange.all) return true;
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int days = switch (range) {
      FocusLogRange.today => 0,
      FocusLogRange.week => 6,
      FocusLogRange.month => 29,
      FocusLogRange.all => 0,
    };
    final DateTime first = today.subtract(Duration(days: days));
    return !day.isBefore(first) && !day.isAfter(today);
  }
}

/// One day of the log, newest entries first.
class FocusLogDay {
  FocusLogDay({required this.day, required List<FocusLogEntry> entries})
    : entries = List<FocusLogEntry>.unmodifiable(
        List<FocusLogEntry>.of(entries)..sort(
          (FocusLogEntry a, FocusLogEntry b) =>
              b.startedAt.compareTo(a.startedAt),
        ),
      );

  final DateTime day;
  final List<FocusLogEntry> entries;

  List<FocusLogEntry> get focusEntries => entries
      .where((FocusLogEntry entry) => entry.isFocus)
      .toList(growable: false);

  int get focusSeconds => focusEntries.fold<int>(
    0,
    (int sum, FocusLogEntry entry) => sum + entry.actualSeconds,
  );

  int get breakSeconds => entries
      .where((FocusLogEntry entry) => !entry.isFocus)
      .fold<int>(
        0,
        (int sum, FocusLogEntry entry) => sum + entry.actualSeconds,
      );

  int get completedCount =>
      focusEntries.where((FocusLogEntry entry) => entry.completed).length;

  bool get isEmpty => entries.isEmpty;
}

/// Every headline number for one range.
class FocusLogStats {
  const FocusLogStats({
    required this.focusSeconds,
    required this.breakSeconds,
    required this.sessionCount,
    required this.completedCount,
    required this.streakDays,
    required this.bestDaySeconds,
    required this.bestDay,
    required this.secondsByMode,
    required this.activeDays,
  });

  final int focusSeconds;
  final int breakSeconds;
  final int sessionCount;
  final int completedCount;

  /// Consecutive days with at least one focus session, ending today or
  /// yesterday. A day that has not started yet never breaks the streak.
  final int streakDays;

  final int bestDaySeconds;
  final DateTime? bestDay;

  /// Focus seconds per mode (`pomodoro`, `linked`, `free`).
  final Map<String, int> secondsByMode;

  final int activeDays;

  int get averageSeconds =>
      sessionCount == 0 ? 0 : (focusSeconds / sessionCount).round();

  /// 0..1, the share of sessions that ran to their planned end.
  double get completionRate =>
      sessionCount == 0 ? 0.0 : completedCount / sessionCount;

  bool get isEmpty => sessionCount == 0;
}

abstract final class FocusLog {
  /// Groups countable entries by calendar day, newest day first.
  static List<FocusLogDay> group(List<FocusLogEntry> entries) {
    final Map<DateTime, List<FocusLogEntry>> buckets =
        <DateTime, List<FocusLogEntry>>{};
    for (final FocusLogEntry entry in entries) {
      if (!entry.isCountable) continue;
      buckets.putIfAbsent(entry.day, () => <FocusLogEntry>[]).add(entry);
    }
    final List<DateTime> days = buckets.keys.toList()
      ..sort((DateTime a, DateTime b) => b.compareTo(a));
    return <FocusLogDay>[
      for (final DateTime day in days)
        FocusLogDay(day: day, entries: buckets[day]!),
    ];
  }

  static List<FocusLogEntry> filter(
    List<FocusLogEntry> entries,
    FocusLogRange range, {
    required DateTime now,
    String? mode,
  }) {
    return <FocusLogEntry>[
      for (final FocusLogEntry entry in entries)
        if (entry.isCountable &&
            entry.inRange(range, now) &&
            (mode == null || entry.mode == mode))
          entry,
    ];
  }

  static FocusLogStats stats(
    List<FocusLogEntry> entries, {
    required DateTime now,
  }) {
    final List<FocusLogEntry> focus = <FocusLogEntry>[
      for (final FocusLogEntry entry in entries)
        if (entry.isCountable && entry.isFocus) entry,
    ];
    final List<FocusLogEntry> breaks = <FocusLogEntry>[
      for (final FocusLogEntry entry in entries)
        if (entry.isCountable && !entry.isFocus) entry,
    ];

    final Map<String, int> byMode = <String, int>{};
    final Map<DateTime, int> perDay = <DateTime, int>{};
    int completed = 0;
    for (final FocusLogEntry entry in focus) {
      byMode.update(
        entry.mode,
        (int value) => value + entry.actualSeconds,
        ifAbsent: () => entry.actualSeconds,
      );
      perDay.update(
        entry.day,
        (int value) => value + entry.actualSeconds,
        ifAbsent: () => entry.actualSeconds,
      );
      if (entry.completed) completed += 1;
    }

    DateTime? bestDay;
    int bestSeconds = 0;
    for (final MapEntry<DateTime, int> day in perDay.entries) {
      if (day.value > bestSeconds) {
        bestSeconds = day.value;
        bestDay = day.key;
      }
    }

    return FocusLogStats(
      focusSeconds: focus.fold<int>(
        0,
        (int sum, FocusLogEntry entry) => sum + entry.actualSeconds,
      ),
      breakSeconds: breaks.fold<int>(
        0,
        (int sum, FocusLogEntry entry) => sum + entry.actualSeconds,
      ),
      sessionCount: focus.length,
      completedCount: completed,
      streakDays: _streak(perDay.keys.toSet(), now),
      bestDaySeconds: bestSeconds,
      bestDay: bestDay,
      secondsByMode: Map<String, int>.unmodifiable(byMode),
      activeDays: perDay.length,
    );
  }

  /// One slot per day for the activity chart, oldest first.
  ///
  /// Empty days are included on purpose: a gap is information, and the chart
  /// must not silently close it.
  static List<FocusLogDay> activity(
    List<FocusLogEntry> entries, {
    required DateTime now,
    int days = 14,
  }) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final Map<DateTime, List<FocusLogEntry>> buckets =
        <DateTime, List<FocusLogEntry>>{};
    for (final FocusLogEntry entry in entries) {
      if (!entry.isCountable) continue;
      final int age = today.difference(entry.day).inDays;
      if (age < 0 || age >= days) continue;
      buckets.putIfAbsent(entry.day, () => <FocusLogEntry>[]).add(entry);
    }
    return <FocusLogDay>[
      for (int offset = days - 1; offset >= 0; offset--)
        FocusLogDay(
          day: today.subtract(Duration(days: offset)),
          entries:
              buckets[today.subtract(Duration(days: offset))] ??
              const <FocusLogEntry>[],
        ),
    ];
  }

  static int _streak(Set<DateTime> activeDays, DateTime now) {
    if (activeDays.isEmpty) return 0;
    final DateTime today = DateTime(now.year, now.month, now.day);
    // A streak survives until the end of today: starting the day with no
    // session yet must not reset a run built over the previous days.
    DateTime cursor = activeDays.contains(today)
        ? today
        : today.subtract(const Duration(days: 1));
    int streak = 0;
    while (activeDays.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
