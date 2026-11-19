import 'practical_weekdays.dart';

/// One original day as the schedule engine sees it.
class ScheduleDayInput {
  const ScheduleDayInput({
    required this.dayNumber,
    required this.week,
    required this.date,
    required this.isRest,
  });

  final int dayNumber;
  final int week;
  final DateTime date;
  final bool isRest;
}

class ScheduleStepInput {
  const ScheduleStepInput({
    required this.id,
    required this.minutes,
    required this.order,
  });

  final String id;
  final int minutes;
  final int order;
}

/// One original task. Its [minutes] is the sum of its steps; the engine never
/// splits a task, so chapter/video groups stay intact.
class ScheduleTaskInput {
  const ScheduleTaskInput({
    required this.id,
    required this.sourceDayNumber,
    required this.sourceOrder,
    required this.minutes,
    required this.steps,
  });

  final String id;
  final int sourceDayNumber;
  final int sourceOrder;
  final int minutes;
  final List<ScheduleStepInput> steps;
}

class ScheduleSpan {
  const ScheduleSpan({required this.startClock, required this.endClock});

  final String startClock;
  final String endClock;
}

class ScheduleBreak {
  const ScheduleBreak({
    required this.id,
    required this.startClock,
    required this.endClock,
    required this.minutes,
    required this.kind,
    this.label,
  });

  final String id;
  final String startClock;
  final String endClock;
  final int minutes;

  /// `break` or `free_time`.
  final String kind;
  final String? label;
}

class GeneratedDay {
  const GeneratedDay({
    required this.dayNumber,
    required this.week,
    required this.type,
    required this.startClock,
    required this.endClock,
    required this.taskIds,
    required this.breaks,
  });

  final int dayNumber;
  final int week;

  /// `normal`, `practical` or `rest`.
  final String type;
  final String? startClock;
  final String? endClock;
  final List<String> taskIds;
  final List<ScheduleBreak> breaks;

  bool get isRest => type == 'rest';
  bool get isPractical => type == 'practical';
}

class GeneratedTaskPlacement {
  const GeneratedTaskPlacement({
    required this.taskId,
    required this.dayNumber,
    required this.order,
    required this.startClock,
    required this.endClock,
    required this.stepSpans,
    this.isManual = false,
  });

  final String taskId;
  final int dayNumber;
  final int order;
  final String startClock;
  final String endClock;
  final Map<String, ScheduleSpan> stepSpans;

  /// `true` when the user placed this task (day, position or start time).
  final bool isManual;
}

/// A manual placement saved by the user. The task keeps its identity; only its
/// position in the generated week changes.
class ScheduleOverrideInput {
  const ScheduleOverrideInput({
    required this.dayNumber,
    this.position,
    this.startClock,
  });

  /// Target plan day. Must be an existing study day.
  final int dayNumber;

  /// 1-based position inside that day. `null` appends.
  final int? position;

  /// Pinned `HH:mm` start. `null` lets the day timeline decide.
  final String? startClock;
}

class ScheduleGeneration {
  const ScheduleGeneration({
    required this.days,
    required this.placements,
    required this.practicalWeekdays,
  });

  final List<GeneratedDay> days;
  final Map<String, GeneratedTaskPlacement> placements;
  final List<int> practicalWeekdays;

  GeneratedDay day(int dayNumber) {
    return days.firstWhere((GeneratedDay day) => day.dayNumber == dayNumber);
  }
}

class ScheduleException implements Exception {
  const ScheduleException(this.message);

  final String message;

  @override
  String toString() => 'ScheduleException: $message';
}

