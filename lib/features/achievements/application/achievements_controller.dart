import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/plan_progress_repository.dart';
import '../../../data/repositories/template_repository.dart';
import '../../../data/repositories/user_state_repository.dart';
import '../../../domain/plan/plan_progress.dart';
import '../../../features/today/application/today_controller.dart';
import '../../../features/focus/application/focus_controller.dart';

class BadgeInfo {
  const BadgeInfo({
    required this.id,
    required this.name,
    required this.icon,
    required this.current,
    required this.unit,
    required this.thresholds,
  });

  final String id;
  final String name;
  final String icon;
  final int current;
  final String unit;
  final List<int> thresholds;

  int get level => thresholds.where((int t) => current >= t).length;
  int? get nextThreshold =>
      level < thresholds.length ? thresholds[level] : null;
  int get prevThreshold => level > 0 ? thresholds[level - 1] : 0;
  double get fraction {
    if (level >= thresholds.length) return 1.0;
    final int next = thresholds[level];
    final int prev = level > 0 ? thresholds[level - 1] : 0;
    if (next <= prev) return 1.0;
    return ((current - prev) / (next - prev)).clamp(0.0, 1.0);
  }

  bool get complete => level >= thresholds.length;
}

class SubjectProgress {
  const SubjectProgress({
    required this.name,
    required this.color,
    required this.completedTasks,
    required this.totalTasks,
    required this.percent,
  });
  final String name;
  final Color color;
  final int completedTasks;
  final int totalTasks;
  final double percent;
}

class AchievementsData {
  const AchievementsData({
    required this.totalPoints,
    required this.pointsToday,
    required this.streak,
    required this.last7,
    required this.badges,
    required this.nextBadge,
    required this.completedDays,
    required this.totalDays,
    required this.dayStatus,
    required this.dayHours,
    required this.dayPoints,
    required this.dayTasks,
    required this.dayTotalTasks,
    required this.totalFocusHours,
    required this.splitHours,
    required this.subjects,
    required this.todayDayNumber,
    required this.planStart,
    required this.todayDate,
  });

  final int totalPoints;
  final int pointsToday;
  final int streak;
  final List<String> last7;
  final List<BadgeInfo> badges;
  final BadgeInfo? nextBadge;
  final int completedDays;
  final int totalDays;
  final Map<int, String> dayStatus;
  final Map<int, double> dayHours;
  final Map<int, int> dayPoints;
  final Map<int, int> dayTasks;
  final Map<int, int> dayTotalTasks;
  final double totalFocusHours;
  final Map<String, double> splitHours;
  final List<SubjectProgress> subjects;
  final int todayDayNumber;

  /// First day of the active plan, used to print a real date for every cell in
  /// the day map (the reference prints `الأحد 12 نوفمبر` under a selected day).
  final DateTime? planStart;

  /// The device's local "today", used for the last-7-days weekday labels.
  final DateTime? todayDate;
}

