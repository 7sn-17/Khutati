import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/domain/plan/plan_calendar.dart';
import 'package:khutati/domain/plan/plan_dataset.dart';

/// Full calendar matrix for the imported 68-day plan (PRD 5.3).
///
/// Every expectation is derived from the bundled dataset, which
/// `validate_plan_data.mjs` and `PlanDataset.validate` already reconcile
/// against the PDF, so a bad dataset cannot make these tests pass.
void main() {
  final PlanDataset dataset = PlanDataset.parse(
    File('khutati_plan_data.json').readAsStringSync(),
  );
  final PlanCalendar calendar = PlanCalendar(
    startDate: dataset.meta.startDate,
    totalDays: dataset.days.length,
  );

  test('all 68 days map to their dataset date and week', () {
    expect(dataset.days, hasLength(68));

    for (final PlanDay day in dataset.days) {
      final DateTime expected = DateTime(
        day.date.year,
        day.date.month,
        day.date.day,
      );
      expect(
        calendar.dateOfDay(day.dayNumber),
        expected,
        reason: 'day ${day.dayNumber} date',
      );
      expect(
        calendar.weekOfDay(day.dayNumber),
        day.week,
        reason: 'day ${day.dayNumber} week',
      );
      expect(
        calendar.dayNumberFor(day.date),
        day.dayNumber,
        reason: 'day ${day.dayNumber} round trip',
      );
    }

    expect(calendar.dateOfDay(1), DateTime(2026, 11, 19));
    expect(calendar.dateOfDay(68), DateTime(2027, 1, 25));
    expect(calendar.endDate, DateTime(2027, 1, 25));
  });

  test('week buckets partition all days exactly once', () {
    expect(calendar.weekCount, 10);

    final List<int> seen = <int>[];
    for (int week = 1; week <= calendar.weekCount; week++) {
      seen.addAll(calendar.daysInWeek(week));
    }

    expect(seen, <int>[for (int day = 1; day <= 68; day++) day]);
    expect(calendar.daysInWeek(10), <int>[64, 65, 66, 67, 68]);
  });

  test('the four rest days are exactly the metadata days', () {
    final List<int> restDays = <int>[
      for (final PlanDay day in dataset.days)
        if (day.isRest) day.dayNumber,
    ];

    expect(restDays, <int>[15, 30, 45, 60]);
    expect(restDays, dataset.meta.restDays);
    expect(dataset.meta.studyDays, 64);

    for (final int dayNumber in restDays) {
      expect(
        calendar.statusOf(
          dayNumber: dayNumber,
          isCompleted: false,
          isRest: true,
          now: calendar.dateOfDay(dayNumber),
        ),
        PlanDayStatus.rest,
        reason: 'rest day $dayNumber stays rest even today',
      );
      expect(
        dataset.days[dayNumber - 1].items,
        isEmpty,
        reason: 'rest day $dayNumber schedules no work',
      );
    }
  });

  test('the twenty practical days are exactly the metadata days', () {
    const List<int> expectedPracticalDays = <int>[
      2,
      5,
      9,
      12,
      16,
      19,
      23,
      26,
      31,
      33,
      37,
      40,
      44,
      47,
      51,
      54,
      58,
      61,
      65,
      68,
    ];
    final List<int> practicalDays = <int>[
      for (final PlanDay day in dataset.days)
        if (day.isPractical) day.dayNumber,
    ];

    expect(practicalDays, hasLength(20));
    expect(practicalDays, expectedPracticalDays);
    expect(practicalDays, dataset.meta.practicalDays);
  });

  test('phase boundaries match the plan structure', () {
    final Map<String, int> firstDay = <String, int>{};
    final Map<String, int> lastDay = <String, int>{};

    for (final PlanDay day in dataset.days) {
      for (final PlanItem item in day.items) {
        firstDay.update(
          item.subjectKey,
          (int value) => day.dayNumber < value ? day.dayNumber : value,
          ifAbsent: () => day.dayNumber,
        );
        lastDay.update(
          item.subjectKey,
          (int value) => day.dayNumber > value ? day.dayNumber : value,
          ifAbsent: () => day.dayNumber,
        );
      }
    }

    expect(firstDay, <String, int>{
      'chem': 1,
      'eng': 1,
      'hist': 2,
      'phys': 27,
      'bio': 48,
    });
    expect(lastDay, <String, int>{
      'chem': 27,
      'eng': 46,
      'hist': 47,
      'phys': 47,
      'bio': 68,
    });

    // Bio is the only subject after day 47, which is what the last phase of
    // the PDF promises.
    for (final PlanDay day in dataset.days.where(
      (PlanDay day) => day.dayNumber > 47,
    )) {
      expect(
        day.items.every((PlanItem item) => item.subjectKey == 'bio'),
        isTrue,
        reason: 'day ${day.dayNumber} only schedules bio',
      );
    }
  });

  test('statuses stay correct across midnight boundaries', () {
    expect(
      calendar.statusOf(
        dayNumber: 12,
        isCompleted: false,
        isRest: false,
        now: DateTime(2026, 11, 30, 0, 0),
      ),
      PlanDayStatus.current,
    );
    expect(
      calendar.statusOf(
        dayNumber: 12,
        isCompleted: false,
        isRest: false,
        now: DateTime(2026, 11, 30, 23, 59, 59),
      ),
      PlanDayStatus.current,
    );
    expect(
      calendar.statusOf(
        dayNumber: 12,
        isCompleted: false,
        isRest: false,
        now: DateTime(2026, 12, 1, 0, 0),
      ),
      PlanDayStatus.overdue,
    );
    expect(
      calendar.statusOf(
        dayNumber: 13,
        isCompleted: false,
        isRest: false,
        now: DateTime(2026, 11, 30, 23, 59, 59),
      ),
      PlanDayStatus.upcoming,
    );

    // Completion wins over the calendar, so a finished overdue day is not
    // reported as overdue.
    expect(
      calendar.statusOf(
        dayNumber: 3,
        isCompleted: true,
        isRest: false,
        now: DateTime(2027, 1, 20),
      ),
      PlanDayStatus.completed,
    );
  });

  test('today resolves before, during and after the plan', () {
    final DateTime beforeStart = DateTime(2026, 11, 18, 23, 59, 59);

    expect(calendar.hasStarted(beforeStart), isFalse);
    expect(calendar.currentDayNumber(beforeStart), 1);
    expect(calendar.daysAfterToday(beforeStart), 68);
    expect(calendar.daysIncludingToday(beforeStart), 68);
    expect(calendar.dayNumberFor(beforeStart), isNull);

    expect(calendar.hasStarted(DateTime(2026, 11, 19)), isTrue);
    expect(calendar.currentDayNumber(DateTime(2026, 11, 30)), 12);
    expect(calendar.daysAfterToday(DateTime(2026, 11, 30)), 56);
    expect(calendar.daysIncludingToday(DateTime(2026, 11, 30)), 57);

    final DateTime afterEnd = DateTime(2027, 1, 26, 0, 0);
    expect(calendar.hasEnded(DateTime(2027, 1, 25, 23, 59, 59)), isFalse);
    expect(calendar.hasEnded(afterEnd), isTrue);
    expect(calendar.currentDayNumber(afterEnd), 68);
    expect(calendar.daysAfterToday(afterEnd), 0);
    expect(calendar.daysIncludingToday(afterEnd), 0);
    expect(calendar.dayNumberFor(afterEnd), isNull);
  });

  test('calendar-day math ignores time components and survives edges', () {
    // A start date with a time component must normalise to its calendar day.
    final PlanCalendar lateStart = PlanCalendar(
      startDate: DateTime(2026, 11, 19, 23, 30),
      totalDays: 68,
    );
    expect(lateStart.dateOfDay(1), DateTime(2026, 11, 19));
    expect(lateStart.endDate, DateTime(2027, 1, 25));

    // Month and year edges: day 43 is 31 Dec, day 44 is 1 Jan.
    expect(lateStart.dayNumberFor(DateTime(2026, 12, 31, 23, 59, 59)), 43);
    expect(lateStart.dayNumberFor(DateTime(2027, 1, 1, 0, 0)), 44);
    expect(lateStart.dayNumberFor(DateTime(2026, 11, 18, 23, 59, 59)), isNull);

    // UTC input is read by its own calendar fields, not converted, so the
    // answer cannot depend on the device timezone.
    expect(lateStart.dayNumberFor(DateTime.utc(2026, 11, 19, 23, 59)), 1);
    expect(
      lateStart.statusOf(
        dayNumber: 43,
        isCompleted: false,
        isRest: false,
        now: DateTime.utc(2027, 1, 1, 0, 0),
      ),
      PlanDayStatus.overdue,
    );
  });
}