/// Pure, deterministic redistribution of the existing plan.
///
/// Rules:
/// * Rest days never move and never receive tasks.
/// * Tasks stay inside their original week, in their original order.
/// * Each week's sequence is partitioned into contiguous groups, one per
///   non-rest day. Normal days get twice the target workload of practical days.
/// * No task is split, renamed or re-identified. User progress therefore maps
///   by the same task/step ids after a schedule change.
/// * Times are regenerated from each day's start clock, with 15-minute breaks
///   and the normal-day two-hour free block preserved.
abstract final class ScheduleEngine {
  static const int normalStartMinute = 8 * 60;
  static const int practicalStartMinute = 16 * 60;
  static const int breakMinutes = 15;
  static const int freeBlockMinutes = 120;
  static const int _breakAfterMinutes = 55;
  static const double _emptyDayPenalty = 1e12;

  static ScheduleGeneration generate({
    required List<ScheduleDayInput> days,
    required List<ScheduleTaskInput> tasks,
    required Iterable<int> practicalWeekdays,
    Map<String, ScheduleOverrideInput> overrides =
        const <String, ScheduleOverrideInput>{},
  }) {
    final List<int> weekdays = PracticalWeekdays.validate(practicalWeekdays);
    final List<ScheduleDayInput> sortedDays = List<ScheduleDayInput>.of(days)
      ..sort(
        (ScheduleDayInput a, ScheduleDayInput b) =>
            a.dayNumber.compareTo(b.dayNumber),
      );
    _validateInput(sortedDays, tasks);

    final Map<int, ScheduleDayInput> dayByNumber = <int, ScheduleDayInput>{
      for (final ScheduleDayInput day in sortedDays) day.dayNumber: day,
    };
    final Map<String, ScheduleTaskInput> taskById = <String, ScheduleTaskInput>{
      for (final ScheduleTaskInput task in tasks) task.id: task,
    };
    final Map<int, List<ScheduleTaskInput>> tasksByWeek =
        <int, List<ScheduleTaskInput>>{};
    for (final ScheduleTaskInput task in tasks) {
      final ScheduleDayInput? source = dayByNumber[task.sourceDayNumber];
      if (source == null) {
        throw ScheduleException(
          'task ${task.id} references missing day ${task.sourceDayNumber}',
        );
      }
      tasksByWeek
          .putIfAbsent(source.week, () => <ScheduleTaskInput>[])
          .add(task);
    }
    for (final List<ScheduleTaskInput> weekTasks in tasksByWeek.values) {
      weekTasks.sort(_compareTasks);
    }

    final Map<int, List<ScheduleDayInput>> daysByWeek =
        <int, List<ScheduleDayInput>>{};
    for (final ScheduleDayInput day in sortedDays) {
      daysByWeek.putIfAbsent(day.week, () => <ScheduleDayInput>[]).add(day);
    }

    // dayNumber -> ordered tasks, for every study day in the plan.
    final Map<int, List<ScheduleTaskInput>> byDay =
        <int, List<ScheduleTaskInput>>{};

    for (final MapEntry<int, List<ScheduleDayInput>> entry
        in daysByWeek.entries) {
      final List<ScheduleDayInput> weekDays = entry.value;
      final Set<int> practical = _resolvePracticalDays(weekDays, weekdays);
      final List<ScheduleDayInput> activeDays = <ScheduleDayInput>[
        for (final ScheduleDayInput day in weekDays)
          if (!day.isRest) day,
      ];
      if (activeDays.isEmpty && (tasksByWeek[entry.key]?.isNotEmpty ?? false)) {
        throw ScheduleException('week ${entry.key} has tasks but no study day');
      }

      final List<ScheduleTaskInput> weekTasks =
          tasksByWeek[entry.key] ?? const <ScheduleTaskInput>[];
      final List<List<ScheduleTaskInput>> grouped = _partition(
        tasks: weekTasks,
        days: activeDays,
        practical: practical,
      );
      for (int index = 0; index < activeDays.length; index++) {
        byDay[activeDays[index].dayNumber] = List<ScheduleTaskInput>.of(
          grouped[index],
        );
      }
    }

    _applyOverrides(byDay, overrides, taskById, dayByNumber);
    _validateSequence(byDay, tasks);

    final List<GeneratedDay> generatedDays = <GeneratedDay>[];
    final Map<String, GeneratedTaskPlacement> placements =
        <String, GeneratedTaskPlacement>{};

    for (final ScheduleDayInput day in sortedDays) {
      if (day.isRest) {
        generatedDays.add(
          GeneratedDay(
            dayNumber: day.dayNumber,
            week: day.week,
            type: 'rest',
            startClock: null,
            endClock: null,
            taskIds: const <String>[],
            breaks: const <ScheduleBreak>[],
          ),
        );
        continue;
      }
      final List<ScheduleTaskInput> dayTasks =
          byDay[day.dayNumber] ?? const <ScheduleTaskInput>[];
      final TimedDay timed = timeDay(
        dayNumber: day.dayNumber,
        week: day.week,
        tasks: dayTasks,
        practical: _isPractical(day, weekdays, daysByWeek),
        pinnedStarts: <String, String>{
          for (final MapEntry<String, ScheduleOverrideInput> override
              in overrides.entries)
            if (override.value.dayNumber == day.dayNumber &&
                override.value.startClock != null)
              override.key: override.value.startClock!,
        },
        manualIds: overrides.keys.toSet(),
      );
      generatedDays.add(timed.day);
      placements.addAll(timed.placements);
    }

    generatedDays.sort(
      (GeneratedDay a, GeneratedDay b) => a.dayNumber.compareTo(b.dayNumber),
    );
    final ScheduleGeneration result = ScheduleGeneration(
      days: generatedDays,
      placements: placements,
      practicalWeekdays: weekdays,
    );
    _validateResult(sortedDays, tasks, result);
    return result;
  }

