import 'dart:async';

import 'package:drift/drift.dart';

import '../../domain/plan/plan_calendar.dart';
import '../../domain/plan/practical_weekdays.dart';
import '../../domain/plan/schedule_engine.dart';
import '../database/app_database.dart';
import '../database/tables.dart';
import 'sync_queue_repository.dart';
import 'template_repository.dart';

/// One effective day after the practical-weekday setting is applied.
class ScheduledDay {
  const ScheduledDay({
    required this.dayNumber,
    required this.week,
    required this.type,
    required this.startClock,
    required this.endClock,
    required this.headerTitle,
    required this.note,
    required this.taskIds,
    required this.breaks,
  });

  final int dayNumber;
  final int week;

  /// `normal`, `practical` or `rest`.
  final String type;
  final String? startClock;
  final String? endClock;

  /// Original template heading. Custom days leave this `null` so the Plan tab
  /// derives a heading from the tasks that actually landed on the day.
  final String? headerTitle;
  final String? note;
  final List<String> taskIds;
  final List<ScheduleBreak> breaks;

  bool get isRest => type == 'rest';
  bool get isPractical => type == 'practical';
}

/// One task after placement. The [TaskRow] and [StepRow] identities are the
/// template's own ids, which is what keeps completion/partial progress intact.
class ScheduledTask {
  const ScheduledTask({
    required this.task,
    required this.steps,
    required this.dayNumber,
    required this.order,
    required this.startClock,
    required this.endClock,
    required this.stepSpans,
  });

  final TaskRow task;
  final List<StepRow> steps;
  final int dayNumber;
  final int order;
  final String? startClock;
  final String? endClock;
  final Map<String, ScheduleSpan> stepSpans;

  int get plannedMinutes =>
      steps.fold<int>(0, (int sum, StepRow step) => sum + step.minutes);

  List<StepRow> get stepsInOrder {
    final List<StepRow> ordered = List<StepRow>.of(steps)
      ..sort((StepRow a, StepRow b) => a.sortOrder.compareTo(b.sortOrder));
    return List<StepRow>.unmodifiable(ordered);
  }
}

/// Immutable snapshot of the effective schedule. Plan, Today, progress and
/// achievements all derive from this one object.
class ScheduleSnapshot {
  ScheduleSnapshot({
    required this.days,
    required this.tasks,
    required this.subjects,
    required this.isCustom,
    required this.practicalWeekdays,
  }) : daysByNumber = <int, ScheduledDay>{
         for (final ScheduledDay day in days) day.dayNumber: day,
       },
       tasksById = <String, ScheduledTask>{
         for (final ScheduledTask task in tasks) task.task.id: task,
       },
       _tasksByDay = _groupTasks(tasks);

  final List<ScheduledDay> days;
  final List<ScheduledTask> tasks;
  final List<SubjectRow> subjects;
  final Map<int, ScheduledDay> daysByNumber;
  final Map<String, ScheduledTask> tasksById;
  final Map<int, List<ScheduledTask>> _tasksByDay;
  final bool isCustom;
  final List<int> practicalWeekdays;

  ScheduledDay? day(int dayNumber) => daysByNumber[dayNumber];

  List<ScheduledTask> tasksForDay(int dayNumber) {
    return _tasksByDay[dayNumber] ?? const <ScheduledTask>[];
  }

  static Map<int, List<ScheduledTask>> _groupTasks(List<ScheduledTask> tasks) {
    final Map<int, List<ScheduledTask>> grouped = <int, List<ScheduledTask>>{};
    for (final ScheduledTask task in tasks) {
      grouped.putIfAbsent(task.dayNumber, () => <ScheduledTask>[]).add(task);
    }
    for (final List<ScheduledTask> dayTasks in grouped.values) {
      dayTasks.sort(
        (ScheduledTask a, ScheduledTask b) => a.order.compareTo(b.order),
      );
    }
    return grouped;
  }
}

class SchedulePreview {
  const SchedulePreview({
    required this.schedule,
    required this.movedTasks,
    required this.changedDays,
  });

  final ScheduleSnapshot schedule;
  final int movedTasks;
  final int changedDays;
}

