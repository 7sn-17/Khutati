/// Progress state for one step, supporting a two-tap (partial then complete)
/// workflow. Stored in `user_step_states.progress` as a small integer and read
/// by both Today and Plan so the two tabs always agree.
enum StepProgress {
  notStarted(0),
  partial(1),
  completed(2);

  const StepProgress(this.code);

  final int code;

  bool get isAtLeastPartial =>
      this == StepProgress.partial || this == StepProgress.completed;

  bool get isComplete => this == StepProgress.completed;

  /// One tap forward; the final tap reaches completed.
  StepProgress nextWithinSession() {
    switch (this) {
      case StepProgress.notStarted:
        return StepProgress.partial;
      case StepProgress.partial:
        return StepProgress.completed;
      case StepProgress.completed:
        return StepProgress.completed;
    }
  }

  /// Unknown integers (for example a row written by a newer build) fall back
  /// to [notStarted] instead of throwing.
  static StepProgress tryParse(int raw) {
    for (final StepProgress value in values) {
      if (value.code == raw) return value;
    }
    return StepProgress.notStarted;
  }
}
