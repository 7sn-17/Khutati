/// Actual time comes from focus sessions only (PRD sections 5.6 and 5.7).
///
/// The Phase 4 timer writes `focus_sessions` rows; this pure aggregator turns
/// them into the numbers the task list and analytics compare with planned
/// time. Nothing here rounds to the planned duration: a session that ended
/// early still counts as the real seconds the user studied.
abstract final class FocusPhases {
  static const String focus = 'focus';
  static const String breakTime = 'break';
}

/// One recorded session, reduced to what the engines need.
class FocusSessionInput {
  const FocusSessionInput({
    required this.actualSeconds,
    this.phase = FocusPhases.focus,
    this.taskId,
    this.stepId,
    this.startedAt,
  }) : assert(actualSeconds >= 0, 'actualSeconds cannot be negative');

  /// Real elapsed seconds, not the planned duration.
  final int actualSeconds;
  final String phase;
  final String? taskId;
  final String? stepId;
  final DateTime? startedAt;

  bool get isFocus => phase == FocusPhases.focus;
}

/// Study time actually spent, split from break time.
class ActualTime {
  const ActualTime._({
    required this.focusSeconds,
    required this.breakSeconds,
    required this.focusSecondsByTask,
  });

  static const ActualTime none = ActualTime._(
    focusSeconds: 0,
    breakSeconds: 0,
    focusSecondsByTask: <String, int>{},
  );

  factory ActualTime.of(Iterable<FocusSessionInput> sessions) {
    int focusSeconds = 0;
    int breakSeconds = 0;
    final Map<String, int> byTask = <String, int>{};

    for (final FocusSessionInput session in sessions) {
      if (!session.isFocus) {
        breakSeconds += session.actualSeconds;
        continue;
      }
      focusSeconds += session.actualSeconds;
      final String? taskId = session.taskId;
      if (taskId != null) {
        byTask.update(
          taskId,
          (int value) => value + session.actualSeconds,
          ifAbsent: () => session.actualSeconds,
        );
      }
    }

    return ActualTime._(
      focusSeconds: focusSeconds,
      breakSeconds: breakSeconds,
      focusSecondsByTask: Map<String, int>.unmodifiable(byTask),
    );
  }

  /// Sums several aggregates, for example the days of a week.
  factory ActualTime.combine(Iterable<ActualTime> parts) {
    int focusSeconds = 0;
    int breakSeconds = 0;
    final Map<String, int> byTask = <String, int>{};

    for (final ActualTime part in parts) {
      focusSeconds += part.focusSeconds;
      breakSeconds += part.breakSeconds;
      part.focusSecondsByTask.forEach((String taskId, int seconds) {
        byTask.update(
          taskId,
          (int value) => value + seconds,
          ifAbsent: () => seconds,
        );
      });
    }

    return ActualTime._(
      focusSeconds: focusSeconds,
      breakSeconds: breakSeconds,
      focusSecondsByTask: Map<String, int>.unmodifiable(byTask),
    );
  }

  final int focusSeconds;
  final int breakSeconds;

  /// Focus seconds per task id, for planned-versus-actual per task.
  final Map<String, int> focusSecondsByTask;

  bool get hasFocusTime => focusSeconds > 0;

  /// Whole minutes, truncated for display; use [focusSeconds] for exact math.
  int get focusMinutes => focusSeconds ~/ 60;
  int get breakMinutes => breakSeconds ~/ 60;
  double get focusHours => focusSeconds / 3600;

  int focusSecondsForTask(String taskId) => focusSecondsByTask[taskId] ?? 0;

  int focusMinutesForTask(String taskId) => focusSecondsForTask(taskId) ~/ 60;
}
