/// Status of a plan day relative to "now" (PRD 5.3).
enum PlanDayStatus { completed, current, overdue, upcoming, rest }

/// Where the device's local date sits relative to the fixed plan window.
enum PlanWindow { beforeStart, active, afterEnd }

/// The plan day a device-local date resolves to.
///
/// [date] is always a date inside the plan: before the start it is Day 1's
/// date, after the end it is the final day's date. [dayNumber] is clamped the
/// same way, so screens always have a valid day to render.
class ResolvedPlanDay {
  const ResolvedPlanDay({
    required this.dayNumber,
    required this.date,
    required this.window,
  });

  final int dayNumber;
  final DateTime date;
  final PlanWindow window;

  bool get hasStarted => window != PlanWindow.beforeStart;
  bool get hasEnded => window == PlanWindow.afterEnd;
}

/// Date mapping for the fixed plan calendar.
///
/// Day 1 is 19 November and Day 68 is 25 January (PRD section 2, decision 3).
/// The template stores no dates; every date is derived here so the database and
/// the PDF can never disagree.
class PlanCalendar {
  PlanCalendar({required DateTime startDate, required this.totalDays})
    : assert(totalDays > 0),
      startDate = DateTime(startDate.year, startDate.month, startDate.day);

  final DateTime startDate;
  final int totalDays;

  static const int daysPerWeek = 7;

  DateTime dateOfDay(int dayNumber) {
    if (dayNumber < 1 || dayNumber > totalDays) {
      throw RangeError.range(dayNumber, 1, totalDays, 'dayNumber');
    }
    // Constructor arithmetic (not Duration) keeps the calendar day stable
    // across DST transitions.
    return DateTime(
      startDate.year,
      startDate.month,
      startDate.day + dayNumber - 1,
    );
  }

  DateTime get endDate => dateOfDay(totalDays);

  /// 1-based plan day for [date], or `null` when the date is outside the plan.
  int? dayNumberFor(DateTime date) {
    final DateTime a = DateTime.utc(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final DateTime b = DateTime.utc(date.year, date.month, date.day);
    final int index = b.difference(a).inDays + 1;
    if (index < 1 || index > totalDays) return null;
    return index;
  }

  int get weekCount => ((totalDays - 1) ~/ daysPerWeek) + 1;

  int weekOfDay(int dayNumber) {
    if (dayNumber < 1 || dayNumber > totalDays) {
      throw RangeError.range(dayNumber, 1, totalDays, 'dayNumber');
    }
    return ((dayNumber - 1) ~/ daysPerWeek) + 1;
  }

  /// Day numbers in [week], clamped to the plan length (week 10 has 5 days).
  List<int> daysInWeek(int week) {
    if (week < 1 || week > weekCount) {
      throw RangeError.range(week, 1, weekCount, 'week');
    }
    final int first = (week - 1) * daysPerWeek + 1;
    final int candidate = first + daysPerWeek - 1;
    final int last = candidate > totalDays ? totalDays : candidate;
    return <int>[for (int day = first; day <= last; day++) day];
  }

  /// Resolves "today" against the device's local calendar date.
  ///
  /// This is the single date rule used by the UI. The plan's own dates never
  /// move: only the local year/month/day of [now] is compared with
  /// [startDate] and [endDate], so the time of day, DST, the device timezone
  /// and the display locale cannot shift a plan day.
  ///
  /// * before [startDate]: Day 1 is shown as a preview (`beforeStart`);
  /// * inside the window: the matching 1-based plan day (`active`);
  /// * after [endDate]: the final day is shown (`afterEnd`) with no days left.
  ///
  /// [now] must be a local wall-clock value (`DateTime.now()` or a value
  /// converted with `toLocal()`); UTC values are read by their UTC fields.
  ResolvedPlanDay resolveToday(DateTime now) {
    final DateTime localDate = DateTime(now.year, now.month, now.day);
    if (localDate.isBefore(startDate)) {
      return ResolvedPlanDay(
        dayNumber: 1,
        date: startDate,
        window: PlanWindow.beforeStart,
      );
    }
    if (localDate.isAfter(endDate)) {
      return ResolvedPlanDay(
        dayNumber: totalDays,
        date: endDate,
        window: PlanWindow.afterEnd,
      );
    }
    return ResolvedPlanDay(
      dayNumber: dayNumberFor(localDate)!,
      date: dateOfDay(dayNumberFor(localDate)!),
      window: PlanWindow.active,
    );
  }

  /// Day number to show as "today". Before the plan starts this is 1; after it
  /// ends it is the final day, so the UI stays in a valid range.
  int currentDayNumber(DateTime now) => resolveToday(now).dayNumber;

  bool hasStarted(DateTime now) => resolveToday(now).hasStarted;

  bool hasEnded(DateTime now) => resolveToday(now).hasEnded;

  /// Days after today, matching the prototype's "باقي N يوماً" on Day 12.
  int daysAfterToday(DateTime now) {
    final ResolvedPlanDay resolved = resolveToday(now);
    return switch (resolved.window) {
      PlanWindow.beforeStart => totalDays,
      PlanWindow.active => totalDays - resolved.dayNumber,
      PlanWindow.afterEnd => 0,
    };
  }

  /// Days left including today; 0 after the plan ends.
  int daysIncludingToday(DateTime now) {
    final ResolvedPlanDay resolved = resolveToday(now);
    return switch (resolved.window) {
      PlanWindow.beforeStart => totalDays,
      PlanWindow.active => totalDays - resolved.dayNumber + 1,
      PlanWindow.afterEnd => 0,
    };
  }

  PlanDayStatus statusOf({
    required int dayNumber,
    required bool isCompleted,
    required bool isRest,
    DateTime? now,
  }) {
    if (isRest) return PlanDayStatus.rest;
    if (isCompleted) return PlanDayStatus.completed;

    final DateTime today = now ?? DateTime.now();
    final DateTime date = dateOfDay(dayNumber);
    final DateTime normalisedToday = DateTime(
      today.year,
      today.month,
      today.day,
    );

    if (date.isBefore(normalisedToday)) return PlanDayStatus.overdue;
    if (date.isAtSameMomentAs(normalisedToday)) return PlanDayStatus.current;
    return PlanDayStatus.upcoming;
  }
}
