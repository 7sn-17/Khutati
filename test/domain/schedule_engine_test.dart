import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/domain/plan/practical_weekdays.dart';
import 'package:khutati/domain/plan/schedule_engine.dart';

/// A small deterministic plan: two Monday-first weeks, Wednesday is the rest
/// day, and every task has two steps so step spans can be checked.
List<ScheduleDayInput> _days() {
  return <ScheduleDayInput>[
    for (int week = 1; week <= 2; week++)
      for (int offset = 0; offset < 7; offset++)
        ScheduleDayInput(
          dayNumber: (week - 1) * 7 + offset + 1,
          week: week,
          date: DateTime(2026, 11, 16 + (week - 1) * 7 + offset),
          isRest: offset == 2,
        ),
  ];
}

/// Twelve tasks per week: two land on every active day, which also exercises
/// the "no empty study day" rule.
List<ScheduleTaskInput> _tasks() {
  return <ScheduleTaskInput>[
    for (int index = 0; index < 24; index++)
      ScheduleTaskInput(
        id: 't${index + 1}',
        sourceDayNumber: (index ~/ 12) * 7 + (index % 12 < 6 ? 1 : 2),
        sourceOrder: index % 12 + 1,
        minutes: 45 + (index % 4) * 15,
        steps: <ScheduleStepInput>[
          ScheduleStepInput(
            id: 't${index + 1}-s1',
            minutes: 30 + (index % 4) * 15,
            order: 1,
          ),
          ScheduleStepInput(id: 't${index + 1}-s2', minutes: 15, order: 2),
        ],
      ),
  ];
}