  /// Whether [day] ended up practical after rest-day forwarding. The resolved
  /// set is recomputed from the week the day belongs to.
  static bool _isPractical(
    ScheduleDayInput day,
    List<int> weekdays,
    Map<int, List<ScheduleDayInput>> daysByWeek,
  ) {
    final List<ScheduleDayInput> weekDays =
        daysByWeek[day.week] ?? const <ScheduleDayInput>[];
    return _resolvePracticalDays(weekDays, weekdays).contains(day.dayNumber);
  }

  /// Removes overridden tasks from their automatic group and re-inserts them in
  /// the requested day at the requested position. Positions are clamped, so a
  /// stale position can never crash a rebuild.
  static void _applyOverrides(
    Map<int, List<ScheduleTaskInput>> byDay,
    Map<String, ScheduleOverrideInput> overrides,
    Map<String, ScheduleTaskInput> taskById,
    Map<int, ScheduleDayInput> dayByNumber,
  ) {
    if (overrides.isEmpty) return;

    for (final MapEntry<String, ScheduleOverrideInput> entry
        in overrides.entries) {
      final ScheduleTaskInput? task = taskById[entry.key];
      if (task == null) {
        throw ScheduleException(
          'override references unknown task ${entry.key}',
        );
      }
      final ScheduleDayInput? target = dayByNumber[entry.value.dayNumber];
      if (target == null) {
        throw ScheduleException(
          'override for ${entry.key} targets missing day '
          '${entry.value.dayNumber}',
        );
      }
      if (target.isRest) {
        throw ScheduleException(
          'override for ${entry.key} targets rest day ${target.dayNumber}',
        );
      }
      for (final List<ScheduleTaskInput> list in byDay.values) {
        list.removeWhere((ScheduleTaskInput item) => item.id == entry.key);
      }
    }

    final Map<int, List<MapEntry<String, ScheduleOverrideInput>>> perDay =
        <int, List<MapEntry<String, ScheduleOverrideInput>>>{};
    for (final MapEntry<String, ScheduleOverrideInput> entry
        in overrides.entries) {
      perDay
          .putIfAbsent(
            entry.value.dayNumber,
            () => <MapEntry<String, ScheduleOverrideInput>>[],
          )
          .add(entry);
    }

    for (final MapEntry<int, List<MapEntry<String, ScheduleOverrideInput>>>
        dayEntry
        in perDay.entries) {
      final List<ScheduleTaskInput> list = byDay[dayEntry.key]!;
      dayEntry.value.sort((
        MapEntry<String, ScheduleOverrideInput> a,
        MapEntry<String, ScheduleOverrideInput> b,
      ) {
        final int positionA = a.value.position ?? 1 << 20;
        final int positionB = b.value.position ?? 1 << 20;
        if (positionA != positionB) return positionA.compareTo(positionB);
        return _compareTasks(taskById[a.key]!, taskById[b.key]!);
      });
      for (final MapEntry<String, ScheduleOverrideInput> entry
          in dayEntry.value) {
        final int requested = entry.value.position ?? list.length + 1;
        final int position = requested.clamp(1, list.length + 1);
        list.insert(position - 1, taskById[entry.key]!);
      }
    }
  }

