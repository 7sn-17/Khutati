import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/domain/plan/practical_weekdays.dart';
import 'package:khutati/domain/plan/schedule_engine.dart';

/// Manual placements and the one-to-three practical-day rule.
///
/// The plan is two Monday-first weeks with Wednesday as the rest day and three
/// one-hour tasks on each study day, so a move always has a visible neighbour.
void main() {
  List<ScheduleDayInput> days() {
    final List<ScheduleDayInput> out = <ScheduleDayInput>[];
    final DateTime start = DateTime(2026, 11, 16); // Monday
    for (int i = 0; i < 14; i++) {
      final DateTime date = start.add(Duration(days: i));
      out.add(
        ScheduleDayInput(
          dayNumber: i + 1,
          week: i < 7 ? 1 : 2,
          date: date,
          isRest: date.weekday == DateTime.wednesday,
        ),
      );
    }
    return out;
  }

  List<ScheduleTaskInput> tasks() {
    final List<ScheduleTaskInput> out = <ScheduleTaskInput>[];
    for (int week = 0; week < 2; week++) {
      for (int i = 0; i < 12; i++) {
        final String id = 't${week + 1}-${i + 1}';
        out.add(
          ScheduleTaskInput(
            id: id,
            sourceDayNumber: week * 7 + 1 + (i ~/ 3),
            sourceOrder: i,
            minutes: 60,
            steps: <ScheduleStepInput>[
              ScheduleStepInput(id: '$id-a', minutes: 30, order: 1),
              ScheduleStepInput(id: '$id-b', minutes: 30, order: 2),
            ],
          ),
        );
      }
    }
    return out;
  }

  ScheduleGeneration generate({
    List<int>? practical,
    Map<String, ScheduleOverrideInput> overrides =
        const <String, ScheduleOverrideInput>{},
  }) {
    return ScheduleEngine.generate(
      days: days(),
      tasks: tasks(),
      practicalWeekdays: practical ?? PracticalWeekdays.original,
      overrides: overrides,
    );
  }

  List<String> order(ScheduleGeneration generation) {
    return <String>[
      for (final GeneratedDay day in generation.days)
        if (!day.isRest) ...day.taskIds,
    ];
  }

  test('one, two and three practical days all produce a full plan', () {
    for (final List<int> selection in <List<int>>[
      <int>[DateTime.tuesday],
      <int>[DateTime.monday, DateTime.friday],
      <int>[DateTime.monday, DateTime.wednesday, DateTime.friday],
    ]) {
      final ScheduleGeneration generation = generate(practical: selection);
      expect(order(generation), hasLength(24));
      expect(
        generation.days
            .where((GeneratedDay day) => day.isPractical && !day.isRest)
            .length,
        selection.length * 2,
        reason: 'one practical day per week, resolved per week',
      );
      expect(
        generation.days
            .where((GeneratedDay day) => day.isRest)
            .every((GeneratedDay day) => day.taskIds.isEmpty),
        isTrue,
      );
    }
  });

  test('a fourth practical day is rejected', () {
    expect(
      () => generate(
        practical: <int>[
          DateTime.monday,
          DateTime.tuesday,
          DateTime.thursday,
          DateTime.friday,
        ],
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => PracticalWeekdays.validate(<int>[]),
      throwsA(isA<FormatException>()),
    );
  });

  test('generation is deterministic', () {
    final ScheduleGeneration a = generate();
    final ScheduleGeneration b = generate();
    expect(order(a), order(b));
    for (final String id in a.placements.keys) {
      expect(a.placements[id]!.startClock, b.placements[id]!.startClock);
    }
  });

  test('a manual position changes the day order only', () {
    final ScheduleGeneration base = generate();
    final GeneratedDay dayTwo = base.days.firstWhere(
      (GeneratedDay day) => day.dayNumber == 2,
    );
    final String moved = dayTwo.taskIds.first;

    final ScheduleGeneration manual = generate(
      overrides: <String, ScheduleOverrideInput>{
        moved: ScheduleOverrideInput(
          dayNumber: 2,
          position: dayTwo.taskIds.length,
        ),
      },
    );
    final GeneratedDay after = manual.days.firstWhere(
      (GeneratedDay day) => day.dayNumber == 2,
    );
    expect(after.taskIds.last, moved);
    expect(after.taskIds.length, dayTwo.taskIds.length);
    expect(manual.placements[moved]!.isManual, isTrue);
    expect(
      manual.placements[moved]!.startClock,
      isNot(base.placements[moved]!.startClock),
    );
    // Every other day is untouched.
    for (final GeneratedDay day in manual.days) {
      if (day.dayNumber == 2 || day.isRest) continue;
      expect(day.taskIds, base.day(day.dayNumber).taskIds);
    }
  });

  test('a pinned start is honoured and the rest of the day follows it', () {
    final ScheduleGeneration base = generate();
    final String moved = base.days
        .firstWhere((GeneratedDay day) => day.dayNumber == 2)
        .taskIds
        .first;
    final ScheduleGeneration manual = generate(
      overrides: <String, ScheduleOverrideInput>{
        moved: const ScheduleOverrideInput(
          dayNumber: 2,
          position: 1,
          startClock: '11:30',
        ),
      },
    );
    final GeneratedTaskPlacement placement = manual.placements[moved]!;
    expect(placement.startClock, '11:30');
    expect(placement.endClock, '12:30');
    final GeneratedDay day = manual.day(2);
    expect(day.startClock, '11:30');
    // The remaining tasks follow the pinned block instead of the 08:00 start.
    expect(day.endClock!.compareTo('12:30'), greaterThan(0));
  });

  test('moving later material to an earlier day is rejected', () {
    final ScheduleGeneration base = generate();
    final String late = base.day(5).taskIds.last;
    expect(
      () => generate(
        overrides: <String, ScheduleOverrideInput>{
          late: const ScheduleOverrideInput(dayNumber: 1, position: 1),
        },
      ),
      throwsA(isA<ScheduleException>()),
    );
  });

  test('a rest day can never receive a task', () {
    expect(
      () => generate(
        overrides: <String, ScheduleOverrideInput>{
          't1-1': const ScheduleOverrideInput(dayNumber: 3),
        },
      ),
      throwsA(isA<ScheduleException>()),
    );
  });

  test('a pinned start that overlaps the previous task is rejected', () {
    final ScheduleGeneration base = generate();
    final GeneratedDay dayTwo = base.day(2);
    final String second = dayTwo.taskIds[1];
    final String firstStart = base.placements[dayTwo.taskIds.first]!.startClock;
    expect(
      () => generate(
        overrides: <String, ScheduleOverrideInput>{
          second: ScheduleOverrideInput(
            dayNumber: 2,
            position: 2,
            startClock: firstStart,
          ),
        },
      ),
      throwsA(isA<ScheduleException>()),
    );
  });

  test('a pinned start that runs past midnight is rejected', () {
    expect(
      () => generate(
        overrides: <String, ScheduleOverrideInput>{
          't1-1': const ScheduleOverrideInput(
            dayNumber: 2,
            position: 1,
            startClock: '23:45',
          ),
        },
      ),
      throwsA(isA<ScheduleException>()),
    );
  });

  test('an override for an unknown task is rejected', () {
    expect(
      () => generate(
        overrides: <String, ScheduleOverrideInput>{
          'missing': const ScheduleOverrideInput(dayNumber: 2),
        },
      ),
      throwsA(isA<ScheduleException>()),
    );
  });
}
