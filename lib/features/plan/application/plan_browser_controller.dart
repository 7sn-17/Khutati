import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/plan_progress_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/user_state_repository.dart';
import '../../../domain/plan/plan_calendar.dart';
import '../../../domain/plan/plan_progress.dart';
import '../../../domain/plan/plan_task.dart';
import '../../../domain/plan/step_progress.dart';
import '../../today/application/today_controller.dart' show todayClockProvider;

/// One accessible colour-labelled group of tasks inside a day.
class PlanSubjectGroup {
  const PlanSubjectGroup({
    required this.key,
    required this.name,
    required this.accent,
    required this.tasks,
  });

  final String key;
  final String name;
  final Color accent;
  final List<PlanTask> tasks;

  int get minutes =>
      tasks.fold<int>(0, (int sum, PlanTask task) => sum + task.plannedMinutes);

  bool get isComplete =>
      tasks.isNotEmpty && tasks.every((PlanTask t) => t.isComplete);
}

/// A plan day as the Plan tab renders it: real date, status, tasks and the
/// same progress snapshot used everywhere else in the app.
class PlanDayData {
  const PlanDayData({
    required this.day,
    required this.date,
    required this.tasks,
    required this.progress,
    required this.status,
    required this.isToday,
    required this.subjectNames,
    required this.subjectAccents,
  });

  final ScheduledDay day;
  final DateTime date;
  final List<PlanTask> tasks;
  final PlanProgress progress;
  final PlanDayStatus status;
  final bool isToday;
  final Map<String, String> subjectNames;
  final Map<String, Color> subjectAccents;

  bool get isRest => day.type == 'rest';
  bool get isPractical => day.type == 'practical';

  List<PlanSubjectGroup> get groups {
    final Map<String, List<PlanTask>> grouped = <String, List<PlanTask>>{};
    for (final PlanTask task in tasks) {
      grouped.putIfAbsent(task.subjectKey, () => <PlanTask>[]).add(task);
    }
    return <PlanSubjectGroup>[
      for (final MapEntry<String, List<PlanTask>> entry in grouped.entries)
        PlanSubjectGroup(
          key: entry.key,
          name: subjectNames[entry.key] ?? entry.value.first.subjectName ?? '',
          accent: subjectAccents[entry.key] ?? subjectAccents.values.first,
          tasks: entry.value,
        ),
    ];
  }
}

/// A plan week with its seven (or fewer) days and combined progress.
class PlanWeekData {
  const PlanWeekData({
    required this.number,
    required this.days,
    required this.progress,
  });

  final int number;
  final List<PlanDayData> days;
  final PlanProgress progress;

  DateTime get firstDate => days.first.date;
  DateTime get lastDate => days.last.date;

  List<PlanSubjectGroup> get subjects {
    final Map<String, PlanTask> seen = <String, PlanTask>{};
    for (final PlanDayData day in days) {
      for (final PlanTask task in day.tasks) {
        seen.putIfAbsent(task.id, () => task);
      }
    }
    final Map<String, List<PlanTask>> grouped = <String, List<PlanTask>>{};
    for (final PlanTask task in seen.values) {
      grouped.putIfAbsent(task.subjectKey, () => <PlanTask>[]).add(task);
    }
    return <PlanSubjectGroup>[
      for (final MapEntry<String, List<PlanTask>> entry in grouped.entries)
        PlanSubjectGroup(
          key: entry.key,
          name:
              days
                  .where(
                    (PlanDayData day) => day.tasks.any(
                      (PlanTask t) => t.subjectKey == entry.key,
                    ),
                  )
                  .first
                  .subjectNames[entry.key] ??
              entry.value.first.subjectName ??
              '',
          accent:
              days
                  .where(
                    (PlanDayData day) => day.tasks.any(
                      (PlanTask t) => t.subjectKey == entry.key,
                    ),
                  )
                  .first
                  .subjectAccents[entry.key] ??
              const Color(0xFF6AA6FF),
          tasks: entry.value,
        ),
    ];
  }
}

/// A task match for Plan search, carrying enough context to jump to its day.
class PlanSearchHit {
  const PlanSearchHit({required this.day, required this.task});

  final PlanDayData day;
  final PlanTask task;
}

