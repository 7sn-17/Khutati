import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../domain/plan/plan_calendar.dart';

/// Manual scheduling actions shared by the task sheet and its tests.
class TaskScheduleActions {
  TaskScheduleActions(this._ref);

  final Ref _ref;

  Future<PlanCalendar> _calendar() async {
    final PlanCalendar? calendar = await _ref.read(planCalendarProvider.future);
    if (calendar == null) {
      throw StateError('plan calendar is not ready');
    }
    return calendar;
  }

  Future<TaskMovePreview> preview({
    required String taskId,
    int? dayNumber,
    int? position,
    String? startClock,
  }) async {
    return _ref
        .read(scheduleRepositoryProvider)
        .previewMove(
          await _calendar(),
          taskId: taskId,
          dayNumber: dayNumber,
          position: position,
          startClock: startClock,
        );
  }

  Future<TaskMovePreview> commit({
    required String taskId,
    int? dayNumber,
    int? position,
    String? startClock,
  }) async {
    return _ref
        .read(scheduleRepositoryProvider)
        .commitMove(
          await _calendar(),
          taskId: taskId,
          dayNumber: dayNumber,
          position: position,
          startClock: startClock,
        );
  }

  Future<void> clear(String taskId) {
    return _ref.read(scheduleRepositoryProvider).clearOverride(taskId);
  }

  Future<void> clearAll() {
    return _ref.read(scheduleRepositoryProvider).clearAllOverrides();
  }
}

final Provider<TaskScheduleActions> taskScheduleActionsProvider =
    Provider<TaskScheduleActions>((Ref ref) {
      return TaskScheduleActions(ref);
    });
