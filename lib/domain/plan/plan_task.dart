/// Task and step domain model for the hybrid task list (PRD section 5.4).
///
/// Pure Dart on purpose: no Flutter and no Drift imports. The Today list, the
/// day detail screen, focus sessions and achievements all read the same
/// roll-up from here, so "a task is complete when every step is complete" is
/// implemented exactly once.
import 'plan_progress.dart';

/// `tasks.type` values, mirrored from the template schema.
enum PlanTaskType {
  foundation('foundation'),
  lecture('lecture'),
  courseQuestions('course_questions');

  const PlanTaskType(this.wireValue);

  /// The value stored in `tasks.type`.
  final String wireValue;

  /// Foundation and lecture tasks are videos; only course-question tasks carry
  /// a `questions` step.
  bool get isVideo => this != PlanTaskType.courseQuestions;

  static PlanTaskType? tryParse(String? raw) {
    for (final PlanTaskType type in PlanTaskType.values) {
      if (type.wireValue == raw) return type;
    }
    return null;
  }

  static PlanTaskType parse(String raw) {
    final PlanTaskType? type = tryParse(raw);
    if (type == null) {
      throw ArgumentError.value(raw, 'raw', 'unknown plan task type');
    }
    return type;
  }
}

/// `user_task_states.status` values (PRD section 5.4).
enum PlanTaskStatus {
  notStarted('not_started'),
  inProgress('in_progress'),
  completed('completed'),
  postponed('postponed');

  const PlanTaskStatus(this.wireValue);

  /// The value stored in `user_task_states.status`.
  final String wireValue;

  bool get isDone => this == PlanTaskStatus.completed;

  static PlanTaskStatus? tryParse(String? raw) {
    for (final PlanTaskStatus status in PlanTaskStatus.values) {
      if (status.wireValue == raw) return status;
    }
    return null;
  }
}

/// One step of a task: attend the video, study it, or solve its questions.
class PlanStep {
  const PlanStep({
    required this.id,
    required this.kind,
    required this.minutes,
    required this.order,
    this.completed = false,
    this.suggestedStart,
    this.suggestedEnd,
  }) : assert(minutes >= 0, 'minutes cannot be negative');

  final String id;

  /// One of [ProgressStepKinds].
  final String kind;

  /// Exact integer minutes, never a rounded display string.
  final int minutes;

  /// 1-based position inside its task.
  final int order;

  /// Whether the user checked this step (user state, never template data).
  final bool completed;

  /// Suggested clock time (`HH:mm`) from the plan, for display only.
  final String? suggestedStart;
  final String? suggestedEnd;

  bool get isAttendance => kind == ProgressStepKinds.attend;
  bool get isStudy => kind == ProgressStepKinds.study;
  bool get isQuestions => kind == ProgressStepKinds.questions;

  PlanStep withCompleted(bool value) {
    if (value == completed) return this;
    return PlanStep(
      id: id,
      kind: kind,
      minutes: minutes,
      order: order,
      completed: value,
      suggestedStart: suggestedStart,
      suggestedEnd: suggestedEnd,
    );
  }
}

/// A task with its ordered steps, the unit the day list expands (PRD 5.4).
///
/// A task may be marked complete explicitly; that counts every step as done
/// without rewriting the user's step rows, so unchecking one step later does
/// not silently reopen the task (the caller decides the status).
class PlanTask {
  const PlanTask({
    required this.id,
    required this.dayNumber,
    required this.subjectKey,
    required this.title,
    required this.type,
    required this.steps,
    this.subjectName,
    this.groupTitle,
    this.suggestedStart,
    this.suggestedEnd,
    this.status = PlanTaskStatus.notStarted,
    this.postponedToDay,
    this.expanded = false,
  }) : assert(
         status != PlanTaskStatus.postponed || postponedToDay != null,
         'a postponed task needs a target day',
       );

  final String id;

  /// 1-based plan day this task belongs to. A postponed task keeps its
  /// original day and moves via [postponedToDay].
  final int dayNumber;

  final String subjectKey;
  final String? subjectName;

  /// The PDF "group" heading (chapter name).
  final String? groupTitle;

  final String title;
  final PlanTaskType type;
  final List<PlanStep> steps;
  final String? suggestedStart;
  final String? suggestedEnd;

  /// The user's explicit status; defaults to not started.
  final PlanTaskStatus status;

