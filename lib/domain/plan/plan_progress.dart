import 'step_progress.dart';

/// Progress and hours engine (PRD section 5.7).
///
/// Pure Dart on purpose: the same numbers drive the Today ring, the Plan
/// screen, Achievements and the completion screen, and none of them may invent
/// their own arithmetic.
abstract final class ProgressStepKinds {
  static const String attend = 'attend';
  static const String study = 'study';
  static const String questions = 'questions';
}

/// One step as the engine sees it: duration plus whether the user checked it.
class ProgressStepInput {
  const ProgressStepInput({
    required this.id,
    required this.kind,
    required this.minutes,
    required this.completed,
    this.progress = StepProgress.notStarted,
  });

  final String id;
  final String kind;
  final int minutes;
  final bool completed;
  final StepProgress progress;

  bool get isAttendance => kind == ProgressStepKinds.attend;
  bool get isStudy => kind == ProgressStepKinds.study;
  bool get isQuestions => kind == ProgressStepKinds.questions;

  /// [progress] wins; a bare `completed: true` still counts as fully done so
  /// callers that only know the boolean keep their old numbers.
  StepProgress get effectiveProgress =>
      progress != StepProgress.notStarted
          ? progress
          : completed
          ? StepProgress.completed
          : StepProgress.notStarted;
}

class ProgressTaskInput {
  const ProgressTaskInput({
    required this.id,
    required this.steps,
    this.completed = false,
  });

  final String id;
  final List<ProgressStepInput> steps;

  /// A task may be marked complete explicitly (long-press / menu). That counts
  /// every step as done without rewriting the user's step rows.
  final bool completed;

  int get plannedMinutes => steps.fold<int>(
    0,
    (int sum, ProgressStepInput step) => sum + step.minutes,
  );

  bool get isComplete =>
      completed ||
      (steps.isNotEmpty &&
          steps.every(
            (ProgressStepInput s) => s.effectiveProgress.isComplete,
          ));
}

/// Immutable snapshot of progress for a day, a subject or the whole plan.
class PlanProgress {
  const PlanProgress._({
    required this.plannedMinutes,
    required this.completedMinutes,
    required this.plannedTasks,
    required this.completedTasks,
    required this.plannedSteps,
    required this.completedSteps,
    required this.partialSteps,
    required this.plannedMinutesByKind,
    required this.completedMinutesByKind,
  });

  static const PlanProgress empty = PlanProgress._(
    plannedMinutes: 0,
    completedMinutes: 0,
    plannedTasks: 0,
    completedTasks: 0,
    plannedSteps: 0,
    completedSteps: 0,
    partialSteps: 0,
    plannedMinutesByKind: <String, int>{},
    completedMinutesByKind: <String, int>{},
  );

  factory PlanProgress.of(Iterable<ProgressTaskInput> tasks) {
    int plannedMinutes = 0;
    int completedMinutes = 0;
    int plannedTasks = 0;
    int completedTasks = 0;
    int plannedSteps = 0;
    int completedSteps = 0;
    int partialSteps = 0;
    final Map<String, int> plannedByKind = <String, int>{};
    final Map<String, int> completedByKind = <String, int>{};

    for (final ProgressTaskInput task in tasks) {
      plannedTasks += 1;
      final bool done = task.isComplete;
      if (done) completedTasks += 1;

      for (final ProgressStepInput step in task.steps) {
        plannedSteps += 1;
        plannedMinutes += step.minutes;
        plannedByKind.update(
          step.kind,
          (int value) => value + step.minutes,
          ifAbsent: () => step.minutes,
        );

        // An explicitly completed task counts every step as done.
        final StepProgress progress = done
            ? StepProgress.completed
            : step.effectiveProgress;
        if (progress != StepProgress.notStarted) {
          if (progress.isComplete) {
            completedSteps += 1;
          }
          if (progress.isPartial) {
            partialSteps += 1;
            // Both half states (up and down) credit half the step's minutes.
            // Treating partialDown as complete inflated today's completed
            // minutes and made the summary jump after the third tap.
            completedMinutes += step.minutes ~/ 2;
            completedByKind.update(
              step.kind,
              (int value) => value + step.minutes ~/ 2,
              ifAbsent: () => step.minutes ~/ 2,
            );
          } else {
            completedMinutes += step.minutes;
            completedByKind.update(
              step.kind,
              (int value) => value + step.minutes,
              ifAbsent: () => step.minutes,
            );
          }
        }
      }
    }

    return PlanProgress._(
      plannedMinutes: plannedMinutes,
      completedMinutes: completedMinutes,
      plannedTasks: plannedTasks,
      completedTasks: completedTasks,
      plannedSteps: plannedSteps,
      completedSteps: completedSteps,
      partialSteps: partialSteps,
      plannedMinutesByKind: Map<String, int>.unmodifiable(plannedByKind),
      completedMinutesByKind: Map<String, int>.unmodifiable(completedByKind),
    );
  }

