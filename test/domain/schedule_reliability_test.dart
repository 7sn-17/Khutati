import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/domain/plan/schedule_engine.dart';

/// Invariants that must hold for *every* practical-day combination.
///
/// The engine is the only thing standing between the user and a broken plan, so
/// these tests do not sample a few configurations: they sweep all 63 valid
/// selections (1, 2 and 3 weekdays out of 7) over a four-week plan with mixed
/// task lengths, including a three-hour block that cannot be split.
List<ScheduleDayInput> _days() {
  return <ScheduleDayInput>[
    for (int week = 1; week <= 4; week++)
      for (int offset = 0; offset < 7; offset++)
        ScheduleDayInput(
          dayNumber: (week - 1) * 7 + offset + 1,
          week: week,
          date: DateTime(2026, 11, 16 + (week - 1) * 7 + offset),
          // Wednesday is the plan's rest day.
          isRest: offset == 2,
        ),
  ];
}

/// Twenty tasks per week, spread over the six study days, with a mix of short,
/// medium and one long indivisible block.
List<ScheduleTaskInput> _tasks() {
  const List<int> sourceOffsets = <int>[
    0,
    0,
    0,
    1,
    1,
    1,
    3,
    3,
    3,
    3,
    4,
    4,
    4,
    4,
    5,
    5,
    5,
    6,
    6,
    6,
  ];
  const List<int> minutes = <int>[45, 60, 30, 90, 45, 180, 60, 30, 45, 60];
  final List<ScheduleTaskInput> tasks = <ScheduleTaskInput>[];
  for (int week = 1; week <= 4; week++) {
    for (int index = 0; index < sourceOffsets.length; index++) {
      final int id = (week - 1) * sourceOffsets.length + index + 1;
      final int total = minutes[index % minutes.length];
      tasks.add(
        ScheduleTaskInput(
          id: 't$id',
          sourceDayNumber: (week - 1) * 7 + sourceOffsets[index] + 1,
          sourceOrder: index + 1,
          minutes: total,
          steps: <ScheduleStepInput>[
            ScheduleStepInput(
              id: 't$id-s1',
              minutes: (total / 2).ceil(),
              order: 1,
            ),
            ScheduleStepInput(
              id: 't$id-s2',
              minutes: total - (total / 2).ceil(),
              order: 2,
            ),
          ],
        ),
      );
    }
  }
  return tasks;
}