/// The single owner of practical-weekday persistence and schedule generation.
///
/// The template is never mutated. The user choice lives in `app_settings`; the
/// effective schedule is derived deterministically from the template plus that
/// choice. Removing the setting restores the original plan exactly.
class ScheduleRepository {
  ScheduleRepository(this._db, this._template);

  final AppDatabase _db;
  final TemplateRepository _template;

  static const String practicalWeekdaysKey = 'schedule.practical_weekdays_v1';
  static const String practicalWeekdaysUpdatedAtKey =
      'schedule.practical_weekdays_updated_at_v1';
  static const String syncEntity = 'schedule_settings';
  static const String syncEntityId = 'practical_weekdays';

  Future<List<int>?> practicalWeekdays() async {
    final SettingRow? row =
        await (_db.select(_db.appSettings)
              ..where((AppSettings t) => t.key.equals(practicalWeekdaysKey)))
            .getSingleOrNull();
    return PracticalWeekdays.tryDecode(row?.value);
  }

  Stream<List<int>?> watchPracticalWeekdays() {
    final query = _db.select(_db.appSettings)
      ..where((AppSettings t) => t.key.equals(practicalWeekdaysKey));
    return query.watchSingleOrNull().map(
      (SettingRow? row) => PracticalWeekdays.tryDecode(row?.value),
    );
  }

  Future<DateTime?> _updatedAt() async {
    final SettingRow? row =
        await (_db.select(_db.appSettings)..where(
              (AppSettings t) => t.key.equals(practicalWeekdaysUpdatedAtKey),
            ))
            .getSingleOrNull();
    return DateTime.tryParse(row?.value ?? '');
  }

  Future<ScheduleSnapshot> load(PlanCalendar calendar) async {
    return _build(calendar, await practicalWeekdays());
  }

  /// Emits a new snapshot whenever the setting changes. The schedule itself is
  /// never cached, so a write cannot leave a stale task list behind.
  Stream<ScheduleSnapshot> watch(PlanCalendar calendar) {
    return watchPracticalWeekdays().asyncMap(
      (List<int>? weekdays) => _build(calendar, weekdays),
    );
  }

  Future<SchedulePreview> preview(
    PlanCalendar calendar,
    Iterable<int> weekdays,
  ) async {
    final List<int> selected = PracticalWeekdays.validate(weekdays);
    final ScheduleSnapshot current = await load(calendar);
    final ScheduleSnapshot next = await _build(
      calendar,
      PracticalWeekdays.isOriginal(selected) ? null : selected,
    );
    int moved = 0;
    for (final ScheduledTask task in next.tasks) {
      final ScheduledTask? before = current.tasksById[task.task.id];
      if (before == null || before.dayNumber != task.dayNumber) moved += 1;
    }
    int changedDays = 0;
    for (final ScheduledDay day in next.days) {
      final ScheduledDay? before = current.day(day.dayNumber);
      if (before == null ||
          before.type != day.type ||
          !_sameIds(before.taskIds, day.taskIds)) {
        changedDays += 1;
      }
    }
    return SchedulePreview(
      schedule: next,
      movedTasks: moved,
      changedDays: changedDays,
    );
  }

