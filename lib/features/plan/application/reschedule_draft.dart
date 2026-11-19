import '../../../data/repositories/schedule_repository.dart';
import '../../../domain/plan/schedule_engine.dart';

/// The pending manual placements of the rescheduling screen.
///
/// Immutable on purpose: every edit returns a new draft and remembers the one
/// before it, so an invalid combination can be rejected without leaving the
/// screen in a half-applied state, and «تراجع» is a real undo rather than a
/// guess.
class RescheduleDraft {
  RescheduleDraft(this.base)
    : _entries = const <String, ScheduleOverrideInput>{},
      _history = const <Map<String, ScheduleOverrideInput>>[];

  const RescheduleDraft._(this.base, this._entries, this._history);

  /// The schedule as it is saved today. Kept so an empty draft still has
  /// something to render.
  final ScheduleSnapshot base;

  final Map<String, ScheduleOverrideInput> _entries;
  final List<Map<String, ScheduleOverrideInput>> _history;

  Map<String, ScheduleOverrideInput> get entries =>
      Map<String, ScheduleOverrideInput>.unmodifiable(_entries);

  int get count => _entries.length;
  bool get isEmpty => _entries.isEmpty;
  bool get canUndo => _history.isNotEmpty;

  /// Places [taskId] on [toDay] at [position] (1-based), optionally pinning its
  /// start clock.
  RescheduleDraft move(
    String taskId, {
    required int toDay,
    int? position,
    String? startClock,
  }) {
    final Map<String, ScheduleOverrideInput> next =
        Map<String, ScheduleOverrideInput>.of(_entries)
          ..[taskId] = ScheduleOverrideInput(
            dayNumber: toDay,
            position: position,
            startClock: startClock,
          );
    return RescheduleDraft._(base, next, <Map<String, ScheduleOverrideInput>>[
      ..._history,
      _entries,
    ]);
  }

  /// Returns the previous draft, or `null` at the start of the history.
  RescheduleDraft? undo() {
    if (_history.isEmpty) return null;
    return RescheduleDraft._(
      base,
      _history.last,
      _history.sublist(0, _history.length - 1),
    );
  }

  RescheduleDraft cleared() {
    return RescheduleDraft._(
      base,
      const <String, ScheduleOverrideInput>{},
      const <Map<String, ScheduleOverrideInput>>[],
    );
  }

  /// 1-based position [taskId] would take after moving [delta] slots inside
  /// [tasks], or `null` when the move leaves the day.
  static int? targetPosition(
    List<ScheduledTask> tasks,
    String taskId,
    int delta,
  ) {
    final int index = tasks.indexWhere(
      (ScheduledTask task) => task.task.id == taskId,
    );
    if (index < 0) return null;
    final int target = index + delta;
    if (target < 0 || target >= tasks.length) return null;
    return target + 1;
  }
}
