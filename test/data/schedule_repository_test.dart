import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/data/database/app_database.dart';
import 'package:khutati/data/import/plan_importer.dart';
import 'package:khutati/data/repositories/schedule_repository.dart';
import 'package:khutati/data/repositories/template_repository.dart';
import 'package:khutati/data/repositories/user_state_repository.dart';
import 'package:khutati/domain/plan/plan_calendar.dart';
import 'package:khutati/domain/plan/practical_weekdays.dart';
import 'package:khutati/domain/plan/step_progress.dart';

void main() {
  late AppDatabase db;
  late TemplateRepository template;
  late UserStateRepository userState;
  late ScheduleRepository schedule;
  late PlanCalendar calendar;

  setUp(() async {
    db = AppDatabase.memory();
    template = TemplateRepository(db);
    userState = UserStateRepository(db);
    schedule = ScheduleRepository(db, template);
    calendar = PlanCalendar(startDate: DateTime(2026, 11, 19), totalDays: 68);
    final String json = File('khutati_plan_data.json').readAsStringSync();
    await PlanImporter(db).ensureImported(json);
  });

  tearDown(() => db.close());

  Future<Map<String, int>> templateTaskDays() async {
    final List<DayRow> days = await db.select(db.days).get();
    final Map<String, int> dayNumberById = <String, int>{
      for (final DayRow day in days) day.id: day.dayNumber,
    };
    final List<TaskRow> tasks = await db.select(db.tasks).get();
    return <String, int>{
      for (final TaskRow task in tasks)
        task.id: dayNumberById[task.dayId] ?? -1,
    };
  }

  Future<Map<int, int>> weekByDay() async {
    final List<DayRow> days = await db.select(db.days).get();
    return <int, int>{for (final DayRow day in days) day.dayNumber: day.week};
  }

  test('the default snapshot mirrors the bundled template', () async {
    final ScheduleSnapshot snapshot = await schedule.load(calendar);

    expect(snapshot.isCustom, isFalse);
    expect(snapshot.days, hasLength(68));
    expect(snapshot.tasks, hasLength(725));
    expect(snapshot.practicalWeekdays, PracticalWeekdays.original);
    expect(snapshot.day(15)!.isRest, isTrue);
    expect(snapshot.tasksForDay(15), isEmpty);

    final DayBundle dayOne = (await template.dayBundle(1))!;
    expect(
      snapshot.tasksForDay(1).map((ScheduledTask task) => task.task.id),
      dayOne.tasks.map((TaskWithSteps item) => item.task.id),
    );
    expect(
      snapshot.tasksForDay(1).first.startClock,
      dayOne.tasks.first.task.suggestedStart,
    );
  });

  test('a custom selection keeps every task and every step id', () async {
    final Map<String, int> before = await templateTaskDays();
    final List<StepRow> templateSteps = await db.select(db.steps).get();
    final Map<String, Set<String>> stepsBefore = <String, Set<String>>{};
    for (final StepRow step in templateSteps) {
      stepsBefore.putIfAbsent(step.taskId, () => <String>{}).add(step.id);
    }

    await schedule.save(calendar, <int>[DateTime.tuesday, DateTime.thursday]);
    final ScheduleSnapshot snapshot = await schedule.load(calendar);

    expect(snapshot.isCustom, isTrue);
    expect(snapshot.tasks, hasLength(before.length));

    final Map<String, int> after = <String, int>{
      for (final ScheduledTask task in snapshot.tasks)
        task.task.id: task.dayNumber,
    };
    expect(after.keys.toSet(), before.keys.toSet());
    for (final ScheduledTask task in snapshot.tasks) {
      expect(
        task.steps.map((StepRow step) => step.id).toSet(),
        stepsBefore[task.task.id],
        reason: '${task.task.id} lost a step',
      );
    }

    // No task leaves its week.
    final Map<int, int> weeks = await weekByDay();
    for (final String taskId in before.keys) {
      expect(
        weeks[after[taskId]],
        weeks[before[taskId]],
        reason: '$taskId changed week',
      );
    }

    // Rest days stay empty and no study day is left without work.
    for (final ScheduledDay day in snapshot.days) {
      if (day.isRest) {
        expect(day.taskIds, isEmpty);
      } else {
        expect(day.taskIds, isNotEmpty, reason: 'day ${day.dayNumber}');
      }
    }
  });

  test('generated times are consistent with the day type', () async {
    await schedule.save(calendar, <int>[DateTime.tuesday, DateTime.thursday]);
    final ScheduleSnapshot snapshot = await schedule.load(calendar);

    for (final ScheduledDay day in snapshot.days) {
      if (day.isRest) continue;
      expect(day.startClock, day.isPractical ? '16:00' : '08:00');
      for (final ScheduledTask task in snapshot.tasksForDay(day.dayNumber)) {
        expect(task.startClock, isNotNull);
        expect(task.endClock, isNotNull);
        expect(task.stepSpans.length, task.steps.length);
      }
    }
  });

  test('completion and partial progress survive a schedule change', () async {
    // Real ids from the bundled dataset: an item is a task, and its attendance
    // and study intervals are the steps.
    final TaskRow task = (await db.select(db.tasks).get()).first;
    final List<StepRow> taskSteps = await (db.select(
      db.steps,
    )..where((t) => t.taskId.equals(task.id))).get();
    final String taskId = task.id;
    final String stepId = taskSteps.first.id;
    await userState.setStepCompleted(stepId, StepProgress.partialUp);
    await userState.setTaskStatus(taskId, 'in_progress');

    await schedule.save(calendar, <int>[DateTime.tuesday, DateTime.thursday]);
    final ScheduleSnapshot snapshot = await schedule.load(calendar);

    expect(snapshot.tasksById.containsKey(taskId), isTrue);
    expect(
      snapshot.tasksById[taskId]!.steps.map((StepRow step) => step.id),
      contains(stepId),
    );
    expect(await userState.stepProgress(stepId), StepProgress.partialUp);
  });

  test('preview reports movement without writing the preference', () async {
    final SchedulePreview preview = await schedule.preview(calendar, <int>[
      DateTime.tuesday,
      DateTime.thursday,
    ]);

    expect(preview.movedTasks, greaterThan(0));
    expect(preview.changedDays, greaterThan(0));
    expect(preview.schedule.isCustom, isTrue);
    expect(await schedule.practicalWeekdays(), isNull);
    expect((await schedule.load(calendar)).isCustom, isFalse);
  });

  test('saving enqueues exactly one sync row', () async {
    await schedule.save(calendar, <int>[DateTime.tuesday, DateTime.thursday]);
    await schedule.save(calendar, <int>[DateTime.sunday, DateTime.wednesday]);

    final List<SyncQueueRow> rows = await db.select(db.syncQueue).get();
    final SyncQueueRow row = rows.singleWhere(
      (SyncQueueRow item) => item.entity == ScheduleRepository.syncEntity,
    );
    expect(row.entityId, ScheduleRepository.syncEntityId);
    expect(row.payload, contains('"practical_weekdays"'));
  });

  test('reset restores the original day-by-day schedule', () async {
    final Map<String, int> before = await templateTaskDays();
    await schedule.save(calendar, <int>[DateTime.tuesday, DateTime.thursday]);
    await schedule.reset(calendar);

    expect(await schedule.practicalWeekdays(), isNull);
    final ScheduleSnapshot snapshot = await schedule.load(calendar);
    expect(snapshot.isCustom, isFalse);

    final Map<String, int> after = <String, int>{
      for (final ScheduledTask task in snapshot.tasks)
        task.task.id: task.dayNumber,
    };
    expect(after, before);
  });

  test('a remote preference applies only when it is newer', () async {
    final DateTime base = DateTime.utc(2026, 11, 19, 10);
    await schedule.applyRemote(<int>[
      DateTime.tuesday,
      DateTime.thursday,
    ], base);
    expect(await schedule.practicalWeekdays(), <int>[2, 4]);

    await schedule.applyRemote(<int>[
      DateTime.sunday,
      DateTime.wednesday,
    ], base.subtract(const Duration(minutes: 5)));
    expect(await schedule.practicalWeekdays(), <int>[2, 4]);

    await schedule.applyRemote(<int>[
      DateTime.sunday,
      DateTime.wednesday,
    ], base.add(const Duration(minutes: 5)));
    expect(await schedule.practicalWeekdays(), <int>[3, 7]);
  });

  test('an invalid selection never reaches persistence', () async {
    await expectLater(
      schedule.save(calendar, <int>[
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
      ]),
      throwsA(isA<FormatException>()),
    );
    expect(await schedule.practicalWeekdays(), isNull);
    expect(await db.select(db.syncQueue).get(), isEmpty);
  });

  group('manual scheduling', () {
    Future<ScheduleSnapshot> snapshot() => schedule.load(calendar);

    /// A task with a later task on the next day, so it can move forward one
    /// day without crossing its successor.
    Future<ScheduledTask> movable(ScheduleSnapshot value) async {
      final List<ScheduledTask> ordered = value.orderedTasks;
      for (int i = 0; i + 1 < ordered.length; i++) {
        final ScheduledTask task = ordered[i];
        final ScheduledTask next = ordered[i + 1];
        if (!value.day(task.dayNumber + 1)!.isRest &&
            next.dayNumber > task.dayNumber) {
          return task;
        }
      }
      throw StateError('no movable task in the dataset');
    }

    test('a preview writes nothing', () async {
      final ScheduleSnapshot before = await snapshot();
      final ScheduledTask task = await movable(before);
      final TaskMovePreview preview = await schedule.previewMove(
        calendar,
        taskId: task.task.id,
        dayNumber: task.dayNumber + 1,
        startClock: null,
      );
      expect(preview.ok, isTrue);
      expect(preview.toDay, task.dayNumber + 1);
      expect(await db.select(db.scheduleOverrides).get(), isEmpty);
      expect(await db.select(db.syncQueue).get(), isEmpty);
    });

    test(
      'committing a move persists one override and one outbox row',
      () async {
        final ScheduleSnapshot before = await snapshot();
        final ScheduledTask task = await movable(before);
        final TaskMovePreview result = await schedule.commitMove(
          calendar,
          taskId: task.task.id,
          dayNumber: task.dayNumber + 1,
        );
        expect(result.ok, isTrue);

        final List<ScheduleOverrideRow> rows = await db
            .select(db.scheduleOverrides)
            .get();
        expect(rows, hasLength(1));
        expect(rows.single.taskId, task.task.id);
        expect(rows.single.dayNumber, task.dayNumber + 1);

        final List<SyncQueueRow> queue = await db.select(db.syncQueue).get();
        expect(
          queue.where(
            (SyncQueueRow row) =>
                row.entity == ScheduleRepository.overrideSyncEntity,
          ),
          hasLength(1),
        );

        final ScheduleSnapshot after = await snapshot();
        expect(after.tasksById[task.task.id]!.dayNumber, task.dayNumber + 1);
        expect(after.tasksById[task.task.id]!.isManual, isTrue);
        expect(after.tasks, hasLength(before.tasks.length));
        expect(after.overrides, hasLength(1));
      },
    );

    test('a rest day is refused and nothing is written', () async {
      final ScheduleSnapshot before = await snapshot();
      final ScheduledTask task = await movable(before);
      final int restDay = before.days
          .firstWhere((ScheduledDay day) => day.isRest)
          .dayNumber;
      final TaskMovePreview result = await schedule.previewMove(
        calendar,
        taskId: task.task.id,
        dayNumber: restDay,
      );
      expect(result.ok, isFalse);
      expect(result.issue, TaskMoveIssue.restDay);
      expect(await db.select(db.scheduleOverrides).get(), isEmpty);
    });

    test('moving later material to an earlier day is refused', () async {
      final ScheduleSnapshot before = await snapshot();
      final ScheduledTask late = before.orderedTasks.last;
      final TaskMovePreview result = await schedule.previewMove(
        calendar,
        taskId: late.task.id,
        dayNumber: before.orderedTasks.first.dayNumber,
      );
      expect(result.ok, isFalse);
      expect(result.issue, TaskMoveIssue.dependencyBefore);
      expect(result.blocking, isNotNull);
    });

    test('a pinned start survives a reload and is honoured', () async {
      final ScheduleSnapshot before = await snapshot();
      final ScheduledTask task = await movable(before);
      final List<ScheduledTask> dayTasks = before.tasksForDay(task.dayNumber);
      final int slot = dayTasks.length;
      // Pin after the day's current end so the start cannot overlap the task
      // that will precede it.
      final List<String> end = (before.day(task.dayNumber)!.endClock ?? '17:00')
          .split(':');
      final int endMinutes = int.parse(end[0]) * 60 + int.parse(end[1]);
      final String clock =
          '${(endMinutes + 30) ~/ 60}:'
          '${((endMinutes + 30) % 60).toString().padLeft(2, '0')}';
      final TaskMovePreview result = await schedule.commitMove(
        calendar,
        taskId: task.task.id,
        dayNumber: task.dayNumber,
        position: slot,
        startClock: clock,
      );
      expect(result.ok, isTrue, reason: 'issue ${result.issue}');

      final ScheduleSnapshot after = await snapshot();
      expect(after.tasksById[task.task.id]!.startClock, clock);
      expect(after.overrides[task.task.id]!.startClock, clock);
    });

    test('an overlapping pinned start is refused', () async {
      final ScheduleSnapshot before = await snapshot();
      final List<ScheduledTask> day = before.tasksForDay(2);
      expect(day.length, greaterThan(1));
      final TaskMovePreview result = await schedule.previewMove(
        calendar,
        taskId: day[1].task.id,
        dayNumber: 2,
        position: 2,
        startClock: day.first.startClock,
      );
      expect(result.ok, isFalse);
      expect(result.issue, TaskMoveIssue.overlap);
      expect(result.blocking?.task.id, day.first.task.id);
    });

    test('clearing one override restores automatic scheduling', () async {
      final ScheduleSnapshot before = await snapshot();
      final ScheduledTask task = await movable(before);
      await schedule.commitMove(
        calendar,
        taskId: task.task.id,
        dayNumber: task.dayNumber + 1,
      );
      await schedule.clearOverride(task.task.id);

      expect(await db.select(db.scheduleOverrides).get(), isEmpty);
      final ScheduleSnapshot after = await snapshot();
      expect(after.tasksById[task.task.id]!.dayNumber, task.dayNumber);
      expect(after.tasksById[task.task.id]!.isManual, isFalse);
    });

    test('clearing every override returns to the template schedule', () async {
      final ScheduleSnapshot before = await snapshot();
      final ScheduledTask task = await movable(before);
      await schedule.commitMove(
        calendar,
        taskId: task.task.id,
        dayNumber: task.dayNumber + 1,
      );
      await schedule.clearAllOverrides();

      final ScheduleSnapshot after = await snapshot();
      expect(after.overrides, isEmpty);
      expect(after.tasksById[task.task.id]!.dayNumber, task.dayNumber);
      expect(after.tasksById[task.task.id]!.startClock, task.startClock);
    });

    test('a manual move preserves completion and step progress', () async {
      final ScheduleSnapshot before = await snapshot();
      final ScheduledTask task = await movable(before);
      final String stepId = task.stepsInOrder.first.id;
      await userState.setStepCompleted(stepId, StepProgress.partialUp);

      await schedule.commitMove(
        calendar,
        taskId: task.task.id,
        dayNumber: task.dayNumber + 1,
      );

      expect(await userState.stepProgress(stepId), StepProgress.partialUp);
      expect(
        (await db.select(db.userStepStates).get()).where(
          (UserStepStateRow row) => row.stepId == stepId,
        ),
        hasLength(1),
      );
    });

    test(
      'an override that cannot survive a weekday change is reported',
      () async {
        final ScheduleSnapshot before = await snapshot();
        final ScheduledTask task = await movable(before);
        await schedule.commitMove(
          calendar,
          taskId: task.task.id,
          dayNumber: task.dayNumber + 1,
          position: 1,
          startClock: '22:00',
        );

        final SchedulePreview preview = await schedule.preview(calendar, <int>[
          DateTime.sunday,
        ]);
        // Either the override still fits, or it is reported instead of failing
        // the whole preview; both are acceptable, silently dropping it is not.
        expect(
          preview.droppedOverrides.isEmpty ||
              preview.droppedOverrides.contains(task.task.id),
          isTrue,
        );
        expect(preview.schedule.tasks, hasLength(before.tasks.length));

        await schedule.save(calendar, <int>[DateTime.sunday]);
        final ScheduleSnapshot after = await snapshot();
        for (final String dropped in preview.droppedOverrides) {
          expect(after.overrides.containsKey(dropped), isFalse);
        }
        expect(after.tasks, hasLength(before.tasks.length));
      },
    );
  });
}