  /// The curriculum is a single sequence at day granularity: a task may never
  /// be scheduled on an earlier day than a task that precedes it in the source
  /// plan. Ordering *inside* a day is a soft preference the user may change.
  /// Automatic partitioning already guarantees this; a manual move can break
  /// it, so it is checked explicitly.
  static void _validateSequence(
    Map<int, List<ScheduleTaskInput>> byDay,
    List<ScheduleTaskInput> tasks,
  ) {
    final List<ScheduleTaskInput> canonical = List<ScheduleTaskInput>.of(tasks)
      ..sort(_compareTasks);
    final Map<String, int> dayOf = <String, int>{};
    for (final MapEntry<int, List<ScheduleTaskInput>> entry in byDay.entries) {
      for (final ScheduleTaskInput task in entry.value) {
        dayOf[task.id] = entry.key;
      }
    }
    if (dayOf.length != canonical.length) {
      throw const ScheduleException('task count changed while scheduling');
    }
    for (int index = 1; index < canonical.length; index++) {
      final int previous = dayOf[canonical[index - 1].id]!;
      final int current = dayOf[canonical[index].id]!;
      if (current < previous) {
        throw ScheduleException(
          'sequence violation: ${canonical[index].id} would move to day '
          '$current before ${canonical[index - 1].id} on day $previous',
        );
      }
    }
  }

  /// The selected weekday is moved forward to the next free study day when it
  /// lands on a rest day. This is exactly how the original plan turns the
  /// Friday rest day in week 5 into a Saturday practical day.
  static Set<int> _resolvePracticalDays(
    List<ScheduleDayInput> weekDays,
    List<int> weekdays,
  ) {
    final Set<int> practical = <int>{};
    for (final int weekday in weekdays) {
      final List<ScheduleDayInput> candidates = <ScheduleDayInput>[
        for (final ScheduleDayInput day in weekDays)
          if (day.date.weekday == weekday) day,
      ];
      if (candidates.isEmpty) continue;
      ScheduleDayInput? candidate = candidates.first;
      if (candidate.isRest || practical.contains(candidate.dayNumber)) {
        candidate = _nearestFreeDay(weekDays, candidate, practical);
      }
      if (candidate != null) practical.add(candidate.dayNumber);
    }
    return practical;
  }

  static ScheduleDayInput? _nearestFreeDay(
    List<ScheduleDayInput> weekDays,
    ScheduleDayInput start,
    Set<int> practical,
  ) {
    final int index = weekDays.indexOf(start);
    for (int i = index + 1; i < weekDays.length; i++) {
      final ScheduleDayInput day = weekDays[i];
      if (!day.isRest && !practical.contains(day.dayNumber)) return day;
    }
    for (int i = index - 1; i >= 0; i--) {
      final ScheduleDayInput day = weekDays[i];
      if (!day.isRest && !practical.contains(day.dayNumber)) return day;
    }
    return null;
  }

