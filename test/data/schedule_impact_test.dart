import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/data/database/app_database.dart';
import 'package:khutati/data/import/plan_importer.dart';
import 'package:khutati/data/repositories/schedule_repository.dart';
import 'package:khutati/data/repositories/template_repository.dart';
import 'package:khutati/domain/plan/plan_calendar.dart';
import 'package:khutati/domain/plan/schedule_engine.dart';

/// The rescheduling screen never calls the engine directly: it asks the
/// repository for the *impact* of a whole draft, then commits it. These tests
/// pin the contract of those two calls — what the impact reports, what it
/// refuses, and that a save writes either every row or none.
void main() {
  late AppDatabase db;
  late ScheduleRepository schedule;
  late PlanCalendar calendar;

  setUp(() async {
    db = AppDatabase.memory();
    schedule = ScheduleRepository(db, TemplateRepository(db));
    calendar = PlanCalendar(startDate: DateTime(2026, 11, 19), totalDays: 68);
    await PlanImporter(db)
        .ensureImported(File('khutati_plan_data.json').readAsStringSync());
  });

  tearDown(() => db.close());

  /// A task that can legally move forward one day: the *last* task of a study
  /// day with a study day after it. Any other task has a successor that would
  /// be left behind, which the sequence rule rightly refuses.
  ScheduledTask? lastMovable(ScheduleSnapshot snapshot, {String? skip}) {
    for (final ScheduledDay day in snapshot.days) {
      if (day.isRest) continue;
      final List<ScheduledTask> tasks = snapshot.tasksForDay(day.dayNumber);
      final ScheduledDay? next = snapshot.day(day.dayNumber + 1);
      if (tasks.length < 2 || next == null || next.isRest) continue;
      final ScheduledTask candidate = tasks.last;
      if (candidate.task.id == skip) continue;
      return candidate;
    }
    return null;
  }

  Future<(ScheduleSnapshot, ScheduledTask)> movableForward() async {
    final ScheduleSnapshot snapshot = await schedule.load(calendar);
    final ScheduledTask? task = lastMovable(snapshot);
    if (task == null) throw StateError('the dataset has no movable task');
    return (snapshot, task);
  }

  Future<List<ScheduleOverrideRow>> overrides() =>
      db.select(db.scheduleOverrides).get();

  Future<List<SyncQueueRow>> outbox() => db.select(db.syncQueue).get();

  test('an empty draft is the saved schedule, with no changes', () async {
    final ScheduleImpact impact = await schedule.previewOverrides(
      calendar,
      const <String, ScheduleOverrideInput>{},
    );

    expect(impact.ok, isTrue);
    expect(impact.moves, isEmpty);
    expect(impact.days, isEmpty);
    expect(impact.hasChanges, isFalse);
    expect(impact.finishDayDelta, 0);
    expect(impact.schedule.tasks, hasLength(725));
  });

  test('one move reports the task, both days and the finish line', () async {
    final (ScheduleSnapshot before, ScheduledTask task) =
        await movableForward();
    final int toDay = task.dayNumber + 1;

    final ScheduleImpact impact = await schedule.previewOverrides(calendar, {
      task.task.id: ScheduleOverrideInput(dayNumber: toDay, position: 1),
    });

    expect(impact.ok, isTrue, reason: impact.error);
    expect(impact.moves, isNotEmpty);

    final TaskPlacementChange move = impact.moves.firstWhere(
      (TaskPlacementChange item) => item.task.task.id == task.task.id,
    );
    expect(move.fromDay, task.dayNumber);
    expect(move.toDay, toDay);
    expect(move.changedDay, isTrue);

    final ScheduledTask placed = impact.schedule.tasksById[task.task.id]!;
    expect(placed.dayNumber, toDay);
    expect(placed.order, 1);
    expect(placed.isManual, isTrue);

    final DayImpact left = impact.days.firstWhere(
      (DayImpact day) => day.dayNumber == task.dayNumber,
    );
    final DayImpact joined = impact.days.firstWhere(
      (DayImpact day) => day.dayNumber == toDay,
    );
    expect(left.deltaTasks, -1);
    expect(joined.deltaTasks, 1);
    expect(left.deltaMinutes, lessThan(0));
    expect(joined.deltaMinutes, greaterThan(0));

    // The plan can only finish on the same day or later, never earlier.
    expect(
      impact.finishDayAfter,
      greaterThanOrEqualTo(impact.finishDayBefore!),
    );
    expect(before.tasks, hasLength(impact.schedule.tasks.length));

    // A preview is pure: no rows, no outbox.
    expect(await overrides(), isEmpty);
    expect(await outbox(), isEmpty);
  });

  test('a rest day is refused and nothing is written', () async {
    final ScheduleSnapshot before = await schedule.load(calendar);
    final ScheduledDay rest = before.days.firstWhere(
      (ScheduledDay day) => day.isRest,
    );

    final ScheduleImpact impact = await schedule.previewOverrides(calendar, {
      before.orderedTasks.first.task.id: ScheduleOverrideInput(
        dayNumber: rest.dayNumber,
      ),
    });

    expect(impact.ok, isFalse);
    expect(impact.error, contains('rest day'));
    expect(
      impact.schedule.tasksById[before.orderedTasks.first.task.id]!.dayNumber,
      before.orderedTasks.first.dayNumber,
    );
    expect(await overrides(), isEmpty);
  });

  test('a move that inverts the curriculum is refused', () async {
    final ScheduleSnapshot before = await schedule.load(calendar);
    final ScheduledTask last = before.orderedTasks.last;

    final ScheduleImpact impact = await schedule.previewOverrides(calendar, {
      last.task.id: const ScheduleOverrideInput(dayNumber: 1, position: 1),
    });

    expect(impact.ok, isFalse);
    expect(impact.error, contains('sequence'));
    expect(impact.schedule.tasksById[last.task.id]!.dayNumber, last.dayNumber);
    expect(await overrides(), isEmpty);
  });

  test('a same-day reorder is allowed and keeps every task', () async {
    final ScheduleSnapshot before = await schedule.load(calendar);
    final ScheduledDay day = before.days.firstWhere(
      (ScheduledDay item) =>
          !item.isRest && before.tasksForDay(item.dayNumber).length >= 3,
    );
    final List<ScheduledTask> tasks = before.tasksForDay(day.dayNumber);
    final ScheduledTask first = tasks.first;
    final ScheduledTask third = tasks[2];

    final ScheduleImpact impact = await schedule.previewOverrides(calendar, {
      first.task.id: ScheduleOverrideInput(
        dayNumber: day.dayNumber,
        position: 3,
      ),
      third.task.id: ScheduleOverrideInput(
        dayNumber: day.dayNumber,
        position: 1,
      ),
    });

    expect(impact.ok, isTrue, reason: impact.error);
    final List<ScheduledTask> after = impact.schedule.tasksForDay(
      day.dayNumber,
    );
    expect(after, hasLength(tasks.length));
    expect(after.first.task.id, third.task.id);
    expect(after[2].task.id, first.task.id);
    expect(
      after.map((ScheduledTask task) => task.task.id).toSet(),
      tasks.map((ScheduledTask task) => task.task.id).toSet(),
    );
    expect(impact.days, isEmpty, reason: 'no task changes day');
  });

  test('a save writes every row and survives a reload unchanged', () async {
    final ScheduleSnapshot before = await schedule.load(calendar);
    final ScheduledDay day = before.days.firstWhere(
      (ScheduledDay item) =>
          !item.isRest && before.tasksForDay(item.dayNumber).length >= 3,
    );
    final List<ScheduledTask> tasks = before.tasksForDay(day.dayNumber);
    final ScheduledTask first = tasks.first;
    final ScheduledTask third = tasks[2];

    final Map<String, ScheduleOverrideInput> draft =
        <String, ScheduleOverrideInput>{
          first.task.id: ScheduleOverrideInput(
            dayNumber: day.dayNumber,
            position: 3,
          ),
          third.task.id: ScheduleOverrideInput(
            dayNumber: day.dayNumber,
            position: 1,
          ),
        };
    final ScheduleImpact impact = await schedule.previewOverrides(
      calendar,
      draft,
    );
    await schedule.commitOverrides(calendar, draft);

    expect(await overrides(), hasLength(2));
    expect(
      (await outbox())
          .where(
            (SyncQueueRow row) =>
                row.entity == ScheduleRepository.overrideSyncEntity,
          )
          .length,
      2,
    );

    final ScheduleSnapshot reloaded = await schedule.load(calendar);
    final List<ScheduledTask> preview = impact.schedule.tasksForDay(
      day.dayNumber,
    );
    final List<ScheduledTask> actual = reloaded.tasksForDay(day.dayNumber);
    expect(
      actual.map((ScheduledTask task) => task.task.id),
      preview.map((ScheduledTask task) => task.task.id),
    );
    expect(
      actual.map((ScheduledTask task) => task.startClock),
      preview.map((ScheduledTask task) => task.startClock),
    );
    expect(reloaded.tasksById[first.task.id]!.isManual, isTrue);
    expect(reloaded.tasksById[third.task.id]!.isManual, isTrue);
  });

  test('an invalid draft throws on save and writes nothing', () async {
    final ScheduleSnapshot before = await schedule.load(calendar);
    final ScheduledTask last = before.orderedTasks.last;

    await expectLater(
      schedule.commitOverrides(calendar, <String, ScheduleOverrideInput>{
        last.task.id: const ScheduleOverrideInput(dayNumber: 1, position: 1),
      }),
      throwsA(isA<ScheduleException>()),
    );
    expect(await overrides(), isEmpty);
    expect(await outbox(), isEmpty);
  });

  test('a saved placement still applies while the next draft is previewed', () async {
    final (ScheduleSnapshot before, ScheduledTask first) =
        await movableForward();
    await schedule.commitOverrides(calendar, <String, ScheduleOverrideInput>{
      first.task.id: ScheduleOverrideInput(
        dayNumber: first.dayNumber + 1,
        position: 1,
      ),
    });

    // Pick a second task that can still move, ignoring the one just saved. It
    // must be the last task of its day, or its successor would be left behind.
    final ScheduleSnapshot reloaded = await schedule.load(calendar);
    final ScheduledTask? candidate = lastMovable(reloaded, skip: first.task.id);
    expect(candidate, isNotNull, reason: 'no second movable task');
    final ScheduledTask second = candidate!;

    final ScheduleImpact impact = await schedule.previewOverrides(calendar, {
      second.task.id: ScheduleOverrideInput(
        dayNumber: second.dayNumber + 1,
        position: 1,
      ),
    });

    expect(impact.ok, isTrue, reason: impact.error);
    // The earlier save is part of the preview, not something it reverts.
    expect(
      impact.schedule.tasksById[first.task.id]!.dayNumber,
      first.dayNumber + 1,
    );
    expect(
      impact.moves.where(
        (TaskPlacementChange move) => move.task.task.id == first.task.id,
      ),
      isEmpty,
    );
    expect(
      impact.schedule.tasksById[second.task.id]!.dayNumber,
      second.dayNumber + 1,
    );
    expect(before.tasks, hasLength(reloaded.tasks.length));
  });
}