int _minutes(String clock) {
  final List<String> parts = clock.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

void main() {
  test('every task is placed once and keeps its identity and order', () {
    final ScheduleGeneration result = ScheduleEngine.generate(
      days: _days(),
      tasks: _tasks(),
      practicalWeekdays: <int>[DateTime.monday, DateTime.friday],
    );

    expect(result.days, hasLength(14));
    expect(result.placements, hasLength(24));

    final List<String> placed = <String>[
      for (final GeneratedDay day in result.days) ...day.taskIds,
    ];
    expect(placed.toSet(), <String>{for (int i = 1; i <= 24; i++) 't$i'});
    expect(placed, hasLength(24));

    // Tasks never leave their week and never overtake each other.
    for (int week = 1; week <= 2; week++) {
      final List<String> weekOrder = <String>[
        for (final GeneratedDay day in result.days)
          if (day.week == week) ...day.taskIds,
      ];
      final int first = (week - 1) * 12 + 1;
      expect(weekOrder, <String>[
        for (int i = first; i < first + 12; i++) 't$i',
      ]);
    }
  });

  test('rest days stay empty and never move', () {
    final ScheduleGeneration result = ScheduleEngine.generate(
      days: _days(),
      tasks: _tasks(),
      practicalWeekdays: <int>[DateTime.monday, DateTime.friday],
    );

    for (final int dayNumber in <int>[3, 10]) {
      final GeneratedDay day = result.day(dayNumber);
      expect(day.isRest, isTrue);
      expect(day.taskIds, isEmpty);
      expect(day.startClock, isNull);
      expect(day.breaks, isEmpty);
    }
  });

  test(
    'a practical weekday that lands on a rest day moves to the next free day',
    () {
      final ScheduleGeneration result = ScheduleEngine.generate(
        days: _days(),
        tasks: _tasks(),
        practicalWeekdays: <int>[DateTime.wednesday, DateTime.friday],
      );

      // Wednesday is the rest day in both weeks: the practical day is
      // forwarded to Thursday, exactly like the original plan's Friday-rest
      // weeks.
      expect(result.day(3).isRest, isTrue);
      expect(result.day(4).isPractical, isTrue);
      expect(result.day(10).isRest, isTrue);
      expect(result.day(11).isPractical, isTrue);
      expect(result.day(5).isPractical, isTrue);
      expect(result.day(12).isPractical, isTrue);
    },
  );

  test('times are regenerated without overlaps and with real breaks', () {
    final ScheduleGeneration result = ScheduleEngine.generate(
      days: _days(),
      tasks: _tasks(),
      practicalWeekdays: <int>[DateTime.monday, DateTime.friday],
    );

    for (final GeneratedDay day in result.days) {
      if (day.isRest) continue;
      expect(day.startClock, day.isPractical ? '16:00' : '08:00');
      expect(day.endClock, isNotNull);
      expect(day.taskIds, isNotEmpty);

      int previousEnd = _minutes(day.startClock!);
      for (final String taskId in day.taskIds) {
        final GeneratedTaskPlacement placement = result.placements[taskId]!;
        final int start = _minutes(placement.startClock);
        final int end = _minutes(placement.endClock);
        expect(start, greaterThanOrEqualTo(previousEnd));
        expect(end, greaterThan(start));
        previousEnd = end;

        // Step spans are contiguous and stay inside the task.
        int stepCursor = start;
        for (final ScheduleSpan span in placement.stepSpans.values) {
          expect(_minutes(span.startClock), stepCursor);
          stepCursor = _minutes(span.endClock);
        }
        expect(stepCursor, end);
      }
      expect(_minutes(day.endClock!), greaterThanOrEqualTo(previousEnd));

      for (final ScheduleBreak item in day.breaks) {
        expect(item.minutes, greaterThan(0));
        expect(
          _minutes(item.endClock),
          _minutes(item.startClock) + item.minutes,
        );
      }
    }
  });

  test('normal days get a free block, practical days do not', () {
    final ScheduleGeneration result = ScheduleEngine.generate(
      days: _days(),
      tasks: _tasks(),
      practicalWeekdays: <int>[DateTime.monday, DateTime.friday],
    );

    for (final GeneratedDay day in result.days) {
      if (day.isRest || !day.isPractical) continue;
      expect(
        day.breaks.any((ScheduleBreak item) => item.kind == 'free_time'),
        isFalse,
        reason: 'practical day ${day.dayNumber} must not take a free block',
      );
    }
    expect(
      result.days.any(
        (GeneratedDay day) =>
            !day.isRest &&
            !day.isPractical &&
            day.breaks.any((ScheduleBreak item) => item.kind == 'free_time'),
      ),
      isTrue,
    );
  });

  test('invalid input is rejected instead of producing a half schedule', () {
    expect(
      () => ScheduleEngine.generate(
        days: _days(),
        tasks: _tasks(),
        practicalWeekdays: <int>[],
      ),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => ScheduleEngine.generate(
        days: _days(),
        tasks: _tasks(),
        practicalWeekdays: <int>[
          DateTime.monday,
          DateTime.tuesday,
          DateTime.thursday,
          DateTime.friday,
        ],
      ),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => ScheduleEngine.generate(
        days: <ScheduleDayInput>[..._days(), _days().first],
        tasks: _tasks(),
        practicalWeekdays: PracticalWeekdays.original,
      ),
      throwsA(isA<ScheduleException>()),
    );

    expect(
      () => ScheduleEngine.generate(
        days: _days(),
        tasks: <ScheduleTaskInput>[
          ..._tasks(),
          ScheduleTaskInput(
            id: 't1',
            sourceDayNumber: 1,
            sourceOrder: 13,
            minutes: 10,
            steps: const <ScheduleStepInput>[],
          ),
        ],
        practicalWeekdays: PracticalWeekdays.original,
      ),
      throwsA(isA<ScheduleException>()),
    );
  });

  test('a task that references a missing day is rejected', () {
    expect(
      () => ScheduleEngine.generate(
        days: _days(),
        tasks: <ScheduleTaskInput>[
          ScheduleTaskInput(
            id: 'orphan',
            sourceDayNumber: 99,
            sourceOrder: 1,
            minutes: 30,
            steps: const <ScheduleStepInput>[],
          ),
        ],
        practicalWeekdays: PracticalWeekdays.original,
      ),
      throwsA(isA<ScheduleException>()),
    );
  });
}