  static int _compareTasks(ScheduleTaskInput a, ScheduleTaskInput b) {
    final int byDay = a.sourceDayNumber.compareTo(b.sourceDayNumber);
    if (byDay != 0) return byDay;
    final int byOrder = a.sourceOrder.compareTo(b.sourceOrder);
    if (byOrder != 0) return byOrder;
    return a.id.compareTo(b.id);
  }

  /// Dynamic-programming partition of a week's ordered task list into one
  /// contiguous group per active day. Minimising squared deviation from the
  /// normal:2 / practical:1 targets keeps the days balanced without splitting
  /// a task or changing the sequence.
  static List<List<ScheduleTaskInput>> _partition({
    required List<ScheduleTaskInput> tasks,
    required List<ScheduleDayInput> days,
    required Set<int> practical,
  }) {
    final int n = tasks.length;
    final int k = days.length;
    if (k == 0) {
      if (n > 0) throw const ScheduleException('no active days for tasks');
      return const <List<ScheduleTaskInput>>[];
    }
    if (n == 0) {
      return List<List<ScheduleTaskInput>>.generate(
        k,
        (_) => const <ScheduleTaskInput>[],
        growable: false,
      );
    }

    final List<double> weights = <double>[
      for (final ScheduleDayInput day in days)
        practical.contains(day.dayNumber) ? 1.0 : 2.0,
    ];
    final double totalWeight = weights.fold<double>(
      0,
      (double sum, double weight) => sum + weight,
    );
    final int totalMinutes = tasks.fold<int>(
      0,
      (int sum, ScheduleTaskInput task) => sum + task.minutes,
    );
    final List<double> targets = <double>[
      for (final double weight in weights)
        totalWeight == 0 ? 0 : totalMinutes * weight / totalWeight,
    ];

    final List<int> prefix = List<int>.filled(n + 1, 0);
    for (int i = 0; i < n; i++) {
      prefix[i + 1] = prefix[i] + tasks[i].minutes;
    }

    final List<List<double>> cost = List<List<double>>.generate(
      k + 1,
      (_) => List<double>.filled(n + 1, double.infinity),
      growable: false,
    );
    final List<List<int>> split = List<List<int>>.generate(
      k + 1,
      (_) => List<int>.filled(n + 1, -1),
      growable: false,
    );
    cost[0][0] = 0;

    for (int day = 1; day <= k; day++) {
      for (int end = 0; end <= n; end++) {
        for (int start = 0; start <= end; start++) {
          final double previous = cost[day - 1][start];
          if (previous == double.infinity) continue;
          final int groupMinutes = prefix[end] - prefix[start];
          final bool empty = end == start;
          final double penalty = empty && n >= k ? _emptyDayPenalty : 0;
          final double difference = groupMinutes - targets[day - 1];
          final double candidate = previous + difference * difference + penalty;
          if (candidate < cost[day][end]) {
            cost[day][end] = candidate;
            split[day][end] = start;
          }
        }
      }
    }

    if (split[k][n] < 0) {
      throw const ScheduleException('could not partition the week');
    }

    final List<List<ScheduleTaskInput>> groups =
        List<List<ScheduleTaskInput>>.filled(
          k,
          const <ScheduleTaskInput>[],
          growable: false,
        );
    int end = n;
    for (int day = k; day >= 1; day--) {
      final int start = split[day][end];
      groups[day - 1] = tasks.sublist(start, end);
      end = start;
    }
    if (end != 0) {
      throw const ScheduleException('partition did not consume every task');
    }
    if (n >= k &&
        groups.any((List<ScheduleTaskInput> group) => group.isEmpty)) {
      throw const ScheduleException('partition left a study day empty');
    }
    return groups;
  }

