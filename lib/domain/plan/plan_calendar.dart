/// Status of a plan day relative to "now" (PRD 5.3).
enum PlanDayStatus { completed, current, overdue, upcoming, rest }

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

  /// Day number to show as "today". Before the plan starts this is 1; after it
  /// ends it is the final day, so the UI stays in a valid range.
  int currentDayNumber(DateTime now) {
    if (now.isBefore(startDate)) return 1;
    final int? day = dayNumberFor(now);
    return day ?? totalDays;
  }

  bool hasStarted(DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(startDate);
  }

  bool hasEnded(DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    return today.isAfter(endDate);
  }

  /// Days after today, matching the prototype's "باقي N يوماً" on Day 12.
  int daysAfterToday(DateTime now) {
    if (hasEnded(now)) return 0;
    if (!hasStarted(now)) return totalDays;
    return totalDays - currentDayNumber(now);
  }

  /// Days left including today; 0 after the plan ends.
  int daysIncludingToday(DateTime now) {
    if (hasEnded(now)) return 0;
    if (!hasStarted(now)) return totalDays;
    return totalDays - currentDayNumber(now) + 1;
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
