import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/core/time/local_day_clock.dart';
import 'package:khutati/domain/plan/plan_calendar.dart';
import 'package:khutati/domain/plan/plan_dataset.dart';

/// Locks the rule that maps the device-local calendar date onto the fixed
/// 68-day plan. The plan's dates themselves never move.
void main() {
  final PlanDataset dataset = PlanDataset.parse(
    File('khutati_plan_data.json').readAsStringSync(),
  );
  final PlanCalendar calendar = PlanCalendar(
    startDate: dataset.meta.startDate,
    totalDays: dataset.days.length,
  );

  test('the two acceptance examples resolve to Day 2 and Day 3', () {
    expect(calendar.resolveToday(DateTime(2026, 11, 20)).dayNumber, 2);
    expect(calendar.resolveToday(DateTime(2026, 11, 21)).dayNumber, 3);
  });

  test('time of day never changes the plan day', () {
    for (final DateTime now in <DateTime>[
      DateTime(2026, 11, 20, 0, 0),
      DateTime(2026, 11, 20, 12, 0),
      DateTime(2026, 11, 20, 23, 59, 59, 999),
    ]) {
      expect(calendar.resolveToday(now).dayNumber, 2, reason: '$now');
    }
  });

  test('before the start it previews Day 1 and reports the full plan', () {
    final ResolvedPlanDay resolved = calendar.resolveToday(
      DateTime(2026, 11, 18, 23, 59, 59),
    );

    expect(resolved.dayNumber, 1);
    expect(resolved.date, DateTime(2026, 11, 19));
    expect(resolved.window, PlanWindow.beforeStart);
    expect(resolved.hasStarted, isFalse);
    expect(resolved.hasEnded, isFalse);
    expect(calendar.daysAfterToday(DateTime(2026, 11, 18)), 68);
    expect(calendar.daysIncludingToday(DateTime(2026, 11, 18)), 68);
    expect(calendar.dayNumberFor(DateTime(2026, 11, 18)), isNull);
  });

  test('after the end it keeps the final day and reports zero remaining', () {
    final ResolvedPlanDay resolved = calendar.resolveToday(
      DateTime(2027, 1, 26, 0, 0),
    );

    expect(resolved.dayNumber, 68);
    expect(resolved.date, DateTime(2027, 1, 25));
    expect(resolved.window, PlanWindow.afterEnd);
    expect(resolved.hasStarted, isTrue);
    expect(resolved.hasEnded, isTrue);
    expect(calendar.daysAfterToday(DateTime(2027, 1, 26)), 0);
    expect(calendar.daysIncludingToday(DateTime(2027, 1, 26)), 0);
  });

  test('rest and practical days resolve from the same date rule', () {
    // Day 15 is 3 Dec and is the first rest day; Day 2 is 20 Nov and is
    // practical. The type comes from the dataset, never from the date.
    expect(dataset.days[14].isRest, isTrue);
    expect(dataset.days[1].isPractical, isTrue);

    expect(calendar.resolveToday(DateTime(2026, 12, 3)).dayNumber, 15);
    expect(dataset.days[14].date, DateTime(2026, 12, 3));
    expect(calendar.resolveToday(DateTime(2026, 11, 20)).dayNumber, 2);
    expect(dataset.days[1].date, DateTime(2026, 11, 20));
  });

  test('midnight rolls the day forward without changing the plan', () {
    expect(
      calendar.resolveToday(DateTime(2026, 11, 29, 23, 59, 59)).dayNumber,
      11,
    );
    expect(calendar.resolveToday(DateTime(2026, 11, 30, 0, 0)).dayNumber, 12);
    expect(
      calendar.resolveToday(DateTime(2027, 1, 25, 23, 59, 59)).dayNumber,
      68,
    );
    expect(
      calendar.resolveToday(DateTime(2027, 1, 26, 0, 0)).window,
      PlanWindow.afterEnd,
    );
  });

  test('a local-date jump (timezone travel) moves the day with it', () {
    // These are wall-clock dates as DateTime.now() would report them after a
    // timezone change; no conversion is applied to the plan dates.
    expect(calendar.resolveToday(DateTime(2026, 11, 21, 0, 30)).dayNumber, 3);
    expect(calendar.resolveToday(DateTime(2026, 11, 20, 23, 30)).dayNumber, 2);
  });

  test('every one of the 68 dataset dates round-trips through the rule', () {
    for (final PlanDay day in dataset.days) {
      final ResolvedPlanDay resolved = calendar.resolveToday(
        DateTime(day.date.year, day.date.month, day.date.day, 12),
      );
      expect(resolved.dayNumber, day.dayNumber, reason: 'day ${day.dayNumber}');
      expect(resolved.date, day.date, reason: 'day ${day.dayNumber}');
      expect(resolved.window, PlanWindow.active);
    }
  });

  group('LocalDayClock', () {
    test('emits when midnight advances the local date', () async {
      final List<DateTime> times = <DateTime>[
        DateTime(2026, 11, 19, 23, 59, 59),
        DateTime(2026, 11, 20, 0, 0, 1),
      ];
      int index = 0;
      final LocalDayClock clock = LocalDayClock(
        now: () => times[index < times.length ? index++ : times.length - 1],
        maxPoll: const Duration(milliseconds: 5),
      );

      expect(await clock.watch().take(2).toList(), times);
    });

    test('emits when a timezone jump moves the local date backwards', () async {
      final List<DateTime> times = <DateTime>[
        DateTime(2026, 11, 20, 1, 0),
        DateTime(2026, 11, 19, 23, 0),
      ];
      int index = 0;
      final LocalDayClock clock = LocalDayClock(
        now: () => times[index < times.length ? index++ : times.length - 1],
        maxPoll: const Duration(milliseconds: 5),
      );

      expect(await clock.watch().take(2).toList(), times);
    });
  });
}
