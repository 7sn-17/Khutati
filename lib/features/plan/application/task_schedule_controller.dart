import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';

/// Override management shared by the settings screens and their tests.
///
/// Placement itself goes through [ScheduleRepository.previewOverrides] /
/// [commitOverrides] so a whole draft is validated and saved atomically; this
/// controller only owns the "forget my manual placement" actions.
class TaskScheduleActions {
  TaskScheduleActions(this._ref);

  final Ref _ref;

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
