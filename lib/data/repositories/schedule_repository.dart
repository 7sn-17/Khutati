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
    this.isManual = false,
  });

  final TaskRow task;
  final List<StepRow> steps;
  final int dayNumber;
  final int order;
  final String? startClock;
  final String? endClock;
  final Map<String, ScheduleSpan> stepSpans;

  /// `true` when the user placed this task by hand.
  final bool isManual;

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
    this.overrides = const <String, ScheduleOverrideInput>{},
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

  /// Manual placements that produced this snapshot, keyed by task id.
  final Map<String, ScheduleOverrideInput> overrides;

  bool get hasOverrides => overrides.isNotEmpty;

  ScheduledDay? day(int dayNumber) => daysByNumber[dayNumber];

  List<ScheduledTask> tasksForDay(int dayNumber) {
    return _tasksByDay[dayNumber] ?? const <ScheduledTask>[];
  }

  /// Every task in curriculum order: day first, then position in the day.
  List<ScheduledTask> get orderedTasks {
    final List<ScheduledTask> ordered = List<ScheduledTask>.of(tasks)
      ..sort((ScheduledTask a, ScheduledTask b) {
        final int byDay = a.dayNumber.compareTo(b.dayNumber);
        return byDay != 0 ? byDay : a.order.compareTo(b.order);
      });
    return ordered;
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

/// A day whose type changes between two schedules.
class DayTypeChange {
  const DayTypeChange({
    required this.dayNumber,
    required this.before,
    required this.after,
  });

  final int dayNumber;
  final String before;
  final String after;
}

/// A day whose planned minutes change between two schedules.
class DayLoadChange {
  const DayLoadChange({
    required this.dayNumber,
    required this.beforeMinutes,
    required this.afterMinutes,
    this.beforeTasks = 0,
    this.afterTasks = 0,
  });

  final int dayNumber;
  final int beforeMinutes;
  final int afterMinutes;
  final int beforeTasks;
  final int afterTasks;

  int get deltaMinutes => afterMinutes - beforeMinutes;
  int get deltaTasks => afterTasks - beforeTasks;
}

/// One task whose day or start clock moves between two schedules.
class TaskPlacementChange {
  const TaskPlacementChange({
    required this.task,
    required this.fromDay,
    required this.toDay,
    required this.fromStartClock,
    required this.toStartClock,
  });

  /// The task in its new position.
  final ScheduledTask task;
  final int fromDay;
  final int toDay;
  final String? fromStartClock;
  final String? toStartClock;

  bool get changedDay => fromDay != toDay;
}

/// The effect of a change on one day, in tasks and in minutes.
class DayImpact {
  const DayImpact({
    required this.dayNumber,
    required this.beforeTasks,
    required this.afterTasks,
    required this.beforeMinutes,
    required this.afterMinutes,
  });

  final int dayNumber;
  final int beforeTasks;
  final int afterTasks;
  final int beforeMinutes;
  final int afterMinutes;

  int get deltaTasks => afterTasks - beforeTasks;
  int get deltaMinutes => afterMinutes - beforeMinutes;
}

/// A proposed set of manual placements, diffed against what is saved today.
///
/// Nothing is written by producing one: the rescheduling screen renders this
/// and only [ScheduleRepository.commitOverrides] persists it.
class ScheduleImpact {
  const ScheduleImpact({
    required this.schedule,
    required this.moves,
    required this.days,
    required this.finishDayBefore,
    required this.finishDayAfter,
    this.droppedOverrides = const <String>[],
    this.ok = true,
    this.issue = TaskMoveIssue.none,
    this.error,
  });

  /// The schedule the draft would produce (the current one when [ok] is false).
  final ScheduleSnapshot schedule;
  final List<TaskPlacementChange> moves;

  /// Only the days whose task count or planned minutes change.
  final List<DayImpact> days;

  final int? finishDayBefore;
  final int? finishDayAfter;
  final List<String> droppedOverrides;
  final bool ok;
  final TaskMoveIssue issue;

  /// Engine message, for logs and tests. Never shown to the user.
  final String? error;

  int get finishDayDelta => (finishDayAfter ?? 0) - (finishDayBefore ?? 0);

  bool get hasChanges => moves.isNotEmpty || days.isNotEmpty;
}

class SchedulePreview {
  const SchedulePreview({
    required this.schedule,
    required this.movedTasks,
    required this.changedDays,
    this.dayChanges = const <DayTypeChange>[],
    this.loadChanges = const <DayLoadChange>[],
    this.droppedOverrides = const <String>[],
    this.previousWeekdays = const <int>[],
    this.nextWeekdays = const <int>[],
    this.finishDayBefore,
    this.finishDayAfter,
  });

  final ScheduleSnapshot schedule;
  final int movedTasks;
  final int changedDays;

  /// Days whose `normal`/`practical`/`rest` type changes.
  final List<DayTypeChange> dayChanges;

  /// Days whose planned minutes change, largest difference first.
  final List<DayLoadChange> loadChanges;

  /// Manual overrides that cannot survive the new weekday set.
  final List<String> droppedOverrides;
  final List<int> previousWeekdays;
  final List<int> nextWeekdays;

  /// Last day of the plan that still has a task, before and after.
  final int? finishDayBefore;
  final int? finishDayAfter;

  int get finishDayDelta => (finishDayAfter ?? 0) - (finishDayBefore ?? 0);

  bool get hasChanges => movedTasks > 0 || changedDays > 0;
}

/// Why a requested manual move cannot be applied.
enum TaskMoveIssue {
  none,
  unknownTask,
  restDay,
  dependencyBefore,
  dependencyAfter,
  overlap,
  pastMidnight,
  invalidTime,
  unavailable,
}

/// Result of validating a manual move before it is written.
class TaskMovePreview {
  const TaskMovePreview({
    required this.issue,
    this.schedule,
    this.task,
    this.fromDay,
    this.toDay,
    this.fromClock,
    this.toClock,
    this.blocking,
    this.affected = const <ScheduledTask>[],
  });

  final TaskMoveIssue issue;

  /// The proposed schedule. Only set when [issue] is [TaskMoveIssue.none].
  final ScheduleSnapshot? schedule;
  final ScheduledTask? task;
  final int? fromDay;
  final int? toDay;
  final String? fromClock;
  final String? toClock;

  /// The task that blocks the move: a prerequisite, a dependent task, or the
  /// task whose time would be overlapped.
  final ScheduledTask? blocking;

  /// Tasks whose day, position or clock would change.
  final List<ScheduledTask> affected;

  bool get ok => issue == TaskMoveIssue.none && schedule != null;
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
  static const String overrideSyncEntity = 'schedule_override';

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

  Future<Map<String, ScheduleOverrideInput>> overrides() async {
    final List<ScheduleOverrideRow> rows = await _db
        .select(_db.scheduleOverrides)
        .get();
    return _toOverrides(rows);
  }

  Stream<Map<String, ScheduleOverrideInput>> watchOverrides() {
    return _db.select(_db.scheduleOverrides).watch().map(_toOverrides);
  }

  static Map<String, ScheduleOverrideInput> _toOverrides(
    List<ScheduleOverrideRow> rows,
  ) {
    return <String, ScheduleOverrideInput>{
      for (final ScheduleOverrideRow row in rows)
        row.taskId: ScheduleOverrideInput(
          dayNumber: row.dayNumber,
          position: row.position,
          startClock: row.startClock,
        ),
    };
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
    return _build(calendar, await practicalWeekdays(), await overrides());
  }

  /// Emits a new snapshot whenever the weekday setting or a manual override
  /// changes. The schedule itself is never cached, so a write cannot leave a
  /// stale task list behind.
  Stream<ScheduleSnapshot> watch(PlanCalendar calendar) async* {
    yield await load(calendar);
    await for (final _ in _scheduleChanges()) {
      yield await load(calendar);
    }
  }

  /// Merges the two inputs of the schedule into one change signal.
  Stream<void> _scheduleChanges() {
    final StreamController<void> controller = StreamController<void>();
    final List<StreamSubscription<dynamic>> subscriptions =
        <StreamSubscription<dynamic>>[];
    controller.onListen = () {
      subscriptions.add(
        watchPracticalWeekdays()
            .skip(1)
            .listen((_) => controller.add(null), onError: controller.addError),
      );
      subscriptions.add(
        watchOverrides()
            .skip(1)
            .listen((_) => controller.add(null), onError: controller.addError),
      );
    };
    controller.onCancel = () async {
      for (final StreamSubscription<dynamic> subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
    };
    return controller.stream;
  }

  /// Builds the proposed schedule for a weekday selection without writing it.
  ///
  /// Manual overrides are carried over. When one cannot survive the new
  /// partition it is reported in [SchedulePreview.droppedOverrides] instead of
  /// failing the whole preview, so the confirmation step can explain exactly
  /// what the user is about to lose.
  Future<SchedulePreview> preview(
    PlanCalendar calendar,
    Iterable<int> weekdays,
  ) async {
    final List<int> selected = PracticalWeekdays.validate(weekdays);
    final ScheduleSnapshot current = await load(calendar);
    final _Resolved resolved = await _resolve(
      calendar,
      selected,
      await overrides(),
    );
    final ScheduleSnapshot next = resolved.schedule;

    int moved = 0;
    for (final ScheduledTask task in next.tasks) {
      final ScheduledTask? before = current.tasksById[task.task.id];
      if (before == null ||
          before.dayNumber != task.dayNumber ||
          before.startClock != task.startClock) {
        moved += 1;
      }
    }

    int changedDays = 0;
    final List<DayTypeChange> typeChanges = <DayTypeChange>[];
    final List<DayLoadChange> loadChanges = <DayLoadChange>[];
    for (final ScheduledDay day in next.days) {
      final ScheduledDay? before = current.day(day.dayNumber);
      if (before == null ||
          before.type != day.type ||
          !_sameIds(before.taskIds, day.taskIds)) {
        changedDays += 1;
      }
      if (before != null && before.type != day.type) {
        typeChanges.add(
          DayTypeChange(
            dayNumber: day.dayNumber,
            before: before.type,
            after: day.type,
          ),
        );
      }
      final List<ScheduledTask> beforeTasks = before == null
          ? const <ScheduledTask>[]
          : current.tasksForDay(day.dayNumber);
      final List<ScheduledTask> afterTasks = next.tasksForDay(day.dayNumber);
      final int beforeMinutes = beforeTasks.fold<int>(
        0,
        (int sum, ScheduledTask t) => sum + t.plannedMinutes,
      );
      final int afterMinutes = afterTasks.fold<int>(
        0,
        (int sum, ScheduledTask t) => sum + t.plannedMinutes,
      );
      if (beforeMinutes != afterMinutes ||
          beforeTasks.length != afterTasks.length) {
        loadChanges.add(
          DayLoadChange(
            dayNumber: day.dayNumber,
            beforeMinutes: beforeMinutes,
            afterMinutes: afterMinutes,
            beforeTasks: beforeTasks.length,
            afterTasks: afterTasks.length,
          ),
        );
      }
    }
    loadChanges.sort((DayLoadChange a, DayLoadChange b) {
      final int byTasks = b.deltaTasks.abs().compareTo(a.deltaTasks.abs());
      return byTasks != 0
          ? byTasks
          : b.deltaMinutes.abs().compareTo(a.deltaMinutes.abs());
    });

    return SchedulePreview(
      schedule: next,
      movedTasks: moved,
      changedDays: changedDays,
      dayChanges: typeChanges,
      loadChanges: loadChanges,
      droppedOverrides: resolved.dropped,
      previousWeekdays: current.practicalWeekdays,
      nextWeekdays: selected,
      finishDayBefore: _finishDay(current),
      finishDayAfter: _finishDay(next),
    );
  }

  /// Validates and commits the setting. The schedule is generated first so an
  /// invalid selection can never leave a half-written preference. Overrides
  /// that cannot survive the new partition are deleted in the same transaction
  /// and were already shown in the preview.
  Future<void> save(PlanCalendar calendar, Iterable<int> weekdays) async {
    final List<int> selected = PracticalWeekdays.validate(weekdays);
    final bool original = PracticalWeekdays.isOriginal(selected);
    final _Resolved resolved = await _resolve(
      calendar,
      selected,
      await overrides(),
    );

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
      for (final String taskId in resolved.dropped) {
        await (_db.delete(
          _db.scheduleOverrides,
        )..where((ScheduleOverrides t) => t.taskId.equals(taskId))).go();
        await SyncQueueRepository(_db).enqueue(
          overrideSyncEntity,
          taskId,
          <String, Object?>{'task_id': taskId, 'deleted': true},
        );
      }
      await SyncQueueRepository(_db)
          .enqueue(syncEntity, syncEntityId, <String, Object?>{
            'practical_weekdays': original ? const <int>[] : selected,
            'updated_at': now.toUtc().toIso8601String(),
          });
    });
  }

  /// Applies a weekday selection plus the overrides that fit it.
  Future<_Resolved> _resolve(
    PlanCalendar calendar,
    List<int> selected,
    Map<String, ScheduleOverrideInput> manual,
  ) async {
    final List<int>? custom = PracticalWeekdays.isOriginal(selected)
        ? null
        : selected;
    try {
      return _Resolved(
        schedule: await _build(calendar, custom, manual),
        dropped: const <String>[],
      );
    } on ScheduleException {
      if (manual.isEmpty) rethrow;
    }

    final Map<String, ScheduleOverrideInput> working =
        Map<String, ScheduleOverrideInput>.of(manual);
    final List<String> dropped = <String>[];
    for (final String taskId in await _newestOverrideIdsFirst()) {
      working.remove(taskId);
      dropped.add(taskId);
      try {
        return _Resolved(
          schedule: await _build(calendar, custom, working),
          dropped: List<String>.unmodifiable(dropped),
        );
      } on ScheduleException {
        continue;
      }
    }
    throw const ScheduleException(
      'no manual override can explain the scheduling failure',
    );
  }

  Future<List<String>> _newestOverrideIdsFirst() async {
    final List<ScheduleOverrideRow> rows = await (_db.select(
      _db.scheduleOverrides,
    )..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).get();
    return <String>[for (final ScheduleOverrideRow row in rows) row.taskId];
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

  // ---- manual scheduling -------------------------------------------------

  /// Validates a manual placement against the current schedule without writing
  /// anything. The returned preview carries the proposed snapshot or a typed
  /// reason the move is not allowed.
  Future<TaskMovePreview> previewMove(
    PlanCalendar calendar, {
    required String taskId,
    int? dayNumber,
    int? position,
    String? startClock,
  }) async {
    final ScheduleSnapshot current = await load(calendar);
    final ScheduledTask? task = current.tasksById[taskId];
    if (task == null) {
      return const TaskMovePreview(issue: TaskMoveIssue.unknownTask);
    }
    final int target = dayNumber ?? task.dayNumber;
    final ScheduledDay? targetDay = current.day(target);
    if (targetDay == null) {
      return TaskMovePreview(
        issue: TaskMoveIssue.unavailable,
        task: task,
        fromDay: task.dayNumber,
      );
    }
    if (targetDay.isRest) {
      return TaskMovePreview(
        issue: TaskMoveIssue.restDay,
        task: task,
        fromDay: task.dayNumber,
        toDay: target,
      );
    }

    final List<ScheduledTask> ordered = current.orderedTasks;
    final int index = ordered.indexWhere(
      (ScheduledTask item) => item.task.id == taskId,
    );
    final ScheduledTask? previous = index > 0 ? ordered[index - 1] : null;
    final ScheduledTask? next = index + 1 < ordered.length
        ? ordered[index + 1]
        : null;

    if (previous != null && target < previous.dayNumber) {
      return TaskMovePreview(
        issue: TaskMoveIssue.dependencyBefore,
        task: task,
        fromDay: task.dayNumber,
        toDay: target,
        blocking: previous,
      );
    }
    if (next != null && target > next.dayNumber) {
      return TaskMovePreview(
        issue: TaskMoveIssue.dependencyAfter,
        task: task,
        fromDay: task.dayNumber,
        toDay: target,
        blocking: next,
      );
    }

    final List<ScheduledTask> targetTasks = List<ScheduledTask>.of(
      current.tasksForDay(target),
    )..removeWhere((ScheduledTask item) => item.task.id == taskId);
    final int slot = (position ?? targetTasks.length + 1).clamp(
      1,
      targetTasks.length + 1,
    );

    if (startClock != null) {
      final int? start = _parseClock(startClock);
      if (start == null) {
        return TaskMovePreview(
          issue: TaskMoveIssue.invalidTime,
          task: task,
          fromDay: task.dayNumber,
          toDay: target,
        );
      }
      final ScheduledTask? before = slot > 1 ? targetTasks[slot - 2] : null;
      if (before != null) {
        final int? end = _parseClock(before.endClock ?? '');
        if (end != null && start < end) {
          return TaskMovePreview(
            issue: TaskMoveIssue.overlap,
            task: task,
            fromDay: task.dayNumber,
            toDay: target,
            blocking: before,
          );
        }
      }
      if (start + task.plannedMinutes >= 24 * 60) {
        return TaskMovePreview(
          issue: TaskMoveIssue.pastMidnight,
          task: task,
          fromDay: task.dayNumber,
          toDay: target,
        );
      }
    }

    final Map<String, ScheduleOverrideInput> manual =
        Map<String, ScheduleOverrideInput>.of(current.overrides);
    manual[taskId] = ScheduleOverrideInput(
      dayNumber: target,
      position: slot,
      startClock: startClock,
    );

    ScheduleSnapshot proposed;
    try {
      proposed = await _build(
        calendar,
        current.isCustom ? current.practicalWeekdays : null,
        manual,
      );
    } on ScheduleException {
      return TaskMovePreview(
        issue: TaskMoveIssue.unavailable,
        task: task,
        fromDay: task.dayNumber,
        toDay: target,
      );
    }

    final ScheduledTask placed = proposed.tasksById[taskId]!;
    final List<ScheduledTask> affected = <ScheduledTask>[
      for (final ScheduledTask item in proposed.tasks)
        if (_placementChanged(current.tasksById[item.task.id], item)) item,
    ];

    return TaskMovePreview(
      issue: TaskMoveIssue.none,
      schedule: proposed,
      task: placed,
      fromDay: task.dayNumber,
      toDay: placed.dayNumber,
      fromClock: task.startClock,
      toClock: placed.startClock,
      affected: List<ScheduledTask>.unmodifiable(affected),
    );
  }

  /// Commits a validated manual move and queues it for sync.
  Future<TaskMovePreview> commitMove(
    PlanCalendar calendar, {
    required String taskId,
    int? dayNumber,
    int? position,
    String? startClock,
  }) async {
    final TaskMovePreview preview = await previewMove(
      calendar,
      taskId: taskId,
      dayNumber: dayNumber,
      position: position,
      startClock: startClock,
    );
    if (!preview.ok) return preview;

    final ScheduledTask placed = preview.schedule!.tasksById[taskId]!;
    final DateTime now = DateTime.now();
    await _db.transaction(() async {
      await _db
          .into(_db.scheduleOverrides)
          .insertOnConflictUpdate(
            ScheduleOverridesCompanion.insert(
              taskId: taskId,
              dayNumber: placed.dayNumber,
              position: Value<int?>(placed.order),
              startClock: Value<String?>(startClock),
              updatedAt: now,
            ),
          );
      await SyncQueueRepository(_db)
          .enqueue(overrideSyncEntity, taskId, <String, Object?>{
            'task_id': taskId,
            'day_number': placed.dayNumber,
            'position': placed.order,
            'start_clock': startClock,
            'updated_at': now.toUtc().toIso8601String(),
          });
    });
    return preview;
  }

  /// Diffs a whole draft of manual placements against what is saved today.
  ///
  /// Unlike [previewMove], this validates the *combination*: three moves that
  /// are each fine on their own can still invert the curriculum together. The
  /// screen uses it for the live impact panel; [commitOverrides] uses it as the
  /// gate before writing anything.
  Future<ScheduleImpact> previewOverrides(
    PlanCalendar calendar,
    Map<String, ScheduleOverrideInput> draft,
  ) async {
    final ScheduleSnapshot current = await load(calendar);
    if (draft.isEmpty) {
      return ScheduleImpact(
        schedule: current,
        moves: const <TaskPlacementChange>[],
        days: const <DayImpact>[],
        finishDayBefore: _finishDay(current),
        finishDayAfter: _finishDay(current),
      );
    }

    // The draft is only the *pending* edits; the placements saved earlier must
    // still apply, otherwise the preview would show every previously moved
    // task snapping back to its automatic slot.
    final Map<String, ScheduleOverrideInput> merged =
        <String, ScheduleOverrideInput>{...await overrides(), ...draft};

    try {
      final ScheduleSnapshot next = await _build(
        calendar,
        _customWeekdays(current.practicalWeekdays),
        merged,
      );
      // The untouched-template path only re-times the days it patched, so it
      // does not run the engine's own checks. Validate the outcome here for
      // both paths: a draft is only acceptable if every task still sits on a
      // study day and the curriculum never runs backwards.
      _validatePlacements(current, next);
      final _ScheduleDiff diff = _diff(current, next);
      return ScheduleImpact(
        schedule: next,
        moves: diff.moves,
        days: diff.days,
        finishDayBefore: diff.finishBefore,
        finishDayAfter: diff.finishAfter,
      );
    } on ScheduleException catch (error) {
      return ScheduleImpact(
        schedule: current,
        moves: const <TaskPlacementChange>[],
        days: const <DayImpact>[],
        finishDayBefore: _finishDay(current),
        finishDayAfter: _finishDay(current),
        ok: false,
        issue: TaskMoveIssue.unavailable,
        error: error.message,
      );
    }
  }

  /// Writes every placement in [draft] in one transaction.
  ///
  /// The whole draft is validated first, so a conflict can never leave half the
  /// moves saved. Rows are stored with their resolved day and order, exactly
  /// like [commitMove], so a later weekday change can reason about them.
  Future<void> commitOverrides(
    PlanCalendar calendar,
    Map<String, ScheduleOverrideInput> draft,
  ) async {
    if (draft.isEmpty) return;
    final ScheduleImpact impact = await previewOverrides(calendar, draft);
    if (!impact.ok) {
      throw ScheduleException(impact.error ?? 'the draft cannot be applied');
    }

    final DateTime now = DateTime.now();
    await _db.transaction(() async {
      for (final MapEntry<String, ScheduleOverrideInput> entry
          in draft.entries) {
        final ScheduledTask? placed = impact.schedule.tasksById[entry.key];
        if (placed == null) {
          throw ScheduleException('task ${entry.key} is not scheduled');
        }
        await _db
            .into(_db.scheduleOverrides)
            .insertOnConflictUpdate(
              ScheduleOverridesCompanion.insert(
                taskId: entry.key,
                dayNumber: placed.dayNumber,
                position: Value<int?>(placed.order),
                startClock: Value<String?>(entry.value.startClock),
                updatedAt: now,
              ),
            );
        await SyncQueueRepository(_db)
            .enqueue(overrideSyncEntity, entry.key, <String, Object?>{
              'task_id': entry.key,
              'day_number': placed.dayNumber,
              'position': placed.order,
              'start_clock': entry.value.startClock,
              'updated_at': now.toUtc().toIso8601String(),
            });
      }
    });
  }

  static List<int>? _customWeekdays(List<int> weekdays) {
    return PracticalWeekdays.isOriginal(weekdays) ? null : weekdays;
  }

  /// Rejects a draft whose result would put a task on a rest day or invert the
  /// curriculum. The template path applies overrides without regenerating the
  /// plan, so neither invariant can be taken for granted there.
  static void _validatePlacements(
    ScheduleSnapshot current,
    ScheduleSnapshot next,
  ) {
    final Map<String, int> dayOf = <String, int>{};
    for (final ScheduledTask task in next.tasks) {
      final ScheduledDay? day = next.day(task.dayNumber);
      if (day == null || day.isRest) {
        throw ScheduleException(
          'task ${task.task.id} would land on a rest day',
        );
      }
      dayOf[task.task.id] = task.dayNumber;
    }

    // [current] is in curriculum order, which is what the sequence rule is
    // defined against: a task may never sit on an earlier day than the task
    // before it.
    final List<ScheduledTask> canonical = current.orderedTasks;
    for (int index = 1; index < canonical.length; index++) {
      final String previous = canonical[index - 1].task.id;
      final String id = canonical[index].task.id;
      final int? previousDay = dayOf[previous];
      final int? day = dayOf[id];
      if (previousDay == null || day == null) continue;
      if (day < previousDay) {
        throw ScheduleException(
          'sequence violation: $id would move to day $day before $previous '
          'on day $previousDay',
        );
      }
    }
  }

  static int? _finishDay(ScheduleSnapshot snapshot) {
    int? last;
    for (final ScheduledTask task in snapshot.tasks) {
      if (last == null || task.dayNumber > last) last = task.dayNumber;
    }
    return last;
  }

  static _ScheduleDiff _diff(ScheduleSnapshot current, ScheduleSnapshot next) {
    final List<TaskPlacementChange> moves = <TaskPlacementChange>[];
    for (final ScheduledTask task in next.orderedTasks) {
      final ScheduledTask? before = current.tasksById[task.task.id];
      if (before == null) continue;
      if (before.dayNumber == task.dayNumber &&
          before.startClock == task.startClock) {
        continue;
      }
      moves.add(
        TaskPlacementChange(
          task: task,
          fromDay: before.dayNumber,
          toDay: task.dayNumber,
          fromStartClock: before.startClock,
          toStartClock: task.startClock,
        ),
      );
    }

    final List<DayImpact> days = <DayImpact>[];
    for (final ScheduledDay day in next.days) {
      if (day.isRest) continue;
      final List<ScheduledTask> beforeTasks = current.tasksForDay(
        day.dayNumber,
      );
      final List<ScheduledTask> afterTasks = next.tasksForDay(day.dayNumber);
      final int beforeMinutes = beforeTasks.fold<int>(
        0,
        (int sum, ScheduledTask t) => sum + t.plannedMinutes,
      );
      final int afterMinutes = afterTasks.fold<int>(
        0,
        (int sum, ScheduledTask t) => sum + t.plannedMinutes,
      );
      if (beforeTasks.length == afterTasks.length &&
          beforeMinutes == afterMinutes) {
        continue;
      }
      days.add(
        DayImpact(
          dayNumber: day.dayNumber,
          beforeTasks: beforeTasks.length,
          afterTasks: afterTasks.length,
          beforeMinutes: beforeMinutes,
          afterMinutes: afterMinutes,
        ),
      );
    }
    days.sort((DayImpact a, DayImpact b) {
      final int bySize = b.deltaTasks.abs().compareTo(a.deltaTasks.abs());
      return bySize != 0
          ? bySize
          : b.deltaMinutes.abs().compareTo(a.deltaMinutes.abs());
    });

    return _ScheduleDiff(
      moves: moves,
      days: days,
      finishBefore: _finishDay(current),
      finishAfter: _finishDay(next),
    );
  }

  /// Removes one manual placement and returns to automatic scheduling for it.
  Future<void> clearOverride(String taskId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.scheduleOverrides,
      )..where((ScheduleOverrides t) => t.taskId.equals(taskId))).go();
      await SyncQueueRepository(_db).enqueue(
        overrideSyncEntity,
        taskId,
        <String, Object?>{'task_id': taskId, 'deleted': true},
      );
    });
  }

  /// Removes every manual placement.
  Future<void> clearAllOverrides() async {
    final List<ScheduleOverrideRow> rows = await _db
        .select(_db.scheduleOverrides)
        .get();
    if (rows.isEmpty) return;
    await _db.transaction(() async {
      await _db.delete(_db.scheduleOverrides).go();
      for (final ScheduleOverrideRow row in rows) {
        await SyncQueueRepository(_db).enqueue(
          overrideSyncEntity,
          row.taskId,
          <String, Object?>{'task_id': row.taskId, 'deleted': true},
        );
      }
    });
  }

  /// Applies a remote override without re-enqueueing it. Local wins on ties.
  Future<void> applyRemoteOverride(
    String taskId,
    ScheduleOverrideInput? value,
    DateTime remoteUpdatedAt,
  ) async {
    final ScheduleOverrideRow? local =
        await (_db.select(_db.scheduleOverrides)
              ..where((ScheduleOverrides t) => t.taskId.equals(taskId)))
            .getSingleOrNull();
    if (local != null &&
        !remoteUpdatedAt.toUtc().isAfter(local.updatedAt.toUtc())) {
      return;
    }
    if (value == null) {
      await (_db.delete(
        _db.scheduleOverrides,
      )..where((ScheduleOverrides t) => t.taskId.equals(taskId))).go();
      return;
    }
    await _db
        .into(_db.scheduleOverrides)
        .insertOnConflictUpdate(
          ScheduleOverridesCompanion.insert(
            taskId: taskId,
            dayNumber: value.dayNumber,
            position: Value<int?>(value.position),
            startClock: Value<String?>(value.startClock),
            updatedAt: remoteUpdatedAt.toUtc(),
          ),
        );
  }

  static bool _placementChanged(ScheduledTask? before, ScheduledTask after) {
    if (before == null) return true;
    return before.dayNumber != after.dayNumber ||
        before.order != after.order ||
        before.startClock != after.startClock;
  }

  static int? _parseClock(String clock) {
    final List<String> parts = clock.split(':');
    if (parts.length != 2) return null;
    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  Future<ScheduleSnapshot> _build(
    PlanCalendar calendar,
    List<int>? custom,
    Map<String, ScheduleOverrideInput> overrides,
  ) async {
    final List<DayRow> dayRows = await _template.allDays();
    final List<TaskWithSteps> taskRows = await _template.allTasksWithSteps();
    final List<BreakRow> breakRows = await _template.allBreaks();
    final List<SubjectRow> subjects = await _template.allSubjects();
    if (custom == null || PracticalWeekdays.isOriginal(custom)) {
      final ScheduleSnapshot base = _buildOriginal(
        dayRows,
        taskRows,
        breakRows,
        subjects,
      );
      return overrides.isEmpty ? base : _patchOriginal(base, overrides);
    }
    return _buildCustom(
      calendar,
      dayRows,
      taskRows,
      subjects,
      custom,
      overrides,
    );
  }

  /// Applies manual placements to the untouched template schedule.
  ///
  /// Only the days whose task list or pinned clock changed are re-timed; every
  /// other day keeps the plan's own printed times. This is what lets a single
  /// manual move leave the rest of the 68 days exactly as imported.
  ScheduleSnapshot _patchOriginal(
    ScheduleSnapshot base,
    Map<String, ScheduleOverrideInput> overrides,
  ) {
    final Map<int, List<ScheduledTask>> byDay = <int, List<ScheduledTask>>{
      for (final ScheduledDay day in base.days)
        day.dayNumber: List<ScheduledTask>.of(base.tasksForDay(day.dayNumber)),
    };

    for (final String taskId in overrides.keys) {
      for (final List<ScheduledTask> list in byDay.values) {
        list.removeWhere((ScheduledTask item) => item.task.id == taskId);
      }
    }

    final Map<int, List<MapEntry<String, ScheduleOverrideInput>>> perDay =
        <int, List<MapEntry<String, ScheduleOverrideInput>>>{};
    for (final MapEntry<String, ScheduleOverrideInput> entry
        in overrides.entries) {
      perDay
          .putIfAbsent(
            entry.value.dayNumber,
            () => <MapEntry<String, ScheduleOverrideInput>>[],
          )
          .add(entry);
    }
    for (final MapEntry<int, List<MapEntry<String, ScheduleOverrideInput>>>
        dayEntry
        in perDay.entries) {
      final List<ScheduledTask> list = byDay[dayEntry.key]!;
      dayEntry.value.sort((
        MapEntry<String, ScheduleOverrideInput> a,
        MapEntry<String, ScheduleOverrideInput> b,
      ) {
        final int positionA = a.value.position ?? 1 << 20;
        final int positionB = b.value.position ?? 1 << 20;
        if (positionA != positionB) return positionA.compareTo(positionB);
        return a.key.compareTo(b.key);
      });
      for (final MapEntry<String, ScheduleOverrideInput> entry
          in dayEntry.value) {
        final ScheduledTask? task = base.tasksById[entry.key];
        if (task == null) {
          throw ScheduleException(
            'override references unknown task ${entry.key}',
          );
        }
        final int slot = (entry.value.position ?? list.length + 1).clamp(
          1,
          list.length + 1,
        );
        list.insert(slot - 1, task);
      }
    }

    final List<ScheduledDay> days = <ScheduledDay>[];
    final List<ScheduledTask> tasks = <ScheduledTask>[];
    for (final ScheduledDay day in base.days) {
      final List<ScheduledTask> list = byDay[day.dayNumber]!;
      final bool pinned = overrides.entries.any(
        (MapEntry<String, ScheduleOverrideInput> entry) =>
            entry.value.dayNumber == day.dayNumber &&
            entry.value.startClock != null,
      );
      final bool changed =
          pinned ||
          !_sameIds(day.taskIds, <String>[
            for (final ScheduledTask task in list) task.task.id,
          ]);
      if (!changed) {
        days.add(day);
        tasks.addAll(base.tasksForDay(day.dayNumber));
        continue;
      }
      final int? startMinute = _parseClock(day.startClock ?? '');
      final TimedDay timed = ScheduleEngine.timeDay(
        dayNumber: day.dayNumber,
        week: day.week,
        tasks: <ScheduleTaskInput>[
          for (final ScheduledTask task in list) _toInput(task),
        ],
        practical: day.isPractical,
        startMinute: startMinute,
        pinnedStarts: <String, String>{
          for (final MapEntry<String, ScheduleOverrideInput> entry
              in overrides.entries)
            if (entry.value.dayNumber == day.dayNumber &&
                entry.value.startClock != null)
              entry.key: entry.value.startClock!,
        },
        manualIds: overrides.keys.toSet(),
      );
      days.add(
        ScheduledDay(
          dayNumber: day.dayNumber,
          week: day.week,
          type: day.type,
          startClock: timed.day.startClock,
          endClock: timed.day.endClock,
          headerTitle: day.headerTitle,
          note: day.note,
          taskIds: timed.day.taskIds,
          breaks: timed.day.breaks,
        ),
      );
      for (final String id in timed.day.taskIds) {
        final ScheduledTask original = base.tasksById[id]!;
        final GeneratedTaskPlacement placement = timed.placements[id]!;
        tasks.add(
          ScheduledTask(
            task: original.task,
            steps: original.steps,
            dayNumber: day.dayNumber,
            order: placement.order,
            startClock: placement.startClock,
            endClock: placement.endClock,
            stepSpans: placement.stepSpans,
            isManual: placement.isManual,
          ),
        );
      }
    }

    tasks.sort((ScheduledTask a, ScheduledTask b) {
      final int byDay = a.dayNumber.compareTo(b.dayNumber);
      return byDay != 0 ? byDay : a.order.compareTo(b.order);
    });

    // A manual placement may not invert the curriculum at day granularity:
    // ordering inside a day is the user's choice, crossing a day backwards is
    // not.
    final Map<String, int> dayOf = <String, int>{
      for (final ScheduledTask task in tasks) task.task.id: task.dayNumber,
    };
    final List<ScheduledTask> canonical = base.orderedTasks;
    for (int index = 1; index < canonical.length; index++) {
      final int previous = dayOf[canonical[index - 1].task.id]!;
      final int current = dayOf[canonical[index].task.id]!;
      if (current < previous) {
        throw ScheduleException(
          'manual placement moves ${canonical[index].task.id} to day $current '
          'before ${canonical[index - 1].task.id} on day $previous',
        );
      }
    }

    return ScheduleSnapshot(
      days: days,
      tasks: tasks,
      subjects: base.subjects,
      isCustom: false,
      practicalWeekdays: base.practicalWeekdays,
      overrides: overrides,
    );
  }

  static ScheduleTaskInput _toInput(ScheduledTask task) {
    return ScheduleTaskInput(
      id: task.task.id,
      sourceDayNumber: task.dayNumber,
      sourceOrder: task.order,
      minutes: task.plannedMinutes,
      steps: <ScheduleStepInput>[
        for (final StepRow step in task.stepsInOrder)
          ScheduleStepInput(
            id: step.id,
            minutes: step.minutes,
            order: step.sortOrder,
          ),
      ],
    );
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
    Map<String, ScheduleOverrideInput> overrides,
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
      overrides: overrides,
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
          isManual: placement.isManual,
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
      overrides: overrides,
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

class _Resolved {
  const _Resolved({required this.schedule, required this.dropped});

  final ScheduleSnapshot schedule;
  final List<String> dropped;
}

/// Raw result of diffing two snapshots, before it is wrapped in an impact.
class _ScheduleDiff {
  const _ScheduleDiff({
    required this.moves,
    required this.days,
    required this.finishBefore,
    required this.finishAfter,
  });

  final List<TaskPlacementChange> moves;
  final List<DayImpact> days;
  final int? finishBefore;
  final int? finishAfter;
}
