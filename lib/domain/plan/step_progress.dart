/// Progress state for one step, supporting the four-tap workflow.
///
/// The two half states are deliberately distinct values in SQLite:
///
/// * [partialUp] (code 1) means the next tap completes the step.
/// * [partialDown] (code 3) means the next tap clears the step.
///
/// Persisting both is what keeps the cycle stable across a process restart.
/// Collapsing them into one "partial" value made the third and fourth tap both
/// land on 50% after reopening the app.
enum StepProgress {
  notStarted(0),
  partialUp(1),
  completed(2),
  partialDown(3);

  const StepProgress(this.code);

  final int code;

  bool get isAtLeastPartial =>
      this == StepProgress.partialUp ||
      this == StepProgress.partialDown ||
      this == StepProgress.completed;

  bool get isComplete => this == StepProgress.completed;

  /// Halfway state, whether going up or coming back down.
  bool get isPartial =>
      this == StepProgress.partialUp || this == StepProgress.partialDown;

  /// Fraction of the step's planned minutes that is credited.
  double get fraction => switch (this) {
        StepProgress.notStarted => 0,
        StepProgress.partialUp || StepProgress.partialDown => 0.5,
        StepProgress.completed => 1,
      };

  /// The strict loop: 0% -> 50% -> 100% -> 50% -> 0% -> ...
  StepProgress next() {
    switch (this) {
      case StepProgress.notStarted:
        return StepProgress.partialUp;
      case StepProgress.partialUp:
        return StepProgress.completed;
      case StepProgress.completed:
        return StepProgress.partialDown;
      case StepProgress.partialDown:
        return StepProgress.notStarted;
    }
  }

  /// Kept as the old call site name so the state machine has one public path.
  StepProgress nextWithinSession() => next();

  /// Unknown integers (for example a row written by a newer build) fall back
  /// to [notStarted] instead of throwing. Code 1 is read as [partialUp], which
  /// is the value every older build wrote for its single half state.
  static StepProgress tryParse(int raw) {
    for (final StepProgress value in values) {
      if (value.code == raw) return value;
    }
    return StepProgress.notStarted;
  }
}