  /// Times one day. Public so the repository can re-time a single day of the
  /// original (template) schedule after a manual move without regenerating the
  /// whole plan.
  static TimedDay timeDay({
    required int dayNumber,
    required int week,
    required List<ScheduleTaskInput> tasks,
    required bool practical,
    int? startMinute,
    Map<String, String> pinnedStarts = const <String, String>{},
    Set<String> manualIds = const <String>{},
  }) {
    int current =
        startMinute ?? (practical ? practicalStartMinute : normalStartMinute);
    int sinceBreak = 0;
    int scheduledWork = 0;
    bool freeBlockInserted = false;
    final int dayMinutes = tasks.fold<int>(
      0,
      (int sum, ScheduleTaskInput task) => sum + task.minutes,
    );
    final List<ScheduleBreak> breaks = <ScheduleBreak>[];
    final Map<String, GeneratedTaskPlacement> placements =
        <String, GeneratedTaskPlacement>{};

    for (int index = 0; index < tasks.length; index++) {
      final ScheduleTaskInput task = tasks[index];
      final String? pinned = pinnedStarts[task.id];

      if (pinned != null) {
        // A pinned start is the user's decision: honour it exactly and do not
        // insert a break or the free block in front of it.
        final int at = _minutesOf(pinned);
        if (at < current) {
          throw ScheduleException(
            'manual start for ${task.id} overlaps the previous task',
          );
        }
        current = at;
        sinceBreak = 0;
      } else {
        if (index > 0 && sinceBreak >= _breakAfterMinutes) {
          breaks.add(
            _break(
              id: '$dayNumber-break-${breaks.length + 1}',
              start: current,
              minutes: breakMinutes,
              kind: 'break',
            ),
          );
          current += breakMinutes;
          sinceBreak = 0;
        }

        if (!practical &&
            !freeBlockInserted &&
            index > 0 &&
            scheduledWork >= dayMinutes / 2) {
          breaks.add(
            _break(
              id: '$dayNumber-free-${breaks.length + 1}',
              start: current,
              minutes: freeBlockMinutes,
              kind: 'free_time',
            ),
          );
          current += freeBlockMinutes;
          freeBlockInserted = true;
          sinceBreak = 0;
        }
      }

      final int taskStart = current;
      final Map<String, ScheduleSpan> stepSpans = <String, ScheduleSpan>{};
      final List<ScheduleStepInput> steps =
          List<ScheduleStepInput>.of(task.steps)..sort(
            (ScheduleStepInput a, ScheduleStepInput b) =>
                a.order.compareTo(b.order),
          );
      for (final ScheduleStepInput step in steps) {
        final int stepStart = current;
        current += step.minutes;
        stepSpans[step.id] = ScheduleSpan(
          startClock: _clock(stepStart),
          endClock: _clock(current),
        );
      }
      placements[task.id] = GeneratedTaskPlacement(
        taskId: task.id,
        dayNumber: dayNumber,
        order: index + 1,
        startClock: _clock(taskStart),
        endClock: _clock(current),
        stepSpans: stepSpans,
        isManual: manualIds.contains(task.id),
      );
      sinceBreak += task.minutes;
      scheduledWork += task.minutes;
    }

    final int dayEnd = tasks.isEmpty
        ? (startMinute ??
              (practical ? practicalStartMinute : normalStartMinute))
        : current;
    final int dayStart = tasks.isEmpty
        ? dayEnd
        : _minutesOf(placements[tasks.first.id]!.startClock);
    if (dayEnd >= 24 * 60) {
      throw ScheduleException('day $dayNumber runs past midnight');
    }
    return TimedDay(
      day: GeneratedDay(
        dayNumber: dayNumber,
        week: week,
        type: practical ? 'practical' : 'normal',
        startClock: _clock(dayStart),
        endClock: _clock(dayEnd),
        taskIds: <String>[for (final ScheduleTaskInput task in tasks) task.id],
        breaks: breaks,
      ),
      placements: placements,
    );
  }

