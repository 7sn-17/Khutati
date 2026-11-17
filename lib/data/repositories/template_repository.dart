import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// A task with its ordered steps, ready for the hybrid task list (PRD 5.4).
class TaskWithSteps {
  const TaskWithSteps({required this.task, required this.steps});

  final TaskRow task;
  final List<StepRow> steps;
}

/// One plan day plus everything the Today and Day screens need.
class DayBundle {
  const DayBundle({
    required this.day,
    required this.tasks,
    required this.breaks,
  });

  final DayRow day;
  final List<TaskWithSteps> tasks;
  final List<BreakRow> breaks;

  int get plannedMinutes => tasks.fold<int>(
        0,
        (int sum, TaskWithSteps task) =>
            sum + task.steps.fold<int>(0, (int s, StepRow step) => s + step.minutes),
      );

  int get stepCount =>
      tasks.fold<int>(0, (int sum, TaskWithSteps task) => sum + task.steps.length);
}

/// Read-only access to the imported plan template.
///
/// Deliberately has no write methods: template rows are written only by the
/// import pipeline (Phase 2.1), never by the UI.
class TemplateRepository {
  TemplateRepository(this._db);

  final AppDatabase _db;

  Future<List<DayRow>> allDays() {
    final query = _db.select(_db.days);
    query.orderBy([(t) => OrderingTerm.asc(t.dayNumber)]);
    return query.get();
  }
  Future<DayRow?> dayByNumber(int dayNumber) {
    return (_db.select(_db.days)..where((t) => t.dayNumber.equals(dayNumber))).getSingleOrNull();
  }

  /// Loads a day, its tasks and their steps in one round trip.
  Future<DayBundle?> dayBundle(int dayNumber) async {
    final DayRow? day = await dayByNumber(dayNumber);
    if (day == null) return null;

    final query = _db.select(_db.tasks).join(<Join<HasResultSet, dynamic>>[
      innerJoin(_db.steps, _db.steps.taskId.equalsExp(_db.tasks.id)),
    ]);
    query
      ..where(_db.tasks.dayId.equals(day.id))
      ..orderBy(<OrderingTerm>[
        OrderingTerm.asc(_db.tasks.sortOrder),
        OrderingTerm.asc(_db.steps.sortOrder),
      ]);

    final List<TypedResult> rows = await query.get();
    final Map<String, List<StepRow>> stepsByTask = <String, List<StepRow>>{};
    final Map<String, TaskRow> tasksById = <String, TaskRow>{};

    for (final TypedResult row in rows) {
      final TaskRow task = row.readTable(_db.tasks);
      final StepRow step = row.readTable(_db.steps);
      tasksById[task.id] = task;
      stepsByTask.putIfAbsent(task.id, () => <StepRow>[]).add(step);
    }

    final List<BreakRow> breaks =
        await (_db.select(_db.breaks)..where((t) => t.dayId.equals(day.id))).get();

    return DayBundle(
      day: day,
      tasks: <TaskWithSteps>[
        for (final TaskRow task in tasksById.values)
          TaskWithSteps(task: task, steps: stepsByTask[task.id] ?? const <StepRow>[]),
      ],
      breaks: breaks,
    );
  }

  /// Planned totals per bucket, used to reconcile the template to the PDF.
  Future<({int attendance, int study, int questions})> plannedTotals() async {
    final List<TaskRow> tasks = await _db.select(_db.tasks).get();
    int attendance = 0;
    int study = 0;
    int questions = 0;
    for (final TaskRow task in tasks) {
      attendance += task.attendanceMinutes;
      study += task.studyMinutes;
      questions += task.questionMinutes;
    }
    return (attendance: attendance, study: study, questions: questions);
  }
}
