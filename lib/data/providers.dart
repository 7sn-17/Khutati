import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_assets.dart';
import '../domain/plan/plan_calendar.dart';
import '../domain/plan/plan_dataset.dart';
import 'database/app_database.dart';
import 'database/database_provider.dart';
import 'repositories/plan_progress_repository.dart';
import 'repositories/template_repository.dart';
import 'repositories/user_state_repository.dart';

/// Single wiring point for the data layer. Screens depend on repositories, not
/// on Drift, so the plan engine can be tested without Flutter (PRD section 7).
final Provider<TemplateRepository> templateRepositoryProvider =
    Provider<TemplateRepository>((Ref ref) {
      return TemplateRepository(ref.watch(appDatabaseProvider));
    });

final Provider<UserStateRepository> userStateRepositoryProvider =
    Provider<UserStateRepository>((Ref ref) {
      return UserStateRepository(ref.watch(appDatabaseProvider));
    });

final Provider<PlanProgressRepository> planProgressRepositoryProvider =
    Provider<PlanProgressRepository>((Ref ref) {
      return PlanProgressRepository(
        ref.watch(appDatabaseProvider),
        ref.watch(templateRepositoryProvider),
      );
    });

/// The imported plan row; completes after the bootstrap in `main()`.
final FutureProvider<PlanRow?> activePlanProvider = FutureProvider<PlanRow?>((
  Ref ref,
) {
  return ref.watch(templateRepositoryProvider).activePlan();
});

/// Date mapping derived from the bundled dataset, never hard-coded in a screen.
///
/// The plan row is only used as the "is imported" check. Its `start_date` is a
/// SQLite instant, so reading it after a timezone change can land on the
/// previous/next local day. The dataset's date text is timezone-free, which is
/// what keeps Day 1 fixed at 19 November.
final FutureProvider<PlanCalendar?> planCalendarProvider =
    FutureProvider<PlanCalendar?>((Ref ref) async {
      final PlanRow? plan = await ref.watch(activePlanProvider.future);
      if (plan == null) return null;

      final PlanDataset dataset = PlanDataset.parse(
        await rootBundle.loadString(kPlanAsset),
      );
      return PlanCalendar(
        startDate: dataset.meta.startDate,
        totalDays: dataset.meta.totalDays,
      );
    });
