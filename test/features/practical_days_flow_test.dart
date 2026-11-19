import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/data/database/app_database.dart';
import 'package:khutati/data/database/database_provider.dart';
import 'package:khutati/data/import/plan_importer.dart';
import 'package:khutati/data/providers.dart';
import 'package:khutati/data/repositories/schedule_repository.dart';
import 'package:khutati/data/repositories/user_state_repository.dart';
import 'package:khutati/domain/plan/plan_calendar.dart';
import 'package:khutati/domain/plan/plan_task.dart';
import 'package:khutati/domain/plan/practical_weekdays.dart';
import 'package:khutati/domain/plan/step_progress.dart';
import 'package:khutati/features/plan/application/plan_browser_controller.dart';
import 'package:khutati/features/plan/application/task_schedule_controller.dart';
import 'package:khutati/features/settings/application/practical_days_controller.dart';
import 'package:khutati/features/today/application/today_controller.dart';

/// End-to-end flow behind Settings → «أيام العملي».
///
/// The Settings dialog, the Plan tab and the Today tab are three views of one
/// `app_settings` row and one derived schedule. These tests drive the same
/// actions the dialog drives (preview → confirm → save, and reset) against a
/// real in-memory database, and assert that both tabs re-emit without any
/// manual invalidation, that tasks keep their ids, and that progress survives
/// the move.
void main() {
  late AppDatabase db;
  late PlanCalendar calendar;
  late ProviderContainer container;
  late UserStateRepository userState;

  setUp(() async {
    db = AppDatabase.memory();
    calendar = PlanCalendar(startDate: DateTime(2026, 11, 19), totalDays: 68);
    await PlanImporter(db)
        .ensureImported(File('khutati_plan_data.json').readAsStringSync());
    userState = UserStateRepository(db);
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        planCalendarProvider.overrideWith((Ref ref) async => calendar),
        // Friday 20 November 2026 is plan day 2, and a practical day in the
        // bundled template.
        todayClockProvider.overrideWith(
          (Ref ref) => Stream<DateTime>.value(DateTime(2026, 11, 20, 9)),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Waits for the next value of [provider] that satisfies [test].
  Future<T> waitFor<T>(
    ProviderListenable<AsyncValue<T>> provider,
    bool Function(T value) test,
  ) {
    final Completer<T> completer = Completer<T>();
    final ProviderSubscription<AsyncValue<T>> subscription = container
        .listen<AsyncValue<T>>(provider, (
          AsyncValue<T>? previous,
          AsyncValue<T> next,
        ) {
          final T? value = next.valueOrNull;
          if (value != null && test(value) && !completer.isCompleted) {
            completer.complete(value);
          }
        }, fireImmediately: true);
    return completer.future.whenComplete(subscription.close);
  }

  /// Day number of every task in a rendered plan, keyed by task id.
  Map<String, int> dayNumbersOf(PlanBrowserData data) {
    return <String, int>{
      for (final PlanDayData day in data.days)
        for (final PlanTask task in day.tasks) task.id: day.day.dayNumber,
    };
  }

  /// A task the new pair relocates. The partition keeps the number of study
  /// slots per week, so some tasks stay in their slot; the test picks one the
  /// preview actually moves instead of assuming a particular day changes.
  ScheduledTask firstMover(SchedulePreview preview, Map<String, int> before) {
    return preview.schedule.tasks.firstWhere(
      (ScheduledTask task) => before[task.task.id] != task.dayNumber,
      orElse: () => throw StateError('no task moved'),
    );
  }

  test('preview writes nothing and save updates both tabs at once', () async {
    final PracticalDaysActions actions = container.read(
      practicalDaysActionsProvider,
    );

    final PlanBrowserData before = (await container.read(
      planBrowserProvider.future,
    ))!;
    final PlanDayData friday = before.days[1];
    expect(friday.day.dayNumber, 2);
    expect(friday.day.isPractical, isTrue);
    expect(friday.tasks, isNotEmpty);

    // Tuesday 2 and Thursday 4 become the new practical pair.
    final SchedulePreview preview = await actions.preview(<int>[
      DateTime.tuesday,
      DateTime.thursday,
    ]);
    expect(preview.movedTasks, greaterThan(0));
    expect(preview.changedDays, greaterThan(0));

    final Map<String, int> beforeDays = dayNumbersOf(before);
    final ScheduledTask mover = firstMover(preview, beforeDays);
    final String movingTaskId = mover.task.id;
    final int originDay = beforeDays[movingTaskId]!;
    final int newDay = mover.dayNumber;
    final PlanTask movingTask = before.days[originDay - 1].tasks.firstWhere(
      (PlanTask task) => task.id == movingTaskId,
    );
    final String firstStepId = movingTask.steps.first.id;

    // A preview is a read: the stored setting is still the original pair.
    final PracticalDaysSettings untouched = await container.read(
      practicalDaysSettingsProvider.future,
    );
    expect(untouched.selected, PracticalWeekdays.original);
    expect(untouched.isCustom, isFalse);

    // Partial progress is recorded before the schedule changes.
    await userState.setStepCompleted(firstStepId, StepProgress.completed);

    // Both tabs are already listening; neither is invalidated by hand. Today
    // is read once first so its change stream exists before the write.
    final TodayData initialToday = (await container.read(
      todayDataProvider.future,
    ))!;
    expect(initialToday.day.type, 'practical');

    final Future<PlanBrowserData?> planChanged = waitFor<PlanBrowserData?>(
      planBrowserProvider,
      (PlanBrowserData? data) =>
          data != null &&
          data.days[originDay - 1].tasks.every(
            (PlanTask task) => task.id != movingTaskId,
          ) &&
          data.days[newDay - 1].tasks.any(
            (PlanTask task) => task.id == movingTaskId,
          ),
    );
    final Future<TodayData?> todayChanged = waitFor<TodayData?>(
      todayDataProvider,
      (TodayData? data) => data != null && data.day.type == 'normal',
    );
    await pumpEventQueue();

    await actions.save(<int>[DateTime.tuesday, DateTime.thursday]);

    final PlanBrowserData afterPlan = (await planChanged.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Plan did not re-emit'),
    ))!;
    final TodayData afterToday = (await todayChanged.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Today did not re-emit'),
    ))!;

    // Friday is now a normal study day in both tabs.
    expect(afterPlan.days[1].day.type, 'normal');
    expect(afterToday.dayNumber, 2);
    expect(afterToday.day.type, 'normal');

    // One source of truth: Today renders the same tasks, in the same order,
    // at the same clocks as the Plan tab.
    expect(
      afterToday.tasks.map((PlanTask task) => task.id),
      afterPlan.days[1].tasks.map((PlanTask task) => task.id),
    );
    expect(
      afterToday.tasks.map((PlanTask task) => task.suggestedStart),
      afterPlan.days[1].tasks.map((PlanTask task) => task.suggestedStart),
    );

    // The moved task kept its id, its step ids and its completed step.
    final PlanDayData movedDay = afterPlan.days[newDay - 1];
    final PlanTask movedTask = movedDay.tasks.firstWhere(
      (PlanTask task) => task.id == movingTaskId,
    );
    expect(
      movedTask.steps.map((PlanStep step) => step.id),
      movingTask.steps.map((PlanStep step) => step.id),
    );
    expect(
      movedTask.steps
          .firstWhere((PlanStep step) => step.id == firstStepId)
          .progress,
      StepProgress.completed,
    );
    expect(movedDay.progress.completedSteps, greaterThan(0));

    // The choice is persisted and queued for the cloud exactly once.
    final PracticalDaysSettings saved = await container.read(
      practicalDaysSettingsProvider.future,
    );
    expect(saved.selected, <int>[DateTime.tuesday, DateTime.thursday]);
    expect(saved.isCustom, isTrue);

    final List<SyncQueueRow> queue = await db.select(db.syncQueue).get();
    expect(
      queue.where(
        (SyncQueueRow row) =>
            row.entity == ScheduleRepository.syncEntity &&
            row.entityId == ScheduleRepository.syncEntityId,
      ),
      hasLength(1),
    );
  });

  test('reset restores the original plan and keeps completion', () async {
    final PracticalDaysActions actions = container.read(
      practicalDaysActionsProvider,
    );
    final PlanBrowserData before = (await container.read(
      planBrowserProvider.future,
    ))!;
    final SchedulePreview preview = await actions.preview(<int>[
      DateTime.tuesday,
      DateTime.thursday,
    ]);
    final Map<String, int> beforeDays = dayNumbersOf(before);
    final String taskId = firstMover(preview, beforeDays).task.id;
    final int originDay = beforeDays[taskId]!;
    final PlanTask originalTask = before.days[originDay - 1].tasks.firstWhere(
      (PlanTask task) => task.id == taskId,
    );
    final String stepId = originalTask.steps.first.id;
    await userState.setStepCompleted(stepId, StepProgress.completed);

    final Future<PlanBrowserData?> customised = waitFor<PlanBrowserData?>(
      planBrowserProvider,
      (PlanBrowserData? data) =>
          data != null &&
          data.days[originDay - 1].tasks.every(
            (PlanTask task) => task.id != taskId,
          ),
    );
    await pumpEventQueue();
    await actions.save(<int>[DateTime.tuesday, DateTime.thursday]);
    final PlanBrowserData custom = (await customised.timeout(
      const Duration(seconds: 10),
      onTimeout: () =>
          throw TimeoutException('Plan did not re-emit after save'),
    ))!;

    final Future<PlanBrowserData?> restored = waitFor<PlanBrowserData?>(
      planBrowserProvider,
      (PlanBrowserData? data) =>
          data != null &&
          data.days[originDay - 1].tasks.any(
            (PlanTask task) => task.id == taskId,
          ),
    );
    await pumpEventQueue();
    await actions.reset();
    final PlanBrowserData original = (await restored.timeout(
      const Duration(seconds: 10),
      onTimeout: () =>
          throw TimeoutException('Plan did not re-emit after reset'),
    ))!;

    expect(custom.days[1].day.isPractical, isFalse);
    expect(original.days[1].day.isPractical, isTrue);
    expect(
      original.days[originDay - 1].tasks.map((PlanTask task) => task.id),
      before.days[originDay - 1].tasks.map((PlanTask task) => task.id),
    );

    final PracticalDaysSettings settings = await container.read(
      practicalDaysSettingsProvider.future,
    );
    expect(settings.selected, PracticalWeekdays.original);
    expect(settings.isCustom, isFalse);

    // Reset is a new state, not a wipe: the completed step survives.
    expect(
      original.days[originDay - 1].tasks
          .firstWhere((PlanTask task) => task.id == taskId)
          .steps
          .firstWhere((PlanStep step) => step.id == stepId)
          .progress,
      StepProgress.completed,
    );

    // The template tables were never rewritten by either operation.
    expect((await db.select(db.days).get()).length, 68);
    expect((await db.select(db.tasks).get()).length, 725);
  });

  test('three practical days save and reach both tabs', () async {
    final PracticalDaysActions actions = container.read(
      practicalDaysActionsProvider,
    );
    final PlanBrowserData before = (await container.read(
      planBrowserProvider.future,
    ))!;
    expect(before.days[1].day.isPractical, isTrue);

    final SchedulePreview preview = await actions.preview(<int>[
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
    ]);
    expect(preview.nextWeekdays, <int>[2, 3, 4]);
    expect(
      preview.schedule.tasks,
      hasLength(
        before.days.fold<int>(
          0,
          (int sum, PlanDayData day) => sum + day.tasks.length,
        ),
      ),
    );

    final Future<PlanBrowserData?> changed = waitFor<PlanBrowserData?>(
      planBrowserProvider,
      (PlanBrowserData? data) =>
          data != null && data.days[1].day.type == 'normal',
    );
    final Future<TodayData?> todayChanged = waitFor<TodayData?>(
      todayDataProvider,
      (TodayData? data) => data != null && data.day.type == 'normal',
    );
    await pumpEventQueue();
    await actions.save(<int>[
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
    ]);

    final PlanBrowserData after = (await changed.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Plan did not re-emit'),
    ))!;
    final TodayData today = (await todayChanged.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Today did not re-emit'),
    ))!;

    expect(after.days[1].day.type, 'normal');
    // Week 1 runs Thursday..Wednesday, so Tuesday and Wednesday are days 6/7
    // and Thursday is day 1.
    expect(after.days[0].day.isPractical, isTrue);
    expect(after.days[5].day.isPractical, isTrue);
    expect(after.days[6].day.isPractical, isTrue);
    expect(today.dayNumber, 2);
    expect(
      today.tasks.map((PlanTask task) => task.id),
      after.days[1].tasks.map((PlanTask task) => task.id),
    );
    final PracticalDaysSettings settings = await container.read(
      practicalDaysSettingsProvider.future,
    );
    expect(settings.selected, <int>[2, 3, 4]);
  });

  test('a manual move reaches Plan, Today and the override table', () async {
    final PlanBrowserData before = (await container.read(
      planBrowserProvider.future,
    ))!;
    final List<PlanTask> dayTwo = before.days[1].tasks;
    expect(dayTwo.length, greaterThan(1));

    // Day 3 is a study day; moving the last task of day 2 there stays inside
    // its neighbour window.
    final PlanTask moved = dayTwo.last;
    final Future<PlanBrowserData?> changed = waitFor<PlanBrowserData?>(
      planBrowserProvider,
      (PlanBrowserData? data) =>
          data != null &&
          data.days[1].tasks.every((PlanTask task) => task.id != moved.id),
    );
    await pumpEventQueue();
    final TaskMovePreview result = await container
        .read(taskScheduleActionsProvider)
        .commit(taskId: moved.id, dayNumber: 3);

    expect(result.ok, isTrue, reason: 'issue ${result.issue}');
    final PlanBrowserData after = (await changed.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Plan did not re-emit'),
    ))!;

    expect(
      after.days[2].tasks.any((PlanTask task) => task.id == moved.id),
      isTrue,
    );
    expect(after.manualTaskIds, contains(moved.id));
    expect(
      after.tasks,
      hasLength(
        before.days.fold<int>(
          0,
          (int sum, PlanDayData day) => sum + day.tasks.length,
        ),
      ),
    );

    // Today renders the same day-2 list as Plan.
    final TodayData today = (await container.read(todayDataProvider.future))!;
    expect(
      today.tasks.map((PlanTask task) => task.id),
      after.days[1].tasks.map((PlanTask task) => task.id),
    );

    final List<ScheduleOverrideRow> rows = await db
        .select(db.scheduleOverrides)
        .get();
    expect(rows, hasLength(1));
    expect(rows.single.taskId, moved.id);
    expect(rows.single.dayNumber, 3);

    await container.read(taskScheduleActionsProvider).clear(moved.id);
    expect(await db.select(db.scheduleOverrides).get(), isEmpty);
    final PlanBrowserData restored = (await container.read(
      planBrowserProvider.future,
    ))!;
    expect(
      restored.days[1].tasks.any((PlanTask task) => task.id == moved.id),
      isTrue,
    );
    expect(restored.manualTaskIds, isEmpty);
  });
}
