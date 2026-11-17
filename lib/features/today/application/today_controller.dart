import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/local_day_clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/plan_progress_repository.dart';
import '../../../data/repositories/template_repository.dart';
import '../../../data/repositories/user_state_repository.dart';
import '../../../domain/plan/plan_calendar.dart';
import '../../../domain/plan/plan_progress.dart';
import '../../../domain/plan/plan_task.dart';
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
  final DayRow day;
  final List<PlanTask> tasks;
  final List<BreakRow> breaks;
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
  final TemplateRepository template = ref.watch(templateRepositoryProvider);
  final UserStateRepository userState = ref.watch(userStateRepositoryProvider);
  final PlanProgressRepository progress = ref.watch(
    planProgressRepositoryProvider,
  );
  final AppDatabase db = ref.watch(appDatabaseProvider);

  return _watchToday(
    calendar: calendar,
    now: now,
    template: template,
    userState: userState,
    progress: progress,
    stateChanges: _watchUserState(db),
  );
});

Stream<TodayData?> _watchToday({
  required Future<PlanCalendar?> calendar,
  required Future<DateTime> now,
  required TemplateRepository template,
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
  yield await _buildToday(
    activeCalendar,
    current,
    template,
    userState,
    progress,
  );

  await for (final _ in stateChanges) {
    yield await _buildToday(
      activeCalendar,
      current,
      template,
      userState,
      progress,
    );
  }
}

/// Watches every user table Today reads. Drift emits an initial value for each
/// query, which is skipped because [_watchToday] has already built that state.
Stream<void> _watchUserState(AppDatabase db) {
  final List<StreamSubscription<dynamic>> subscriptions =
      <StreamSubscription<dynamic>>[];
  late final StreamController<void> controller;

  controller = StreamController<void>(
    onListen: () {
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
  TemplateRepository template,
  UserStateRepository userState,
  PlanProgressRepository progressRepository,
) async {
  final ResolvedPlanDay resolved = calendar.resolveToday(now);
  final int dayNumber = resolved.dayNumber;

  // One snapshot, exactly like the Plan tab: every day, every task with its
  // steps, then a pure-Dart filter for the resolved day. No per-day SQL join
  // is involved, so a stale, duplicated or re-keyed `days.id` can never blank
  // the schedule and Today and Plan read the same rows by construction.
  final List<DayRow> allDays = await template.allDays();
  DayRow? todayDay;
  final Set<String> dayIds = <String>{};
  for (final DayRow day in allDays) {
    if (day.dayNumber != dayNumber) continue;
    todayDay ??= day;
    dayIds.add(day.id);
  }
  // Before the plan import there is no row for today; the screen shows the
  // load-error state rather than an empty schedule.
  if (todayDay == null) return null;

  final List<TaskWithSteps> allTasks = await template.allTasksWithSteps();
  final List<TaskWithSteps> dayTasks =
      <TaskWithSteps>[
        for (final TaskWithSteps item in allTasks)
          if (dayIds.contains(item.task.dayId)) item,
      ]..sort(
        (TaskWithSteps a, TaskWithSteps b) =>
            a.task.sortOrder.compareTo(b.task.sortOrder),
      );

  final List<BreakRow> breaks = <BreakRow>[];
  for (final String dayId in dayIds) {
    breaks.addAll(await template.breaksForDay(dayId));
  }
  breaks.sort((BreakRow a, BreakRow b) => a.startClock.compareTo(b.startClock));

  // Use the global (non-joined) reads, exactly like the Plan tab, so Today
  // and Plan never disagree on progress and an upgraded database cannot make
  // the per-day joins come back empty. State is then filtered by step id below.
  final Set<String> allCompletedStepIds = await userState.allCompletedStepIds();
  final Map<String, StepProgress> allStepProgresses = await userState
      .allStepProgresses();
  final Map<String, String> allTaskStatuses = await userState.allTaskStatuses();
  final List<SubjectRow> subjects = await template.allSubjects();
  final Map<String, String> subjectNames = <String, String>{
    for (final SubjectRow subject in subjects) subject.id: subject.nameAr,
  };
  final Map<String, Color> subjectAccents = <String, Color>{
    for (final SubjectRow subject in subjects)
      subject.id: _hexColor(subject.accentHex),
  };

  final Map<int, PlanProgress> progressByDay = await progressRepository
      .progressByDay();
  final PlanProgress progress = progressByDay[dayNumber] ?? PlanProgress.empty;

  final ({int tasks, int minutes}) overdue = await progressRepository
      .overdueBefore(dayNumber);

  final List<PlanTask> tasks = <PlanTask>[
    for (final TaskWithSteps item in dayTasks)
      PlanTask(
        id: item.task.id,
        dayNumber: dayNumber,
        subjectKey: item.task.subjectId,
        subjectName: subjectNames[item.task.subjectId],
        title: item.task.title,
        groupTitle: item.task.groupTitle,
        type: PlanTaskType.parse(item.task.type),
        suggestedStart: item.task.suggestedStart,
        suggestedEnd: item.task.suggestedEnd,
        status:
            PlanTaskStatus.tryParse(allTaskStatuses[item.task.id]) ??
            PlanTaskStatus.notStarted,
        postponedToDay:
            (PlanTaskStatus.tryParse(allTaskStatuses[item.task.id]) ??
                        PlanTaskStatus.notStarted) ==
                    PlanTaskStatus.postponed
                ? (dayNumber + 1).clamp(1, allDays.length)
                : null,
        steps: <PlanStep>[
          for (final StepRow step in item.steps)
            PlanStep(
              id: step.id,
              kind: step.kind,
              minutes: step.minutes,
              order: step.sortOrder,
              completed: allCompletedStepIds.contains(step.id),
              suggestedStart: step.suggestedStart,
              suggestedEnd: step.suggestedEnd,
              progress:
                  allStepProgresses[step.id] ??
                  (allCompletedStepIds.contains(step.id)
                      ? StepProgress.completed
                      : StepProgress.notStarted),
            ),
        ],
      ),
  ];

  final Map<int, DayRow> dayByNumber = <int, DayRow>{
    for (final DayRow day in allDays) day.dayNumber: day,
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
  required Map<int, DayRow> dayByNumber,
  required Map<int, PlanProgress> progressByDay,
  required PlanProgress today,
}) {
  int streak = 0;

  for (int number = dayNumber - 1; number >= 1; number--) {
    final DayRow? day = dayByNumber[number];
    if (day == null) break;
    if (day.type == 'rest') {
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