  /// Sums several snapshots (for example the seven days of a week).
  factory PlanProgress.combine(Iterable<PlanProgress> parts) {
    int plannedMinutes = 0;
    int completedMinutes = 0;
    int plannedTasks = 0;
    int completedTasks = 0;
    int plannedSteps = 0;
    int completedSteps = 0;
    int partialSteps = 0;
    final Map<String, int> plannedByKind = <String, int>{};
    final Map<String, int> completedByKind = <String, int>{};

    for (final PlanProgress part in parts) {
      plannedMinutes += part.plannedMinutes;
      completedMinutes += part.completedMinutes;
      plannedTasks += part.plannedTasks;
      completedTasks += part.completedTasks;
      plannedSteps += part.plannedSteps;
      completedSteps += part.completedSteps;
      partialSteps += part.partialSteps;
      part.plannedMinutesByKind.forEach((String kind, int minutes) {
        plannedByKind.update(
          kind,
          (int v) => v + minutes,
          ifAbsent: () => minutes,
        );
      });
      part.completedMinutesByKind.forEach((String kind, int minutes) {
        completedByKind.update(
          kind,
          (int v) => v + minutes,
          ifAbsent: () => minutes,
        );
      });
    }

    return PlanProgress._(
      plannedMinutes: plannedMinutes,
      completedMinutes: completedMinutes,
      plannedTasks: plannedTasks,
      completedTasks: completedTasks,
      plannedSteps: plannedSteps,
      completedSteps: completedSteps,
      partialSteps: partialSteps,
      plannedMinutesByKind: Map<String, int>.unmodifiable(plannedByKind),
      completedMinutesByKind: Map<String, int>.unmodifiable(completedByKind),
    );
  }

  final int plannedMinutes;
  final int completedMinutes;
  final int plannedTasks;
  final int completedTasks;
  final int plannedSteps;
  final int completedSteps;
  final int partialSteps;
  final Map<String, int> plannedMinutesByKind;
  final Map<String, int> completedMinutesByKind;

  int get remainingMinutes {
    final int remaining = plannedMinutes - completedMinutes;
    return remaining < 0 ? 0 : remaining;
  }

  /// 0..1, safe for an empty plan.
  double get fraction {
    if (plannedMinutes <= 0) return 0;
    return (completedMinutes / plannedMinutes).clamp(0.0, 1.0).toDouble();
  }

  bool get isComplete => plannedTasks > 0 && completedTasks == plannedTasks;

  bool get hasStarted => completedSteps > 0 || completedTasks > 0;

  int get remainingTasks {
    final int remaining = plannedTasks - completedTasks;
    return remaining < 0 ? 0 : remaining;
  }

  int get remainingSteps {
    final int remaining = plannedSteps - completedSteps;
    return remaining < 0 ? 0 : remaining;
  }

  int plannedMinutesFor(String kind) => plannedMinutesByKind[kind] ?? 0;

  int completedMinutesFor(String kind) => completedMinutesByKind[kind] ?? 0;

  /// Hours as a decimal, used by achievements and the weekly chart.
  double get plannedHours => plannedMinutes / 60;
  double get completedHours => completedMinutes / 60;
  double get remainingHours => remainingMinutes / 60;

  double fractionFor(String kind) {
    final int planned = plannedMinutesFor(kind);
    if (planned <= 0) return 0;
    return (completedMinutesFor(kind) / planned).clamp(0.0, 1.0).toDouble();
  }
}