  /// Validates and commits the setting. The schedule is generated first so an
  /// invalid selection can never leave a half-written preference.
  Future<void> save(PlanCalendar calendar, Iterable<int> weekdays) async {
    final List<int> selected = PracticalWeekdays.validate(weekdays);
    final bool original = PracticalWeekdays.isOriginal(selected);
    await _build(calendar, original ? null : selected);

    final DateTime now = DateTime.now();
    await _db.transaction(() async {
      if (original) {
        await (_db.delete(
          _db.appSettings,
        )..where((AppSettings t) => t.key.equals(practicalWeekdaysKey))).go();
      } else {
        await _db
            .into(_db.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: practicalWeekdaysKey,
                value: PracticalWeekdays.encode(selected),
              ),
            );
      }
      await _db
          .into(_db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: practicalWeekdaysUpdatedAtKey,
              value: now.toUtc().toIso8601String(),
            ),
          );
      await SyncQueueRepository(_db)
          .enqueue(syncEntity, syncEntityId, <String, Object?>{
            'practical_weekdays': original ? const <int>[] : selected,
            'updated_at': now.toUtc().toIso8601String(),
          });
    });
  }

  /// Restores the bundled schedule and syncs the default state to the cloud.
  Future<void> reset(PlanCalendar calendar) {
    return save(calendar, PracticalWeekdays.original);
  }

  /// Applies a newer remote preference without re-enqueueing it.
  ///
  /// Local wins on ties, matching the existing task/step sync rule.
  Future<void> applyRemote(
    List<int>? weekdays,
    DateTime remoteUpdatedAt,
  ) async {
    final DateTime? localUpdatedAt = await _updatedAt();
    if (localUpdatedAt != null &&
        !remoteUpdatedAt.toUtc().isAfter(localUpdatedAt.toUtc())) {
      return;
    }
    await _db.transaction(() async {
      if (weekdays == null || weekdays.isEmpty) {
        await (_db.delete(
          _db.appSettings,
        )..where((AppSettings t) => t.key.equals(practicalWeekdaysKey))).go();
      } else {
        await _db
            .into(_db.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: practicalWeekdaysKey,
                value: PracticalWeekdays.encode(weekdays),
              ),
            );
      }
      await _db
          .into(_db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: practicalWeekdaysUpdatedAtKey,
              value: remoteUpdatedAt.toUtc().toIso8601String(),
            ),
          );
    });
  }

  Future<ScheduleSnapshot> _build(
    PlanCalendar calendar,
    List<int>? custom,
  ) async {
    final List<DayRow> dayRows = await _template.allDays();
    final List<TaskWithSteps> taskRows = await _template.allTasksWithSteps();
    final List<BreakRow> breakRows = await _template.allBreaks();
    final List<SubjectRow> subjects = await _template.allSubjects();
    if (custom == null || PracticalWeekdays.isOriginal(custom)) {
      return _buildOriginal(dayRows, taskRows, breakRows, subjects);
    }
    return _buildCustom(calendar, dayRows, taskRows, subjects, custom);
  }

  ScheduleSnapshot _buildOriginal(
    List<DayRow> dayRows,
    List<TaskWithSteps> taskRows,
    List<BreakRow> breakRows,
    List<SubjectRow> subjects,
  ) {
    final Map<String, List<TaskWithSteps>> tasksByDay =
        <String, List<TaskWithSteps>>{};
    for (final TaskWithSteps item in taskRows) {
      tasksByDay
          .putIfAbsent(item.task.dayId, () => <TaskWithSteps>[])
          .add(item);
    }
    final Map<String, List<BreakRow>> breaksByDay = <String, List<BreakRow>>{};
    for (final BreakRow item in breakRows) {
      breaksByDay.putIfAbsent(item.dayId, () => <BreakRow>[]).add(item);
    }

    final List<ScheduledDay> days = <ScheduledDay>[];
    final List<ScheduledTask> tasks = <ScheduledTask>[];
    for (final DayRow day in dayRows) {
      final List<TaskWithSteps> dayTasks =
          List<TaskWithSteps>.of(tasksByDay[day.id] ?? const <TaskWithSteps>[])
            ..sort(
              (TaskWithSteps a, TaskWithSteps b) =>
                  a.task.sortOrder.compareTo(b.task.sortOrder),
            );
      final List<BreakRow> dayBreaks = List<BreakRow>.of(
        breaksByDay[day.id] ?? const <BreakRow>[],
      )..sort((BreakRow a, BreakRow b) => a.startClock.compareTo(b.startClock));
      days.add(
        ScheduledDay(
          dayNumber: day.dayNumber,
          week: day.week,
          type: day.type,
          startClock: day.startClock,
          endClock: day.endClock,
          headerTitle: day.headerTitle,
          note: day.note,
          taskIds: <String>[
            for (final TaskWithSteps task in dayTasks) task.task.id,
          ],
          breaks: <ScheduleBreak>[
            for (final BreakRow item in dayBreaks)
              ScheduleBreak(
                id: item.id,
                startClock: item.startClock,
                endClock: item.endClock,
                minutes: item.minutes,
                kind: item.kind,
                label: item.label,
              ),
          ],
        ),
      );
      for (int index = 0; index < dayTasks.length; index++) {
        final TaskWithSteps item = dayTasks[index];
        tasks.add(
          ScheduledTask(
            task: item.task,
            steps: item.steps,
            dayNumber: day.dayNumber,
            order: index + 1,
            startClock: item.task.suggestedStart,
            endClock: item.task.suggestedEnd,
            stepSpans: <String, ScheduleSpan>{
              for (final StepRow step in item.steps)
                step.id: ScheduleSpan(
                  startClock: step.suggestedStart ?? '',
                  endClock: step.suggestedEnd ?? '',
                ),
            },
          ),
        );
      }
    }

    return ScheduleSnapshot(
      days: days,
      tasks: tasks,
      subjects: subjects,
      isCustom: false,
      practicalWeekdays: PracticalWeekdays.original,
    );
  }

  ScheduleSnapshot _buildCustom(
    PlanCalendar calendar,
    List<DayRow> dayRows,
    List<TaskWithSteps> taskRows,
    List<SubjectRow> subjects,
    List<int> weekdays,
  ) {
    final List<ScheduleDayInput> days = <ScheduleDayInput>[
      for (final DayRow day in dayRows)
        ScheduleDayInput(
          dayNumber: day.dayNumber,
          week: day.week,
          date: calendar.dateOfDay(day.dayNumber),
          isRest: day.type == 'rest',
        ),
    ];
    final List<ScheduleTaskInput> tasks = <ScheduleTaskInput>[
      for (final TaskWithSteps item in taskRows)
        ScheduleTaskInput(
          id: item.task.id,
          sourceDayNumber: _dayNumberById(dayRows, item.task.dayId),
          sourceOrder: item.task.sortOrder,
          minutes: item.steps.fold<int>(
            0,
            (int sum, StepRow step) => sum + step.minutes,
          ),
          steps: <ScheduleStepInput>[
            for (final StepRow step in item.steps)
              ScheduleStepInput(
                id: step.id,
                minutes: step.minutes,
                order: step.sortOrder,
              ),
          ],
        ),
    ];
    final ScheduleGeneration generation = ScheduleEngine.generate(
      days: days,
      tasks: tasks,
      practicalWeekdays: weekdays,
    );
    final Map<String, TaskWithSteps> byId = <String, TaskWithSteps>{
      for (final TaskWithSteps item in taskRows) item.task.id: item,
    };

    final List<ScheduledDay> scheduledDays = <ScheduledDay>[
      for (final GeneratedDay day in generation.days)
        ScheduledDay(
          dayNumber: day.dayNumber,
          week: day.week,
          type: day.type,
          startClock: day.startClock,
          endClock: day.endClock,
          headerTitle: null,
          note: null,
          taskIds: day.taskIds,
          breaks: day.breaks,
        ),
    ];
    final List<ScheduledTask> scheduledTasks = <ScheduledTask>[];
    for (final GeneratedTaskPlacement placement
        in generation.placements.values) {
      final TaskWithSteps? item = byId[placement.taskId];
      if (item == null) {
        throw ScheduleException('missing template task ${placement.taskId}');
      }
      scheduledTasks.add(
        ScheduledTask(
          task: item.task,
          steps: item.steps,
          dayNumber: placement.dayNumber,
          order: placement.order,
          startClock: placement.startClock,
          endClock: placement.endClock,
          stepSpans: placement.stepSpans,
        ),
      );
    }
    scheduledTasks.sort((ScheduledTask a, ScheduledTask b) {
      final int byDay = a.dayNumber.compareTo(b.dayNumber);
      if (byDay != 0) return byDay;
      return a.order.compareTo(b.order);
    });

    return ScheduleSnapshot(
      days: scheduledDays,
      tasks: scheduledTasks,
      subjects: subjects,
      isCustom: true,
      practicalWeekdays: generation.practicalWeekdays,
    );
  }

  static int _dayNumberById(List<DayRow> days, String id) {
    for (final DayRow day in days) {
      if (day.id == id) return day.dayNumber;
    }
    throw ScheduleException('missing template day $id');
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