int _minutesOf(String clock) {
  final List<String> parts = clock.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

Iterable<List<int>> _combinations() sync* {
  const List<int> weekdays = <int>[
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  ];
  for (int a = 0; a < weekdays.length; a++) {
    yield <int>[weekdays[a]];
    for (int b = a + 1; b < weekdays.length; b++) {
      yield <int>[weekdays[a], weekdays[b]];
      for (int c = b + 1; c < weekdays.length; c++) {
        yield <int>[weekdays[a], weekdays[b], weekdays[c]];
      }
    }
  }
}

void _expectSound(
  ScheduleGeneration result,
  List<ScheduleTaskInput> tasks,
  List<int> selection,
) {
  final String label = 'selection $selection';

  // 1. Every task is placed exactly once, and nothing else is placed.
  expect(result.placements, hasLength(tasks.length), reason: label);
  final List<String> placed = <String>[
    for (final GeneratedDay day in result.days) ...day.taskIds,
  ];
  expect(placed.toSet(), <String>{
    for (final ScheduleTaskInput t in tasks) t.id,
  }, reason: label);
  expect(placed, hasLength(tasks.length), reason: label);

  // 2. Rest days stay empty and clockless.
  for (final GeneratedDay day in result.days) {
    if (day.isRest) {
      expect(day.taskIds, isEmpty, reason: '$label rest day ${day.dayNumber}');
      expect(day.startClock, isNull, reason: label);
      expect(day.endClock, isNull, reason: label);
      continue;
    }

    // 3. Clocks exist and the day brackets its tasks without overlap.
    expect(day.startClock, isNotNull, reason: label);
    expect(day.endClock, isNotNull, reason: label);
    final int dayStart = _minutesOf(day.startClock!);
    final int dayEnd = _minutesOf(day.endClock!);
    expect(dayEnd >= dayStart, isTrue, reason: '$label day ${day.dayNumber}');

    int previousEnd = dayStart;
    int order = 0;
    for (final String taskId in day.taskIds) {
      final GeneratedTaskPlacement placement = result.placements[taskId]!;
      final int start = _minutesOf(placement.startClock);
      final int end = _minutesOf(placement.endClock);
      expect(placement.dayNumber, day.dayNumber, reason: label);
      expect(
        start >= previousEnd,
        isTrue,
        reason: '$label overlap in day ${day.dayNumber} at $taskId',
      );
      expect(end > start, isTrue, reason: '$label empty task $taskId');
      expect(
        placement.order,
        ++order,
        reason: '$label order in day ${day.dayNumber}',
      );
      previousEnd = end;
    }
    expect(
      previousEnd,
      dayEnd,
      reason: '$label day end mismatch ${day.dayNumber}',
    );
    if (day.taskIds.isNotEmpty) {
      expect(
        _minutesOf(result.placements[day.taskIds.first]!.startClock),
        dayStart,
        reason: '$label day start mismatch ${day.dayNumber}',
      );
    }
  }

  // 4. Tasks stay in their own week, in curriculum order.
  for (int week = 1; week <= 4; week++) {
    final List<String> weekOrder = <String>[
      for (final GeneratedDay day in result.days)
        if (day.week == week) ...day.taskIds,
    ];
    final int first = (week - 1) * 20 + 1;
    expect(weekOrder, <String>[
      for (int i = first; i < first + 20; i++) 't$i',
    ], reason: '$label week $week order');
  }

  // 5. Practical days never outnumber the selection after rest-day forwarding,
  //    and every week still has at least one.
  for (int week = 1; week <= 4; week++) {
    final int practical = result.days
        .where((GeneratedDay day) => day.week == week && day.isPractical)
        .length;
    expect(practical <= selection.length, isTrue, reason: '$label week $week');
    expect(practical >= 1, isTrue, reason: '$label week $week');
  }

  // 6. Day numbers are unique and ascending.
  final List<int> numbers = <int>[
    for (final GeneratedDay day in result.days) day.dayNumber,
  ];
  expect(numbers, List<int>.generate(28, (int i) => i + 1), reason: label);
}

void main() {
  test('all 63 weekday selections produce a sound schedule', () {
    final List<ScheduleDayInput> days = _days();
    final List<ScheduleTaskInput> tasks = _tasks();
    int checked = 0;

    for (final List<int> selection in _combinations()) {
      final ScheduleGeneration result = ScheduleEngine.generate(
        days: days,
        tasks: tasks,
        practicalWeekdays: selection,
      );
      _expectSound(result, tasks, selection);
      checked += 1;
    }

    expect(checked, 63);
  });

  test('generation is deterministic for every selection', () {
    final List<ScheduleDayInput> days = _days();
    final List<ScheduleTaskInput> tasks = _tasks();
    for (final List<int> selection in _combinations()) {
      final ScheduleGeneration a = ScheduleEngine.generate(
        days: days,
        tasks: tasks,
        practicalWeekdays: selection,
      );
      final ScheduleGeneration b = ScheduleEngine.generate(
        days: days,
        tasks: tasks,
        practicalWeekdays: selection,
      );
      for (final GeneratedDay day in a.days) {
        expect(day.taskIds, b.day(day.dayNumber).taskIds);
        expect(day.startClock, b.day(day.dayNumber).startClock);
        expect(day.endClock, b.day(day.dayNumber).endClock);
      }
    }
  });

  test('a pinned start is honoured exactly and never overlaps', () {
    final List<ScheduleDayInput> days = _days();
    final List<ScheduleTaskInput> tasks = _tasks();
    final ScheduleGeneration base = ScheduleEngine.generate(
      days: days,
      tasks: tasks,
      practicalWeekdays: <int>[DateTime.monday, DateTime.friday],
    );
    final GeneratedDay day = base.days.firstWhere(
      (GeneratedDay d) => d.dayNumber == 2,
    );
    expect(day.taskIds.length, greaterThan(1));

    final String moved = day.taskIds.last;
    final int duration = tasks
        .firstWhere((ScheduleTaskInput t) => t.id == moved)
        .minutes;
    final int pinnedStart = _minutesOf(base.placements[moved]!.startClock) + 30;
    // Only pin when the move still fits inside the day.
    expect(pinnedStart + duration < 24 * 60, isTrue);
    final String clock =
        '${(pinnedStart ~/ 60).toString().padLeft(2, '0')}:'
        '${(pinnedStart % 60).toString().padLeft(2, '0')}';

    final ScheduleGeneration pinned = ScheduleEngine.generate(
      days: days,
      tasks: tasks,
      practicalWeekdays: <int>[DateTime.monday, DateTime.friday],
      overrides: <String, ScheduleOverrideInput>{
        moved: ScheduleOverrideInput(dayNumber: 2, startClock: clock),
      },
    );
    final GeneratedTaskPlacement placement = pinned.placements[moved]!;
    expect(placement.startClock, clock);
    expect(placement.isManual, isTrue);
    _expectSound(pinned, tasks, <int>[DateTime.monday, DateTime.friday]);
  });

  test('two pinned starts in the wrong order are rejected', () {
    final List<ScheduleDayInput> days = _days();
    final List<ScheduleTaskInput> tasks = _tasks();
    final ScheduleGeneration base = ScheduleEngine.generate(
      days: days,
      tasks: tasks,
      practicalWeekdays: <int>[DateTime.monday, DateTime.friday],
    );
    final GeneratedDay day = base.days.firstWhere(
      (GeneratedDay d) => d.dayNumber == 2,
    );
    final String first = day.taskIds.first;
    final String second = day.taskIds[1];

    expect(
      () => ScheduleEngine.generate(
        days: days,
        tasks: tasks,
        practicalWeekdays: <int>[DateTime.monday, DateTime.friday],
        overrides: <String, ScheduleOverrideInput>{
          first: const ScheduleOverrideInput(dayNumber: 2, startClock: '09:00'),
          second: const ScheduleOverrideInput(
            dayNumber: 2,
            startClock: '08:30',
          ),
        },
      ),
      throwsA(isA<ScheduleException>()),
    );
  });

  test('a pinned start at the previous task end is allowed', () {
    final List<ScheduleDayInput> days = _days();
    final List<ScheduleTaskInput> tasks = _tasks();
    final ScheduleGeneration base = ScheduleEngine.generate(
      days: days,
      tasks: tasks,
      practicalWeekdays: <int>[DateTime.monday, DateTime.friday],
    );
    final GeneratedDay day = base.days.firstWhere(
      (GeneratedDay d) => d.dayNumber == 2,
    );
    final GeneratedTaskPlacement firstPlacement =
        base.placements[day.taskIds.first]!;
    final String second = day.taskIds[1];

    final ScheduleGeneration result = ScheduleEngine.generate(
      days: days,
      tasks: tasks,
      practicalWeekdays: <int>[DateTime.monday, DateTime.friday],
      overrides: <String, ScheduleOverrideInput>{
        second: ScheduleOverrideInput(
          dayNumber: 2,
          // Keep it second: an override without a position would append it to
          // the end of the day, where this start would overlap.
          position: 2,
          startClock: firstPlacement.endClock,
        ),
      },
    );
    expect(result.placements[second]!.startClock, firstPlacement.endClock);
    _expectSound(result, tasks, <int>[DateTime.monday, DateTime.friday]);
  });
}
