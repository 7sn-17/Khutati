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
    final String stepId = 'd001-chem-01-01';
    final String taskId = 'd001-chem-01';
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
      schedule.save(calendar, <int>[DateTime.monday]),
      throwsA(isA<FormatException>()),
    );
    expect(await schedule.practicalWeekdays(), isNull);
    expect(await db.select(db.syncQueue).get(), isEmpty);
  });
}
