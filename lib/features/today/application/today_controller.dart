import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/local_day_clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/plan_progress_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/user_state_repository.dart';
import '../../../domain/plan/plan_calendar.dart';
import '../../../domain/plan/plan_progress.dart';
import '../../../domain/plan/plan_task.dart';
import '../../../domain/plan/schedule_engine.dart';
import '../../../domain/plan/step_progress.dart';

/// Read model for Today (PRD 5.2, prototype v0).
///
/// Everything here is derived from the imported plan plus user state; the
/// screen never invents numbers or sample tasks.
class TodayData {
  const TodayData({
    required this.now,
    required this.window,
    required this.dayNumber,
    required this.date,
    required this.day,
    required this.tasks,
    required this.breaks,
    required this.progress,
    required this.overdueTasks,
    required this.overdueMinutes,
    required this.streak,
    required this.points,
    required this.subjectNames,
    required this.subjectAccents,
    required this.daysRemaining,
  });

  /// Device-local time used for this build, so the greeting and quote rotate
  /// with the same date as the plan day.
  final DateTime now;

  /// Whether the local date is before, inside or after the plan window.
  final PlanWindow window;

  final int dayNumber;
  final DateTime date;
  final ScheduledDay day;
  final List<PlanTask> tasks;
  final List<ScheduleBreak> breaks;
  final PlanProgress progress;

  /// Open tasks on earlier study days, and their remaining planned minutes.
  final int overdueTasks;
  final int overdueMinutes;

  /// Consecutive completed/rest days before today (today excluded until done).
  final int streak;

  /// Step points: 10 for a video step, 20 for solved chapter questions.
  final int points;

  final Map<String, String> subjectNames;
  final Map<String, Color> subjectAccents;
  final int daysRemaining;

  bool get isRest => day.type == 'rest';
  bool get isDone => !isRest && progress.isComplete;
  bool get hasStarted => window != PlanWindow.beforeStart;
  bool get hasEnded => window == PlanWindow.afterEnd;

  /// The first task that still has work, in plan order.
  PlanTask? get nextTask {
    for (final PlanTask task in tasks) {
      if (task.isComplete || task.status == PlanTaskStatus.postponed) continue;
      return task;
    }
    return null;
  }
}

/// Emits the device-local time whenever its calendar date changes. Today
/// rebuilds once at local midnight (or after a timezone jump), not on every
/// clock tick.
final StreamProvider<DateTime> todayClockProvider = StreamProvider<DateTime>((
  Ref ref,
) {
  return LocalDayClock().watch();
});

/// Today's plan day plus live progress.
///
/// The plan day comes from one rule, [PlanCalendar.resolveToday], against the
/// device-local date from [todayClockProvider]. Progress comes from a live DB
/// stream, so a step/task write updates every derived number without a manual
/// provider invalidation.
final StreamProvider<TodayData?>
todayDataProvider = StreamProvider<TodayData?>((Ref ref) {
  final Future<PlanCalendar?> calendar = ref.watch(planCalendarProvider.future);
  final Future<DateTime> now = ref.watch(todayClockProvider.future);
  final ScheduleRepository schedule = ref.watch(scheduleRepositoryProvider);
  final UserStateRepository userState = ref.watch(userStateRepositoryProvider);
  final PlanProgressRepository progress = ref.watch(
    planProgressRepositoryProvider,
  );
  final AppDatabase db = ref.watch(appDatabaseProvider);

  return _watchToday(
    calendar: calendar,
    now: now,
    schedule: schedule,
    userState: userState,
    progress: progress,
    stateChanges: _watchTodayChanges(db, schedule),
  );
});

