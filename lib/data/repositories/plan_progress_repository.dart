import '../../domain/plan/plan_progress.dart';
import '../../domain/plan/step_progress.dart';
import '../database/app_database.dart';
import '../database/tables.dart';
import 'template_repository.dart';

/// Bridges Drift rows to the pure progress engine.
///
/// The engine never sees Drift; this repository is the only place where template
/// rows and user state are joined.
class PlanProgressRepository {
  PlanProgressRepository(this._db, this._template);

  final AppDatabase _db;
  final TemplateRepository _template;

  /// Progress for one plan day, or [PlanProgress.empty] outside the plan.
  Future<PlanProgress> dayProgress(int dayNumber) async {
    final DayRow? day = await _template.dayByNumber(dayNumber);
    if (day == null) return PlanProgress.empty;

    final _LoadedPlan plan = await _load();
    return PlanProgress.of(
      plan.tasks
          .where(
            (TaskRow task) =>
                task.dayId == day.id &&
                !plan.postponedTaskIds.contains(task.id),
          )
          .map(plan.inputFor),
    );
  }

  /// Progress across all 68 days — the number Achievements and Today's level
  /// card must agree on.
  Future<PlanProgress> overallProgress() async {
    final _LoadedPlan plan = await _load();
    return PlanProgress.of(
      plan.tasks
          .where(
            (TaskRow task) => !plan.postponedTaskIds.contains(task.id),
          )
          .map(plan.inputFor),
    );
  }

  /// Progress for every plan day, keyed by 1-based day number.
  ///
  /// Today needs a streak and overdue totals, which would otherwise mean one
  /// query per day. This loads the plan once and groups it in memory.
  Future<Map<int, PlanProgress>> progressByDay() async {
    final List<DayRow> days = await _template.allDays();
    final _LoadedPlan plan = await _load();

    final Map<String, int> numberByDayId = <String, int>{
      for (final DayRow day in days) day.id: day.dayNumber,
    };
    final Map<int, List<ProgressTaskInput>> grouped =
        <int, List<ProgressTaskInput>>{};

    for (final TaskRow task in plan.tasks) {
      if (plan.postponedTaskIds.contains(task.id)) continue;
      final int? dayNumber = numberByDayId[task.dayId];
      if (dayNumber == null) continue;
      grouped
          .putIfAbsent(dayNumber, () => <ProgressTaskInput>[])
          .add(plan.inputFor(task));
    }

    return <int, PlanProgress>{
      for (final DayRow day in days)
        day.dayNumber: PlanProgress.of(
          grouped[day.dayNumber] ?? const <ProgressTaskInput>[],
        ),
    };
  }

  /// Work still open on study days before [dayNumber] (PRD 5.3 overdue).
  Future<({int tasks, int minutes})> overdueBefore(int dayNumber) async {
    final Map<int, PlanProgress> byDay = await progressByDay();
    int tasks = 0;
    int minutes = 0;

    for (final MapEntry<int, PlanProgress> entry in byDay.entries) {
      if (entry.key >= dayNumber) continue;
      final PlanProgress progress = entry.value;
      // Rest days have no tasks and are never overdue.
      if (progress.plannedTasks == 0 || progress.isComplete) continue;
      tasks += progress.remainingTasks;
      minutes += progress.remainingMinutes;
    }

    return (tasks: tasks, minutes: minutes);
  }

  /// Per-subject totals for the Achievements screen (PRD 5.7).
  Future<Map<String, PlanProgress>> progressBySubject() async {
    final _LoadedPlan plan = await _load();
    final Map<String, List<TaskRow>> grouped = <String, List<TaskRow>>{};
    for (final TaskRow task in plan.tasks) {
      if (plan.postponedTaskIds.contains(task.id)) continue;
      grouped.putIfAbsent(task.subjectId, () => <TaskRow>[]).add(task);
    }
    return <String, PlanProgress>{
      for (final MapEntry<String, List<TaskRow>> entry in grouped.entries)
        entry.key: PlanProgress.of(entry.value.map(plan.inputFor)),
    };
  }

