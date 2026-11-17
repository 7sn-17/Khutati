import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/plan_progress_repository.dart';
import '../../../data/repositories/template_repository.dart';
import '../../../data/repositories/user_state_repository.dart';
import '../../../domain/plan/plan_calendar.dart';
import '../../../domain/plan/plan_progress.dart';
import '../../../domain/plan/plan_task.dart';
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

  final DayRow day;
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
  final TemplateRepository template = ref.watch(templateRepositoryProvider);
  final UserStateRepository userState = ref.watch(userStateRepositoryProvider);
  final PlanProgressRepository progress = ref.watch(
    planProgressRepositoryProvider,
  );
  final AppDatabase db = ref.watch(appDatabaseProvider);

  return _watchPlan(
    calendar: calendar,
    now: now,
    template: template,
    userState: userState,
    progress: progress,
    stateChanges: _watchUserState(db),
  );
});

Stream<PlanBrowserData?> _watchPlan({
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
  yield await _build(activeCalendar, current, template, userState, progress);

  await for (final _ in stateChanges) {
    yield await _build(activeCalendar, current, template, userState, progress);
  }
}

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

Future<PlanBrowserData> _build(
  PlanCalendar calendar,
  DateTime now,
  TemplateRepository template,
  UserStateRepository userState,
  PlanProgressRepository progressRepository,
) async {
  final ResolvedPlanDay resolved = calendar.resolveToday(now);
  final List<DayRow> dayRows = await template.allDays();
  final List<SubjectRow> subjects = await template.allSubjects();
  final Map<String, String> subjectNames = <String, String>{
    for (final SubjectRow subject in subjects) subject.id: subject.nameAr,
  };
  final Map<String, Color> subjectAccents = <String, Color>{
    for (final SubjectRow subject in subjects)
      subject.id: _hexColor(subject.accentHex),
  };

  final List<TaskWithSteps> templateTasks = await template.allTasksWithSteps();
  final Set<String> completedSteps = await userState.allCompletedStepIds();
  final Map<String, String> taskStatuses = await userState.allTaskStatuses();
  final Map<int, PlanProgress> progressByDay = await progressRepository
      .progressByDay();

  final Map<String, List<TaskWithSteps>> tasksByDay =
      <String, List<TaskWithSteps>>{};
  for (final TaskWithSteps item in templateTasks) {
    tasksByDay.putIfAbsent(item.task.dayId, () => <TaskWithSteps>[]).add(item);
  }

  final List<PlanDayData> days = <PlanDayData>[
    for (final DayRow day in dayRows)
      _dayData(
        day: day,
        calendar: calendar,
        now: now,
        resolved: resolved,
        items: tasksByDay[day.id] ?? const <TaskWithSteps>[],
        progress: progressByDay[day.dayNumber] ?? PlanProgress.empty,
        completedSteps: completedSteps,
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
  required DayRow day,
  required PlanCalendar calendar,
  required DateTime now,
  required ResolvedPlanDay resolved,
  required List<TaskWithSteps> items,
  required PlanProgress progress,
  required Set<String> completedSteps,
  required Map<String, String> taskStatuses,
  required Map<String, String> subjectNames,
  required Map<String, Color> subjectAccents,
}) {
  final bool isRest = day.type == 'rest';
  final List<PlanTask> tasks = <PlanTask>[
    for (final TaskWithSteps item in items)
      PlanTask(
        id: item.task.id,
        dayNumber: day.dayNumber,
        subjectKey: item.task.subjectId,
        subjectName: subjectNames[item.task.subjectId],
        title: item.task.title,
        groupTitle: item.task.groupTitle,
        type: PlanTaskType.parse(item.task.type),
        suggestedStart: item.task.suggestedStart,
        suggestedEnd: item.task.suggestedEnd,
        status:
            PlanTaskStatus.tryParse(taskStatuses[item.task.id]) ??
            PlanTaskStatus.notStarted,
        steps: <PlanStep>[
          for (final StepRow step in item.steps)
            PlanStep(
              id: step.id,
              kind: step.kind,
              minutes: step.minutes,
              order: step.sortOrder,
              completed: completedSteps.contains(step.id),
              suggestedStart: step.suggestedStart,
              suggestedEnd: step.suggestedEnd,
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

Color _hexColor(String hex) {
  final String value = hex.replaceFirst('#', '');
  final int parsed = int.parse(value, radix: 16);
  return Color(value.length == 6 ? 0xFF000000 | parsed : parsed);
}