final FutureProvider<AchievementsData?>
achievementsProvider = FutureProvider<AchievementsData?>((Ref ref) async {
  final TodayData? today = ref.watch(todayDataProvider).valueOrNull;
  final List<FocusSession> sessions =
      ref.watch(focusHistoryProvider).valueOrNull ?? const <FocusSession>[];

  final TemplateRepository template = ref.watch(templateRepositoryProvider);
  final UserStateRepository userState = ref.watch(userStateRepositoryProvider);
  final PlanProgressRepository progress = ref.watch(
    planProgressRepositoryProvider,
  );

  final List<DayRow> allDays = await template.allDays();
  final List<SubjectRow> subjects = await template.allSubjects();
  final List<TaskWithSteps> tasks = await template.allTasksWithSteps();
  final PlanRow? plan = await template.activePlan();

  final Set<String> completedStepIds = await userState.allCompletedStepIds();
  final Map<String, String> taskStatuses = await userState.allTaskStatuses();
  final Map<int, PlanProgress> progressByDay = await progress.progressByDay();
  final Map<String, PlanProgress> progressBySubject = await progress
      .progressBySubject();

  // step id -> kind
  final Map<String, String> stepKind = <String, String>{};
  for (final TaskWithSteps t in tasks) {
    for (final StepRow s in t.steps) {
      stepKind[s.id] = s.kind;
    }
  }

  // total points (all days)
  int totalPoints = 0;
  final Map<int, int> dayPoints = <int, int>{};
  final Map<String, int> dayByTaskId = <String, int>{};
  for (final DayRow d in allDays) {
    dayByTaskId[d.id] = d.dayNumber;
  }
  // map task -> day number
  final Map<String, int> taskDay = <String, int>{};
  for (final TaskWithSteps t in tasks) {
    // find day number by task.dayId
    for (final DayRow d in allDays) {
      if (d.id == t.task.dayId) {
        taskDay[t.task.id] = d.dayNumber;
      }
    }
  }

  for (final TaskWithSteps t in tasks) {
    final bool taskComplete = taskStatuses[t.task.id] == 'completed';
    int taskPts = 0;
    for (final StepRow s in t.steps) {
      final bool stepDone = taskComplete || completedStepIds.contains(s.id);
      if (!stepDone) continue;
      final int p = s.kind == 'questions' ? 20 : 10;
      taskPts += p;
      totalPoints += p;
    }
    final int? dn = taskDay[t.task.id];
    if (dn != null) {
      dayPoints[dn] = (dayPoints[dn] ?? 0) + taskPts;
    }
  }

  // completed days
  int completedDays = 0;
  final Map<int, String> dayStatus = <int, String>{};
  final Map<int, int> dayTasks = <int, int>{};
  final Map<int, int> dayTotalTasks = <int, int>{};
  final int todayDayNumber = today?.dayNumber ?? 0;
  final int totalDays = allDays.length;

  for (final DayRow d in allDays) {
    final int dn = d.dayNumber;
    final PlanProgress pp = progressByDay[dn] ?? PlanProgress.empty;
    dayTasks[dn] = pp.completedTasks;
    dayTotalTasks[dn] = pp.plannedTasks;
    if (pp.isComplete && pp.plannedTasks > 0) completedDays += 1;

    // A rest day is a property of the plan, not of the calendar: it must show
    // as "راحة" (dashed) whether it is behind us or still ahead. Checking the
    // future branch first used to hide every upcoming rest day as "قادم", which
    // is why they looked unrecorded in the map.
    if (d.type == 'rest') {
      dayStatus[dn] = 'rest';
    } else if (dn > todayDayNumber || todayDayNumber == 0) {
      dayStatus[dn] = 'future';
    } else if (dn == todayDayNumber) {
      dayStatus[dn] = pp.isComplete ? 'done' : 'today';
    } else if (pp.isComplete) {
      dayStatus[dn] = 'done';
    } else {
      dayStatus[dn] = 'wait';
    }
  }

  // last 7
  final List<String> last7 = <String>[];
  for (int i = 6; i >= 0; i--) {
    final int dn = todayDayNumber - i;
    if (dn < 1 || dn > totalDays) {
      last7.add('future');
    } else {
      last7.add(dayStatus[dn] ?? 'future');
    }
  }

  // study split & day hours from focus sessions
  final Map<String, double> splitSec = <String, double>{
    'attend': 0,
    'study': 0,
    'questions': 0,
  };
  final Map<int, double> daySec = <int, double>{};
  double totalFocusSec = 0;
  for (final FocusSession s in sessions) {
    if (s.phase != 'focus') continue;
    if (s.actualSeconds <= 0) continue;
    totalFocusSec += s.actualSeconds;
    final String? sid = s.stepId;
    final String kind = sid != null ? (stepKind[sid] ?? 'study') : 'study';
    splitSec[kind] = (splitSec[kind] ?? 0) + s.actualSeconds;
    // map to day number
    if (plan != null) {
      final DateTime planStart = DateTime(
        plan.startDate.year,
        plan.startDate.month,
        plan.startDate.day,
      );
      final DateTime sessionDate = DateTime(
        s.startedAt.year,
        s.startedAt.month,
        s.startedAt.day,
      );
      final int dn = sessionDate.difference(planStart).inDays + 1;
      if (dn >= 1 && dn <= totalDays) {
        daySec[dn] = (daySec[dn] ?? 0) + s.actualSeconds;
      }
    }
  }
  final Map<String, double> splitHours = <String, double>{
    'attend': (splitSec['attend'] ?? 0) / 3600.0,
    'study': (splitSec['study'] ?? 0) / 3600.0,
    'questions': (splitSec['questions'] ?? 0) / 3600.0,
  };
  final Map<int, double> dayHours = <int, double>{};
  for (final MapEntry<int, double> e in daySec.entries) {
    dayHours[e.key] = e.value / 3600.0;
  }
  final double totalFocusHours = totalFocusSec / 3600.0;

  // completed question steps count
  int questionStepsCompleted = 0;
  for (final TaskWithSteps t in tasks) {
    for (final StepRow s in t.steps) {
      if (s.kind != 'questions') continue;
      if (completedStepIds.contains(s.id)) questionStepsCompleted += 1;
    }
  }

  final List<BadgeInfo> badges = <BadgeInfo>[
    BadgeInfo(
      id: 'streak',
      name: 'السلسلة',
      icon: 'flame',
      current: today?.streak ?? 0,
      unit: 'يوم',
      thresholds: const <int>[3, 7, 14, 30, 60],
    ),
    BadgeInfo(
      id: 'points',
      name: 'النقاط',
      icon: 'star',
      current: totalPoints,
      unit: 'نقطة',
      thresholds: const <int>[250, 750, 1500, 3000, 5000],
    ),
    BadgeInfo(
      id: 'hours',
      name: 'ساعات الدراسة',
      icon: 'clock',
      current: totalFocusHours.floor(),
      unit: 'ساعة',
      thresholds: const <int>[10, 25, 50, 100, 150],
    ),
    BadgeInfo(
      id: 'plan',
      name: 'إنجاز الخطة',
      icon: 'flag',
      current: completedDays,
      unit: 'يوم',
      thresholds: const <int>[7, 17, 34, 51, 68],
    ),
    BadgeInfo(
      id: 'questions',
      name: 'حل الأسئلة',
      icon: 'quiz',
      current: questionStepsCompleted,
      unit: 'فصل',
      thresholds: const <int>[3, 8, 15, 25, 40],
    ),
  ];

  BadgeInfo? nextBadge;
  final List<BadgeInfo> candidates = badges
      .where((BadgeInfo b) => b.nextThreshold != null)
      .toList();
  if (candidates.isNotEmpty) {
    candidates.sort(
      (BadgeInfo a, BadgeInfo b) => b.fraction.compareTo(a.fraction),
    );
    nextBadge = candidates.first;
  }

  final List<SubjectProgress> subjectList = <SubjectProgress>[];
  for (final SubjectRow sub in subjects) {
    final PlanProgress pp = progressBySubject[sub.id] ?? PlanProgress.empty;
    final double pct = pp.plannedTasks > 0
        ? pp.completedTasks / pp.plannedTasks
        : 0.0;
    subjectList.add(
      SubjectProgress(
        name: sub.nameAr,
        color: _hexColor(sub.accentHex),
        completedTasks: pp.completedTasks,
        totalTasks: pp.plannedTasks,
        percent: pct.clamp(0.0, 1.0),
      ),
    );
  }

  return AchievementsData(
    totalPoints: totalPoints,
    pointsToday: today?.points ?? 0,
    streak: today?.streak ?? 0,
    last7: last7,
    badges: badges,
    nextBadge: nextBadge,
    completedDays: completedDays,
    totalDays: totalDays,
    dayStatus: dayStatus,
    dayHours: dayHours,
    dayPoints: dayPoints,
    dayTasks: dayTasks,
    dayTotalTasks: dayTotalTasks,
    totalFocusHours: totalFocusHours,
    splitHours: splitHours,
    subjects: subjectList,
    todayDayNumber: todayDayNumber,
    planStart: plan?.startDate,
    todayDate: today?.date,
  );
});

Color _hexColor(String hex) {
  final String value = hex.replaceFirst('#', '');
  final int parsed = int.parse(value, radix: 16);
  return Color(value.length == 6 ? 0xFF000000 | parsed : parsed);
}
