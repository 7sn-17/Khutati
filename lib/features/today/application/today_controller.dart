import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/template_repository.dart';
import '../../../domain/plan/plan_calendar.dart';
import '../../../domain/plan/plan_progress.dart';
import '../../../domain/plan/plan_task.dart';

/// Read model for Today (PRD 5.2, prototype v0).
///
/// Everything here is derived from the imported plan plus user state; the
/// screen never invents numbers or sample tasks.
class TodayData {
  const TodayData({
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
    required this.hasStarted,
  });

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
  final bool hasStarted;

  bool get isRest => day.type == 'rest';
  bool get isDone => !isRest && progress.isComplete;

  /// The first task that still has work, in plan order.
  PlanTask? get nextTask {
    for (final PlanTask task in tasks) {
      if (!task.isComplete) return task;
    }
    return null;
  }
}

/// Today's plan day plus live progress. Rebuilt when user state changes.
///
/// The date is captured when the provider is built; a new day is picked up on
/// the next app start or pull-to-refresh, which is enough for a study app.
final FutureProvider<TodayData?> todayDataProvider = FutureProvider<TodayData?>(
  (Ref ref) async {
    final PlanCalendar? calendar = await ref.watch(planCalendarProvider.future);
    if (calendar == null) return null;

    final DateTime now = DateTime.now();
    final int dayNumber = calendar.currentDayNumber(now);
    final TemplateRepository template = ref.watch(templateRepositoryProvider);
    final DayBundle? bundle = await template.dayBundle(dayNumber);
    if (bundle == null) return null;

    final Set<String> completedStepIds = await ref
        .watch(userStateRepositoryProvider)
        .completedStepIdsForDay(bundle.day.id);
    final List<SubjectRow> subjects = await template.allSubjects();
    final Map<String, String> subjectNames = <String, String>{
      for (final SubjectRow subject in subjects) subject.id: subject.nameAr,
    };
    final Map<String, Color> subjectAccents = <String, Color>{
      for (final SubjectRow subject in subjects)
        subject.id: _hexColor(subject.accentHex),
    };

    final Map<int, PlanProgress> progressByDay = await ref
        .watch(planProgressRepositoryProvider)
        .progressByDay();
    final PlanProgress progress =
        progressByDay[dayNumber] ?? PlanProgress.empty;

    final ({int tasks, int minutes}) overdue = await ref
        .watch(planProgressRepositoryProvider)
        .overdueBefore(dayNumber);

    final List<PlanTask> tasks = <PlanTask>[
      for (final TaskWithSteps item in bundle.tasks)
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
          steps: <PlanStep>[
            for (final StepRow step in item.steps)
              PlanStep(
                id: step.id,
                kind: step.kind,
                minutes: step.minutes,
                order: step.sortOrder,
                completed: completedStepIds.contains(step.id),
                suggestedStart: step.suggestedStart,
                suggestedEnd: step.suggestedEnd,
              ),
          ],
        ),
    ];

    final List<DayRow> allDays = await template.allDays();
    final Map<int, DayRow> dayByNumber = <int, DayRow>{
      for (final DayRow day in allDays) day.dayNumber: day,
    };

    return TodayData(
      dayNumber: dayNumber,
      date: calendar.dateOfDay(dayNumber),
      day: bundle.day,
      tasks: tasks,
      breaks: bundle.breaks,
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
      hasStarted: calendar.hasStarted(now),
    );
  },
);

/// Writes step state and refreshes the read model.
class TodayActions {
  TodayActions(this._ref);

  final Ref _ref;

  Future<void> setStepCompleted(String stepId, bool completed) async {
    await _ref
        .read(userStateRepositoryProvider)
        .setStepCompleted(stepId, completed);
    _ref.invalidate(todayDataProvider);
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
    for (final PlanStep step in task.steps) {
      if (!step.completed) continue;
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
