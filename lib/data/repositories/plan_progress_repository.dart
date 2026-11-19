import '../../domain/plan/plan_progress.dart';
import '../../domain/plan/step_progress.dart';
import '../database/app_database.dart';
import 'schedule_repository.dart';

/// Bridges Drift user state to the pure progress engine.
///
/// The effective task-to-day mapping comes from a [ScheduleSnapshot], never
/// from `tasks.day_id` directly. That is what makes Plan, Today, Achievements
/// and overdue counts agree after a practical-day change.
class PlanProgressRepository {
  PlanProgressRepository(this._db);

  final AppDatabase _db;

  /// Progress for one effective plan day, or [PlanProgress.empty] outside the
  /// plan.
  Future<PlanProgress> dayProgress(
    int dayNumber,
    ScheduleSnapshot schedule,
  ) async {
    final _LoadedPlan plan = await _load(schedule);
    return PlanProgress.of(schedule.tasksForDay(dayNumber).map(plan.inputFor));
  }

  /// Progress across all 68 days — the number Achievements and Today's level
  /// card must agree on.
  Future<PlanProgress> overallProgress(ScheduleSnapshot schedule) async {
    final _LoadedPlan plan = await _load(schedule);
    return PlanProgress.of(schedule.tasks.map(plan.inputFor));
  }

  /// Progress for every effective plan day, keyed by 1-based day number.
  ///
  /// Today needs a streak and overdue totals, which would otherwise mean one
  /// query per day. This loads the plan once and groups it in memory.
  Future<Map<int, PlanProgress>> progressByDay(
    ScheduleSnapshot schedule,
  ) async {
    final _LoadedPlan plan = await _load(schedule);
    return <int, PlanProgress>{
      for (final ScheduledDay day in schedule.days)
        day.dayNumber: PlanProgress.of(
          schedule.tasksForDay(day.dayNumber).map(plan.inputFor),
        ),
    };
  }

  /// Work still open on study days before [dayNumber] (PRD 5.3 overdue).
  Future<({int tasks, int minutes})> overdueBefore(
    int dayNumber,
    ScheduleSnapshot schedule,
  ) async {
    final Map<int, PlanProgress> byDay = await progressByDay(schedule);
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
  Future<Map<String, PlanProgress>> progressBySubject(
    ScheduleSnapshot schedule,
  ) async {
    final _LoadedPlan plan = await _load(schedule);
    final Map<String, List<ScheduledTask>> grouped =
        <String, List<ScheduledTask>>{};
    for (final ScheduledTask task in schedule.tasks) {
      grouped
          .putIfAbsent(task.task.subjectId, () => <ScheduledTask>[])
          .add(task);
    }
    return <String, PlanProgress>{
      for (final MapEntry<String, List<ScheduledTask>> entry in grouped.entries)
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

  Future<_LoadedPlan> _load(ScheduleSnapshot schedule) async {
    final List<UserStepStateRow> stepStates = await _db
        .select(_db.userStepStates)
        .get();
    final List<UserTaskStateRow> taskStates = await _db
        .select(_db.userTaskStates)
        .get();

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
      completedStepIds: <String>{
        for (final UserStepStateRow state in stepStates)
          if (state.completed) state.stepId,
      },
      completedTaskIds: <String>{
        for (final UserTaskStateRow state in taskStates)
          if (state.status == 'completed') state.taskId,
      },
      stepProgresses: stepProgresses,
    );
  }
}

class _LoadedPlan {
  const _LoadedPlan({
    required this.completedStepIds,
    required this.completedTaskIds,
    required this.stepProgresses,
  });

  final Set<String> completedStepIds;
  final Set<String> completedTaskIds;
  final Map<String, StepProgress> stepProgresses;

  ProgressTaskInput inputFor(ScheduledTask task) {
    final List<StepRow> rows = task.steps;
    final List<ProgressStepInput> steps = rows.isEmpty
        ? <ProgressStepInput>[
            // Defensive: an imported task always has steps, but a hand-edited
            // database (or a future user task) may not.
            ProgressStepInput(
              id: '${task.task.id}-total',
              kind: ProgressStepKinds.study,
              minutes:
                  task.task.attendanceMinutes +
                  task.task.studyMinutes +
                  task.task.questionMinutes,
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
                progress: stepProgresses[step.id] ?? StepProgress.notStarted,
              ),
          ];

    return ProgressTaskInput(
      id: task.task.id,
      steps: steps,
      completed: completedTaskIds.contains(task.task.id),
    );
  }
}