  static ScheduleBreak _break({
    required String id,
    required int start,
    required int minutes,
    required String kind,
  }) {
    return ScheduleBreak(
      id: id,
      startClock: _clock(start),
      endClock: _clock(start + minutes),
      minutes: minutes,
      kind: kind,
    );
  }

  static String _clock(int minutes) {
    if (minutes < 0 || minutes >= 24 * 60) {
      throw ScheduleException('clock out of range: $minutes');
    }
    final int hour = minutes ~/ 60;
    final int minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  static int _minutesOf(String clock) {
    final List<String> parts = clock.split(':');
    if (parts.length != 2) {
      throw ScheduleException('bad clock $clock');
    }
    final int hour = int.tryParse(parts[0]) ?? -1;
    final int minute = int.tryParse(parts[1]) ?? -1;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw ScheduleException('bad clock $clock');
    }
    return hour * 60 + minute;
  }

  static void _validateInput(
    List<ScheduleDayInput> days,
    List<ScheduleTaskInput> tasks,
  ) {
    final Set<int> dayNumbers = <int>{};
    for (final ScheduleDayInput day in days) {
      if (!dayNumbers.add(day.dayNumber)) {
        throw ScheduleException('duplicate day ${day.dayNumber}');
      }
      if (day.dayNumber < 1) {
        throw ScheduleException('invalid day ${day.dayNumber}');
      }
    }
    final Set<String> taskIds = <String>{};
    for (final ScheduleTaskInput task in tasks) {
      if (!taskIds.add(task.id)) {
        throw ScheduleException('duplicate task ${task.id}');
      }
      if (task.minutes < 0) {
        throw ScheduleException('negative duration for ${task.id}');
      }
      for (final ScheduleStepInput step in task.steps) {
        if (step.minutes < 0) {
          throw ScheduleException('negative step duration for ${step.id}');
        }
      }
    }
  }

  static void _validateResult(
    List<ScheduleDayInput> inputDays,
    List<ScheduleTaskInput> tasks,
    ScheduleGeneration result,
  ) {
    if (result.days.length != inputDays.length) {
      throw const ScheduleException('generated day count changed');
    }
    for (final GeneratedDay day in result.days) {
      if (day.isRest && day.taskIds.isNotEmpty) {
        throw ScheduleException('rest day ${day.dayNumber} has tasks');
      }
      if (!day.isRest) {
        if (day.startClock == null || day.endClock == null) {
          throw ScheduleException('day ${day.dayNumber} has no clocks');
        }
        final int start = _minutesOf(day.startClock!);
        final int end = _minutesOf(day.endClock!);
        if (end < start) {
          throw ScheduleException('day ${day.dayNumber} ends before it starts');
        }
        int previousEnd = start;
        for (final String taskId in day.taskIds) {
          final GeneratedTaskPlacement? placement = result.placements[taskId];
          if (placement == null) {
            throw ScheduleException('missing placement for $taskId');
          }
          if (placement.dayNumber != day.dayNumber) {
            throw ScheduleException('$taskId is placed on the wrong day');
          }
          final int taskStart = _minutesOf(placement.startClock);
          final int taskEnd = _minutesOf(placement.endClock);
          if (taskStart < previousEnd || taskEnd < taskStart) {
            throw ScheduleException('overlapping task $taskId');
          }
          previousEnd = taskEnd;
        }
        if (previousEnd > end) {
          throw ScheduleException('day ${day.dayNumber} ends too early');
        }
      }
    }
    if (result.placements.length != tasks.length) {
      throw const ScheduleException('task count changed during generation');
    }
    for (final ScheduleTaskInput task in tasks) {
      if (!result.placements.containsKey(task.id)) {
        throw ScheduleException('task ${task.id} was not scheduled');
      }
    }
  }
}

class TimedDay {
  const TimedDay({required this.day, required this.placements});

  final GeneratedDay day;
  final Map<String, GeneratedTaskPlacement> placements;
}