  /// Completed step ids for one task, used by the expandable task cards.
  Future<Set<String>> completedStepsForTask(String taskId) async {
    final List<UserStepStateRow> states = await (_db.select(
      _db.userStepStates,
    )..where((UserStepStates t) => t.completed.equals(true))).get();
    if (states.isEmpty) return <String>{};

    final List<StepRow> steps = await (_db.select(
      _db.steps,
    )..where((Steps t) => t.taskId.equals(taskId))).get();
    final Set<String> stepIds = <String>{
      for (final StepRow step in steps) step.id,
    };
    return <String>{
      for (final UserStepStateRow state in states)
        if (stepIds.contains(state.stepId)) state.stepId,
    };
  }

  Future<_LoadedPlan> _load() async {
    final List<TaskRow> taskRows = await _db.select(_db.tasks).get();
    final List<StepRow> stepRows = await _db.select(_db.steps).get();

    final Map<String, TaskRow> tasks = <String, TaskRow>{
      for (final TaskRow task in taskRows) task.id: task,
    };
    final Map<String, List<StepRow>> steps = <String, List<StepRow>>{};
    for (final StepRow step in stepRows) {
      steps.putIfAbsent(step.taskId, () => <StepRow>[]).add(step);
    }

    final List<UserStepStateRow> stepStates = await _db
        .select(_db.userStepStates)
        .get();
    final List<UserTaskStateRow> taskStates = await _db
        .select(_db.userTaskStates)
        .get();

    final Set<String> postponedTaskIds = <String>{
      for (final UserTaskStateRow state in taskStates)
        if (state.status == 'postponed') state.taskId,
    };

    final Map<String, StepProgress> stepProgresses = <String, StepProgress>{};
    for (final UserStepStateRow state in stepStates) {
      final StepProgress stored = StepProgress.tryParse(state.progress);
      // Legacy rows only have `completed`; keep them fully done.
      stepProgresses[state.stepId] =
          stored == StepProgress.notStarted && state.completed
          ? StepProgress.completed
          : stored;
    }

    return _LoadedPlan(
      tasks: tasks.values.toList(growable: false),
      stepsByTask: steps,
      completedStepIds: <String>{
        for (final UserStepStateRow state in stepStates)
          if (state.completed) state.stepId,
      },
      completedTaskIds: <String>{
        for (final UserTaskStateRow state in taskStates)
          if (state.status == 'completed') state.taskId,
      },
      postponedTaskIds: postponedTaskIds,
      stepProgresses: stepProgresses,
    );
  }
}

class _LoadedPlan {
  const _LoadedPlan({
    required this.tasks,
    required this.stepsByTask,
    required this.completedStepIds,
    required this.completedTaskIds,
    required this.postponedTaskIds,
    required this.stepProgresses,
  });

  final List<TaskRow> tasks;
  final Map<String, List<StepRow>> stepsByTask;
  final Set<String> completedStepIds;
  final Set<String> completedTaskIds;
  final Set<String> postponedTaskIds;
  final Map<String, StepProgress> stepProgresses;

  ProgressTaskInput inputFor(TaskRow task) {
    final List<StepRow> rows = stepsByTask[task.id] ?? const <StepRow>[];
    final List<ProgressStepInput> steps = rows.isEmpty
        ? <ProgressStepInput>[
            // Defensive: an imported task always has steps, but a hand-edited
            // database (or a future user task) may not.
            ProgressStepInput(
              id: '${task.id}-total',
              kind: ProgressStepKinds.study,
              minutes:
                  task.attendanceMinutes +
                  task.studyMinutes +
                  task.questionMinutes,
              completed: false,
            ),
          ]
        : <ProgressStepInput>[
            for (final StepRow step in rows)
              ProgressStepInput(
                id: step.id,
                kind: step.kind,
                minutes: step.minutes,
                completed: completedStepIds.contains(step.id),
                progress:
                    stepProgresses[step.id] ?? StepProgress.notStarted,
              ),
          ];

    return ProgressTaskInput(
      id: task.id,
      steps: steps,
      completed: completedTaskIds.contains(task.id),
    );
  }
}