/// Whole-plan read model for the Plan tab. It loads the template once and
/// rebuilds from the live user-state stream after a step/task change.
class PlanBrowserData {
  const PlanBrowserData({
    required this.calendar,
    required this.now,
    required this.today,
    required this.days,
    required this.progressByDay,
    required this.overall,
  });

  final PlanCalendar calendar;
  final DateTime now;
  final ResolvedPlanDay today;
  final List<PlanDayData> days;
  final Map<int, PlanProgress> progressByDay;
  final PlanProgress overall;

  PlanDayData get todayDay => days.firstWhere(
    (PlanDayData day) => day.day.dayNumber == today.dayNumber,
  );

  int get currentWeek => calendar.weekOfDay(today.dayNumber);

  PlanWeekData week(int number) {
    final List<PlanDayData> weekDays = <PlanDayData>[
      for (final int dayNumber in calendar.daysInWeek(number))
        days[dayNumber - 1],
    ];
    return PlanWeekData(
      number: number,
      days: weekDays,
      progress: PlanProgress.combine(
        weekDays.map((PlanDayData day) => day.progress),
      ),
    );
  }

  /// Local, diacritic-insensitive search over task titles, chapter headings,
  /// subject names and day headings. Results keep plan order and include the
  /// day so the UI can deep-link into the right week.
  List<PlanSearchHit> search(String rawQuery) {
    final String query = _normalize(rawQuery);
    if (query.isEmpty) return const <PlanSearchHit>[];

    final List<PlanSearchHit> hits = <PlanSearchHit>[];
    for (final PlanDayData day in days) {
      for (final PlanTask task in day.tasks) {
        final String haystack = _normalize(
          <String?>[
            task.title,
            task.groupTitle,
            task.subjectName,
            day.day.headerTitle,
            day.day.note,
          ].whereType<String>().join(' '),
        );
        if (haystack.contains(query)) {
          hits.add(PlanSearchHit(day: day, task: task));
        }
      }
    }
    return hits;
  }

