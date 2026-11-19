import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../domain/plan/plan_calendar.dart';
import '../../../domain/plan/practical_weekdays.dart';

class PracticalDaysSettings {
  const PracticalDaysSettings({required this.selected, required this.isCustom});

  final List<int> selected;
  final bool isCustom;
}

/// Live view of the persisted setting. A cloud pull writes the same
/// `app_settings` row, so Settings and both tabs observe one value.
final StreamProvider<PracticalDaysSettings> practicalDaysSettingsProvider =
    StreamProvider<PracticalDaysSettings>((Ref ref) {
      final ScheduleRepository repository = ref.watch(
        scheduleRepositoryProvider,
      );
      return repository.watchPracticalWeekdays().map(
        (List<int>? custom) => PracticalDaysSettings(
          selected: List<int>.unmodifiable(
            custom ?? PracticalWeekdays.original,
          ),
          isCustom: custom != null,
        ),
      );
    });

/// Actions shared by the Settings section and its confirmation dialog.
class PracticalDaysActions {
  PracticalDaysActions(this._ref);

  final Ref _ref;

  Future<SchedulePreview> preview(Iterable<int> weekdays) async {
    final PlanCalendar? calendar = await _ref.read(planCalendarProvider.future);
    if (calendar == null) {
      throw StateError('plan calendar is not ready');
    }
    return _ref.read(scheduleRepositoryProvider).preview(calendar, weekdays);
  }

  Future<void> save(Iterable<int> weekdays) async {
    final PlanCalendar? calendar = await _ref.read(planCalendarProvider.future);
    if (calendar == null) {
      throw StateError('plan calendar is not ready');
    }
    await _ref.read(scheduleRepositoryProvider).save(calendar, weekdays);
  }

  Future<void> reset() async {
    final PlanCalendar? calendar = await _ref.read(planCalendarProvider.future);
    if (calendar == null) {
      throw StateError('plan calendar is not ready');
    }
    await _ref.read(scheduleRepositoryProvider).reset(calendar);
  }
}

final Provider<PracticalDaysActions> practicalDaysActionsProvider =
    Provider<PracticalDaysActions>((Ref ref) {
      return PracticalDaysActions(ref);
    });