Stream<TodayData?> _watchToday({
  required Future<PlanCalendar?> calendar,
  required Future<DateTime> now,
  required ScheduleRepository schedule,
  required UserStateRepository userState,
  required PlanProgressRepository progress,
  required Stream<void> stateChanges,
}) async* {
  final PlanCalendar? activeCalendar = await calendar;
  if (activeCalendar == null) {
    yield null;
    return;
  }

  final DateTime current = await now;
  ScheduleSnapshot snapshot = await schedule.load(activeCalendar);
  yield await _buildToday(
    activeCalendar,
    current,
    snapshot,
    userState,
    progress,
  );

  await for (final _ in stateChanges) {
    snapshot = await schedule.load(activeCalendar);
    yield await _buildToday(
      activeCalendar,
      current,
      snapshot,
      userState,
      progress,
    );
  }
}

/// Watches every user table Today reads and the shared schedule setting.
Stream<void> _watchTodayChanges(AppDatabase db, ScheduleRepository schedule) {
  final List<StreamSubscription<dynamic>> subscriptions =
      <StreamSubscription<dynamic>>[];
  late final StreamController<void> controller;

  controller = StreamController<void>(
    onListen: () {
      subscriptions.add(
        schedule
            .watchPracticalWeekdays()
            .skip(1)
            .listen((_) => controller.add(null), onError: controller.addError),
      );
      subscriptions.add(
        db
            .select(db.userStepStates)
            .watch()
            .skip(1)
            .listen((_) => controller.add(null)),
      );
      subscriptions.add(
        db
            .select(db.userTaskStates)
            .watch()
            .skip(1)
            .listen((_) => controller.add(null)),
      );
    },
    onCancel: () async {
      for (final StreamSubscription<dynamic> subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
    },
  );

  return controller.stream;
}

Future<TodayData?> _buildToday(
  PlanCalendar calendar,
  DateTime now,
  ScheduleSnapshot schedule,
  UserStateRepository userState,
  PlanProgressRepository progressRepository,
) async {
  final ResolvedPlanDay resolved = calendar.resolveToday(now);
  final int dayNumber = resolved.dayNumber;
  final ScheduledDay? todayDay = schedule.day(dayNumber);
  // Before the plan import there is no row for today; the screen shows the
  // load-error state rather than an empty schedule.
  if (todayDay == null) return null;

  final List<ScheduledTask> dayTasks = schedule.tasksForDay(dayNumber);
  final List<ScheduleBreak> breaks = todayDay.breaks;

  // Use the global (non-joined) reads, exactly like the Plan tab, so Today
  // and Plan never disagree on progress and an upgraded database cannot make
  // the per-day joins come back empty. State is then filtered by step id below.
  final Set<String> allCompletedStepIds = await userState.allCompletedStepIds();
  final Map<String, StepProgress> allStepProgresses = await userState
      .allStepProgresses();
  final Map<String, String> allTaskStatuses = await userState.allTaskStatuses();
  final Map<String, String> subjectNames = <String, String>{
    for (final SubjectRow subject in schedule.subjects)
      subject.id: subject.nameAr,
  };
  final Map<String, Color> subjectAccents = <String, Color>{
    for (final SubjectRow subject in schedule.subjects)
      subject.id: _hexColor(subject.accentHex),
  };

  final Map<int, PlanProgress> progressByDay = await progressRepository
      .progressByDay(schedule);
  final PlanProgress progress = progressByDay[dayNumber] ?? PlanProgress.empty;

  final ({int tasks, int minutes}) overdue = await progressRepository
      .overdueBefore(dayNumber, schedule);

  final List<PlanTask> tasks = <PlanTask>[
    for (final ScheduledTask item in dayTasks)
      PlanTask(
        id: item.task.id,
        dayNumber: dayNumber,
        subjectKey: item.task.subjectId,
        subjectName: subjectNames[item.task.subjectId],
        title: item.task.title,
        groupTitle: item.task.groupTitle,
        type: PlanTaskType.parse(item.task.type),
        suggestedStart: item.startClock,
        suggestedEnd: item.endClock,
        status:
            PlanTaskStatus.tryParse(allTaskStatuses[item.task.id]) ??
            PlanTaskStatus.notStarted,
        postponedToDay:
            (PlanTaskStatus.tryParse(allTaskStatuses[item.task.id]) ??
                    PlanTaskStatus.notStarted) ==
                PlanTaskStatus.postponed
            ? (dayNumber + 1).clamp(1, schedule.days.length)
            : null,
        steps: <PlanStep>[
          for (final StepRow step in item.steps)
            PlanStep(
              id: step.id,
              kind: step.kind,
              minutes: step.minutes,
              order: step.sortOrder,
              completed: allCompletedStepIds.contains(step.id),
              suggestedStart: _spanStart(item, step),
              suggestedEnd: _spanEnd(item, step),
              progress:
                  allStepProgresses[step.id] ??
                  (allCompletedStepIds.contains(step.id)
                      ? StepProgress.completed
                      : StepProgress.notStarted),
            ),
        ],
      ),
  ];

  final Map<int, ScheduledDay> dayByNumber = <int, ScheduledDay>{
    for (final ScheduledDay day in schedule.days) day.dayNumber: day,
  };

  return TodayData(
    now: now,
    window: resolved.window,
    dayNumber: dayNumber,
    date: resolved.date,
    day: todayDay,
    tasks: tasks,
    breaks: breaks,
    progress: progress,
    overdueTasks: overdue.tasks,
    overdueMinutes: overdue.minutes,
    streak: _streak(
      dayNumber: dayNumber,
      dayByNumber: dayByNumber,
      progressByDay: progressByDay,
      today: progress,
    ),
    points: _points(tasks),
    subjectNames: subjectNames,
    subjectAccents: subjectAccents,
    daysRemaining: calendar.daysAfterToday(now),
  );
}

String? _spanStart(ScheduledTask item, StepRow step) {
  final ScheduleSpan? span = item.stepSpans[step.id];
  if (span != null && span.startClock.isNotEmpty) return span.startClock;
  return step.suggestedStart;
}

String? _spanEnd(ScheduledTask item, StepRow step) {
  final ScheduleSpan? span = item.stepSpans[step.id];
  if (span != null && span.endClock.isNotEmpty) return span.endClock;
  return step.suggestedEnd;
}

/// Writes step state; the live DB stream rebuilds Today without a manual
/// invalidation.
class TodayActions {
  TodayActions(this._ref);

  final Ref _ref;

  /// Applies the two-tap progression for one step. Today runs the tap logic
  /// locally; the Plan tab calls this with the state returned from the chip.
  Future<void> setStepCompleted(String stepId, StepProgress progress) async {
    await _ref
        .read(userStateRepositoryProvider)
        .setStepCompleted(stepId, progress);
  }
}

final Provider<TodayActions> todayActionsProvider = Provider<TodayActions>((
  Ref ref,
) {
  return TodayActions(ref);
});

int _streak({
  required int dayNumber,
  required Map<int, ScheduledDay> dayByNumber,
  required Map<int, PlanProgress> progressByDay,
  required PlanProgress today,
}) {
  int streak = 0;

  for (int number = dayNumber - 1; number >= 1; number--) {
    final ScheduledDay? day = dayByNumber[number];
    if (day == null) break;
    if (day.isRest) {
      // Scheduled rest days never break a streak (PRD 5.7).
      streak += 1;
      continue;
    }
    final PlanProgress progress = progressByDay[number] ?? PlanProgress.empty;
    if (!progress.isComplete) break;
    streak += 1;
  }

  if (today.isComplete) streak += 1;
  return streak;
}

int _points(List<PlanTask> tasks) {
  int points = 0;
  for (final PlanTask task in tasks) {
    final bool allDone = task.status == PlanTaskStatus.completed;
    for (final PlanStep step in task.steps) {
      if (!(allDone || step.completed)) continue;
      points += step.isQuestions ? 20 : 10;
    }
  }
  return points;
}

Color _hexColor(String hex) {
  final String value = hex.replaceFirst('#', '');
  final int parsed = int.parse(value, radix: 16);
  return Color(value.length == 6 ? 0xFF000000 | parsed : parsed);
}