  static String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp('[\\u064B-\\u0652\\u0670]'), '')
        .replaceAll(RegExp('[أإآ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

final StreamProvider<PlanBrowserData?>
planBrowserProvider = StreamProvider<PlanBrowserData?>((Ref ref) {
  final Future<PlanCalendar?> calendar = ref.watch(planCalendarProvider.future);
  final Future<DateTime> now = ref.watch(todayClockProvider.future);
  final ScheduleRepository schedule = ref.watch(scheduleRepositoryProvider);
  final UserStateRepository userState = ref.watch(userStateRepositoryProvider);
  final PlanProgressRepository progress = ref.watch(
    planProgressRepositoryProvider,
  );
  final AppDatabase db = ref.watch(appDatabaseProvider);

  return _watchPlan(
    calendar: calendar,
    now: now,
    schedule: schedule,
    userState: userState,
    progress: progress,
    stateChanges: _watchPlanChanges(db, schedule),
  );
});

Stream<PlanBrowserData?> _watchPlan({
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
  yield await _build(activeCalendar, current, snapshot, userState, progress);

  await for (final _ in stateChanges) {
    snapshot = await schedule.load(activeCalendar);
    yield await _build(activeCalendar, current, snapshot, userState, progress);
  }
}

/// Watches both user progress and the practical-weekday setting. A schedule
/// change and a step tap must rebuild the same read model.
Stream<void> _watchPlanChanges(AppDatabase db, ScheduleRepository schedule) {
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

Future<PlanBrowserData> _build(
  PlanCalendar calendar,
  DateTime now,
  ScheduleSnapshot schedule,
  UserStateRepository userState,
  PlanProgressRepository progressRepository,
) async {
  final ResolvedPlanDay resolved = calendar.resolveToday(now);
  final Map<String, String> subjectNames = <String, String>{
    for (final SubjectRow subject in schedule.subjects)
      subject.id: subject.nameAr,
  };
  final Map<String, Color> subjectAccents = <String, Color>{
    for (final SubjectRow subject in schedule.subjects)
      subject.id: _hexColor(subject.accentHex),
  };

  final Set<String> completedSteps = await userState.allCompletedStepIds();
  final Map<String, StepProgress> stepProgresses = await userState
      .allStepProgresses();
  final Map<String, String> taskStatuses = await userState.allTaskStatuses();
  final Map<int, PlanProgress> progressByDay = await progressRepository
      .progressByDay(schedule);

  final List<PlanDayData> days = <PlanDayData>[
    for (final ScheduledDay day in schedule.days)
      _dayData(
        day: day,
        calendar: calendar,
        now: now,
        resolved: resolved,
        items: schedule.tasksForDay(day.dayNumber),
        progress: progressByDay[day.dayNumber] ?? PlanProgress.empty,
        completedSteps: completedSteps,
        stepProgresses: stepProgresses,
        taskStatuses: taskStatuses,
        subjectNames: subjectNames,
        subjectAccents: subjectAccents,
      ),
  ];

  return PlanBrowserData(
    calendar: calendar,
    now: now,
    today: resolved,
    days: days,
    progressByDay: progressByDay,
    overall: PlanProgress.combine(progressByDay.values),
  );
}

PlanDayData _dayData({
  required ScheduledDay day,
  required PlanCalendar calendar,
  required DateTime now,
  required ResolvedPlanDay resolved,
  required List<ScheduledTask> items,
  required PlanProgress progress,
  required Set<String> completedSteps,
  required Map<String, StepProgress> stepProgresses,
  required Map<String, String> taskStatuses,
  required Map<String, String> subjectNames,
  required Map<String, Color> subjectAccents,
}) {
  final bool isRest = day.isRest;
  final List<PlanTask> tasks = <PlanTask>[
    for (final ScheduledTask item in items)
      PlanTask(
        id: item.task.id,
        dayNumber: day.dayNumber,
        subjectKey: item.task.subjectId,
        subjectName: subjectNames[item.task.subjectId],
        title: item.task.title,
        groupTitle: item.task.groupTitle,
        type: PlanTaskType.parse(item.task.type),
        suggestedStart: item.startClock,
        suggestedEnd: item.endClock,
        status:
            PlanTaskStatus.tryParse(taskStatuses[item.task.id]) ??
            PlanTaskStatus.notStarted,
        postponedToDay:
            (PlanTaskStatus.tryParse(taskStatuses[item.task.id]) ??
                    PlanTaskStatus.notStarted) ==
                PlanTaskStatus.postponed
            ? day.dayNumber + 1
            : null,
        steps: <PlanStep>[
          for (final StepRow step in item.steps)
            PlanStep(
              id: step.id,
              kind: step.kind,
              minutes: step.minutes,
              order: step.sortOrder,
              completed: completedSteps.contains(step.id),
              suggestedStart: _spanStart(item, step),
              suggestedEnd: _spanEnd(item, step),
              progress:
                  stepProgresses[step.id] ??
                  (completedSteps.contains(step.id)
                      ? StepProgress.completed
                      : StepProgress.notStarted),
            ),
        ],
      ),
  ];

  return PlanDayData(
    day: day,
    date: calendar.dateOfDay(day.dayNumber),
    tasks: tasks,
    progress: progress,
    status: calendar.statusOf(
      dayNumber: day.dayNumber,
      isCompleted: progress.isComplete,
      isRest: isRest,
      now: now,
    ),
    isToday:
        resolved.window == PlanWindow.active &&
        day.dayNumber == resolved.dayNumber,
    subjectNames: subjectNames,
    subjectAccents: subjectAccents,
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

/// Writes plan task state; the live DB stream rebuilds the Plan tab without a
/// manual invalidation, so future and past tasks can be updated in place.
class PlanActions {
  PlanActions(this._ref);

  final Ref _ref;

  Future<void> setTaskStatus(String taskId, PlanTaskStatus status) async {
    await _ref
        .read(userStateRepositoryProvider)
        .setTaskStatus(taskId, status.wireValue);
  }

  /// Sets the step state used by Plan and read by Today, so both tabs agree on
  /// a step's partial/complete state.
  Future<void> setStepCompleted(String stepId, StepProgress progress) async {
    await _ref
        .read(userStateRepositoryProvider)
        .setStepCompleted(stepId, progress);
  }
}

final Provider<PlanActions> planActionsProvider = Provider<PlanActions>((
  Ref ref,
) {
  return PlanActions(ref);
});

Color _hexColor(String hex) {
  final String value = hex.replaceFirst('#', '');
  final int parsed = int.parse(value, radix: 16);
  return Color(value.length == 6 ? 0xFF000000 | parsed : parsed);
}