  /// Target day when [status] is [PlanTaskStatus.postponed].
  final int? postponedToDay;

  /// Whether the task row is expanded into its steps (UI state).
  final bool expanded;

  /// Steps ordered by [PlanStep.order], so display and next-step logic can
  /// never disagree with the plan.
  List<PlanStep> get stepsInOrder {
    final List<PlanStep> ordered = List<PlanStep>.of(steps)
      ..sort((PlanStep a, PlanStep b) => a.order.compareTo(b.order));
    return List<PlanStep>.unmodifiable(ordered);
  }

  int get plannedMinutes =>
      steps.fold<int>(0, (int sum, PlanStep step) => sum + step.minutes);

  int minutesFor(String kind) => steps.fold<int>(
    0,
    (int sum, PlanStep step) => step.kind == kind ? sum + step.minutes : sum,
  );

  int get completedStepCount =>
      steps.where((PlanStep step) => step.completed).length;

  /// A task with no steps is never complete: completion must be observable.
  bool get isComplete =>
      status == PlanTaskStatus.completed ||
      (steps.isNotEmpty && steps.every((PlanStep step) => step.completed));

  /// Completed minutes honour an explicit completion without touching steps.
  int get completedMinutes => isComplete
      ? plannedMinutes
      : steps.fold<int>(
          0,
          (int sum, PlanStep step) => step.completed ? sum + step.minutes : sum,
        );

  int get remainingMinutes {
    final int remaining = plannedMinutes - completedMinutes;
    return remaining < 0 ? 0 : remaining;
  }

  /// 0..1, safe for a task without steps.
  double get fraction {
    if (plannedMinutes <= 0) return 0;
    return (completedMinutes / plannedMinutes).clamp(0.0, 1.0).toDouble();
  }

  bool get hasStarted =>
      status == PlanTaskStatus.inProgress || completedStepCount > 0;

  /// The first step still to do, or `null` once the task is complete.
  PlanStep? get nextStep {
    if (isComplete) return null;
    for (final PlanStep step in stepsInOrder) {
      if (!step.completed) return step;
    }
    return null;
  }

  /// Returns the same instance when the id is unknown or nothing changed.
  PlanTask withStepCompletion(String stepId, bool completed) {
    bool changed = false;
    final List<PlanStep> updated = <PlanStep>[];
    for (final PlanStep step in steps) {
      if (step.id != stepId) {
        updated.add(step);
        continue;
      }
      updated.add(step.withCompleted(completed));
      changed = changed || step.completed != completed;
    }
    if (!changed) return this;
    return _copy(steps: updated);
  }

  /// Sets the explicit status. Passing a status other than
  /// [PlanTaskStatus.postponed] clears [postponedToDay], so restoring a task
  /// cannot leave a stale target day behind.
  PlanTask withStatus(PlanTaskStatus status, {int? postponedToDay}) {
    assert(
      status != PlanTaskStatus.postponed || postponedToDay != null,
      'a postponed task needs a target day',
    );
    return _copy(
      status: status,
      postponedToDay: status == PlanTaskStatus.postponed
          ? postponedToDay
          : null,
    );
  }

  PlanTask toggleExpanded() => _copy(expanded: !expanded);

  /// Feeds the hours engine without inventing a second set of bucket rules.
  ProgressTaskInput toProgressTask() => ProgressTaskInput(
    id: id,
    completed: status == PlanTaskStatus.completed,
    steps: <ProgressStepInput>[
      for (final PlanStep step in stepsInOrder)
        ProgressStepInput(
          id: step.id,
          kind: step.kind,
          minutes: step.minutes,
          completed: step.completed,
        ),
    ],
  );

  PlanTask _copy({
    List<PlanStep>? steps,
    PlanTaskStatus? status,
    int? postponedToDay,
    bool? expanded,
  }) {
    return PlanTask(
      id: id,
      dayNumber: dayNumber,
      subjectKey: subjectKey,
      subjectName: subjectName,
      groupTitle: groupTitle,
      title: title,
      type: type,
      steps: steps ?? this.steps,
      suggestedStart: suggestedStart,
      suggestedEnd: suggestedEnd,
      status: status ?? this.status,
      postponedToDay: status == null ? this.postponedToDay : postponedToDay,
      expanded: expanded ?? this.expanded,
    );
  }
}
