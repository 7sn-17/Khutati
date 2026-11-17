import 'dart:convert';

/// Typed, validated view of `khutati_plan_data.json`.
///
/// This layer is deliberately free of Flutter and Drift imports: the dataset is
/// parsed and reconciled exactly once, then the import pipeline writes it into
/// the template tables (PRD sections 3.1 and 6.1).
///
/// Parsing is strict on purpose. A typo in the bundled plan must fail the build
/// in CI, never reach a device as silent bad data.

/// The only accepted grand total for the 68-day plan (PRD section 3.1).
const int kPlanGrandTotalMinutes = 480 * 60 + 9;

class PlanDatasetException implements Exception {
  const PlanDatasetException(this.message);

  final String message;

  @override
  String toString() => 'PlanDatasetException: $message';
}

abstract final class PlanItemTypes {
  static const String video = 'video';
  static const String courseQuestions = 'course_questions';
}

abstract final class PlanDayTypes {
  static const String normal = 'normal';
  static const String practical = 'practical';
  static const String rest = 'rest';
}

class PlanDataset {
  const PlanDataset({required this.meta, required this.days});

  final PlanMeta meta;
  final List<PlanDay> days;

  factory PlanDataset.parse(String jsonText) {
    final Map<String, dynamic> root = _asMap(jsonDecode(jsonText), 'root');
    final PlanMeta meta = PlanMeta.fromJson(_asMap(root['meta'], 'meta'));
    final List<Object?> rawDays = _asList(root['days'], 'days');
    final List<PlanDay> days = <PlanDay>[
      for (int i = 0; i < rawDays.length; i++)
        PlanDay.fromJson(_asMap(rawDays[i], 'days[$i]')),
    ];

    final PlanDataset dataset = PlanDataset(meta: meta, days: days);
    dataset.validate();
    return dataset;
  }

  int get totalMinutes =>
      days.fold<int>(0, (int sum, PlanDay day) => sum + day.totalMinutes);

  int get itemCount =>
      days.fold<int>(0, (int sum, PlanDay day) => sum + day.items.length);

  int get videoCount => days.fold<int>(
    0,
    (int sum, PlanDay day) =>
        sum + day.items.where((PlanItem i) => i.isVideo).length,
  );

  int get courseQuestionCount => days.fold<int>(
    0,
    (int sum, PlanDay day) =>
        sum + day.items.where((PlanItem i) => i.isCourseQuestions).length,
  );

  /// Re-derives every numeric claim from raw items and compares it with the
  /// dataset's own totals and the PRD's fixed expectations.
  void validate() {
    if (days.length != meta.totalDays) {
      throw PlanDatasetException(
        'expected ${meta.totalDays} days, found ${days.length}',
      );
    }
    if (days.length != 68) {
      throw const PlanDatasetException('the plan must contain 68 days');
    }

    final List<int> restDays = <int>[
      for (final PlanDay day in days)
        if (day.type == PlanDayTypes.rest) day.dayNumber,
    ];
    if (!_sameInts(restDays, meta.restDays)) {
      throw PlanDatasetException(
        'rest days ${restDays.join(',')} do not match meta ${meta.restDays.join(',')}',
      );
    }
    final List<int> practicalDays = <int>[
      for (final PlanDay day in days)
        if (day.type == PlanDayTypes.practical) day.dayNumber,
    ];
    if (!_sameInts(practicalDays, meta.practicalDays)) {
      throw const PlanDatasetException(
        'practical days do not match the dataset metadata',
      );
    }

    final Set<String> ids = <String>{};
    final Map<String, int> attendanceBySubject = <String, int>{};
    final Map<String, int> studyBySubject = <String, int>{};
    final Map<String, int> questionsBySubject = <String, int>{};
    int totalAttendance = 0;
    int totalStudy = 0;
    int totalQuestions = 0;

    for (final PlanDay day in days) {
      final DateTime expectedDate = DateTime(
        meta.startDate.year,
        meta.startDate.month,
        meta.startDate.day + day.dayNumber - 1,
      );
      if (!_sameDate(expectedDate, day.date)) {
        throw PlanDatasetException(
          'day ${day.dayNumber} date ${_dateString(day.date)} does not match the start date',
        );
      }
      if (day.week != ((day.dayNumber - 1) ~/ 7) + 1) {
        throw PlanDatasetException('day ${day.dayNumber} has the wrong week');
      }

      for (final PlanItem item in day.items) {
        if (item.id.isEmpty) {
          throw PlanDatasetException(
            'day ${day.dayNumber} has an item without an id',
          );
        }
        if (!ids.add(item.id)) {
          throw PlanDatasetException('duplicate item id ${item.id}');
        }
        if (!meta.subjectKeys.contains(item.subjectKey)) {
          throw PlanDatasetException(
            'item ${item.id} references unknown subject ${item.subjectKey}',
          );
        }
        if (item.isVideo) {
          if (item.attendance == null || item.study == null) {
            throw PlanDatasetException(
              'video ${item.id} must have attendance and study spans',
            );
          }
          totalAttendance += item.attendance!.minutes;
          totalStudy += item.study!.minutes;
          attendanceBySubject.update(
            item.subjectKey,
            (int v) => v + item.attendance!.minutes,
            ifAbsent: () => item.attendance!.minutes,
          );
          studyBySubject.update(
            item.subjectKey,
            (int v) => v + item.study!.minutes,
            ifAbsent: () => item.study!.minutes,
          );
        } else if (item.isCourseQuestions) {
          if (item.attendance != null || item.study == null) {
            throw PlanDatasetException(
              'course questions ${item.id} must have a single study span',
            );
          }
          totalQuestions += item.study!.minutes;
          questionsBySubject.update(
            item.subjectKey,
            (int v) => v + item.study!.minutes,
            ifAbsent: () => item.study!.minutes,
          );
        } else {
          throw PlanDatasetException(
            'item ${item.id} has unknown type ${item.type}',
          );
        }
      }

      final int derived =
          day.attendanceMinutes + day.studyMinutes + day.questionMinutes;
      if (derived != day.statedStudyMinutes) {
        throw PlanDatasetException(
          'day ${day.dayNumber}: derived $derived min but the page states '
          '${day.statedStudyMinutes} min',
        );
      }
      final int? stated = day.computedTotalMinutes;
      if (stated != null && stated != derived) {
        throw PlanDatasetException(
          'day ${day.dayNumber}: computed total $stated != derived $derived',
        );
      }
    }

    final int total = totalAttendance + totalStudy + totalQuestions;
    if (total != kPlanGrandTotalMinutes) {
      throw PlanDatasetException(
        'grand total $total min does not equal 480 h 9 min',
      );
    }
    if (meta.statedTotals.containsKey('attendance') &&
        meta.statedTotals['attendance'] != totalAttendance) {
      throw const PlanDatasetException('attendance total does not reconcile');
    }
    if (meta.statedTotals.containsKey('study') &&
        meta.statedTotals['study'] != totalStudy) {
      throw const PlanDatasetException('study total does not reconcile');
    }
    if (meta.statedTotals.containsKey('courses') &&
        meta.statedTotals['courses'] != totalQuestions) {
      throw const PlanDatasetException(
        'course-question total does not reconcile',
      );
    }
    if (meta.statedTotals.containsKey('all') &&
        meta.statedTotals['all'] != total) {
      throw const PlanDatasetException('overall total does not reconcile');
    }

    for (final PlanSubject subject in meta.subjects) {
      final int attendance = attendanceBySubject[subject.key] ?? 0;
      final int study = studyBySubject[subject.key] ?? 0;
      final int questions = questionsBySubject[subject.key] ?? 0;
      if (attendance != subject.attendanceMinutes ||
          study != subject.studyMinutes ||
          questions != subject.courseMinutes) {
        throw PlanDatasetException(
          'subject ${subject.key} does not reconcile with page 2 totals',
        );
      }
      if (subject.totalMinutes != attendance + study + questions) {
        throw PlanDatasetException(
          'subject ${subject.key} total does not equal its parts',
        );
      }
    }

    if (meta.studyDays !=
        days.where((PlanDay d) => d.type != PlanDayTypes.rest).length) {
      throw const PlanDatasetException('study day count does not match');
    }
  }
}

class PlanMeta {
  const PlanMeta({
    required this.name,
    required this.source,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    required this.studyDays,
    required this.restDays,
    required this.practicalDays,
    required this.statedTotals,
    required this.subjects,
  });

  factory PlanMeta.fromJson(Map<String, dynamic> json) {
    final List<PlanSubject> subjects = <PlanSubject>[
      for (final Object? raw in _asList(json['subjects'], 'meta.subjects'))
        PlanSubject.fromJson(_asMap(raw, 'meta.subjects[]')),
    ];
    final Map<String, dynamic> totals = _asMap(
      json['statedTotals'],
      'meta.statedTotals',
    );

    return PlanMeta(
      name: _asString(json['name'], 'meta.name'),
      source: _asString(json['source'], 'meta.source'),
      startDate: _asDate(json['startDate'], 'meta.startDate'),
      endDate: _asDate(json['endDate'], 'meta.endDate'),
      totalDays: _asInt(json['totalDays'], 'meta.totalDays'),
      studyDays: _asInt(json['studyDays'], 'meta.studyDays'),
      restDays: _asIntList(json['restDays'], 'meta.restDays'),
      practicalDays: _asIntList(json['practicalDays'], 'meta.practicalDays'),
      statedTotals: <String, int>{
        for (final MapEntry<String, dynamic> entry in totals.entries)
          entry.key: _duration(entry.value, 'meta.statedTotals.${entry.key}'),
      },
      subjects: subjects,
    );
  }

  final String name;
  final String source;
  final DateTime startDate;
  final DateTime endDate;
  final int totalDays;
  final int studyDays;
  final List<int> restDays;
  final List<int> practicalDays;

  /// Keyed by `attendance`, `study`, `courses`, `all`.
  final Map<String, int> statedTotals;
  final List<PlanSubject> subjects;

  Set<String> get subjectKeys => <String>{
    for (final PlanSubject subject in subjects) subject.key,
  };
}

class PlanSubject {
  const PlanSubject({
    required this.key,
    required this.name,
    required this.instructor,
    required this.attendanceMinutes,
    required this.studyMinutes,
    required this.courseMinutes,
    required this.totalMinutes,
  });

  factory PlanSubject.fromJson(Map<String, dynamic> json) {
    return PlanSubject(
      key: _asString(json['key'], 'subject.key'),
      name: _asString(json['name'], 'subject.name'),
      instructor: _asString(json['instructor'], 'subject.instructor'),
      attendanceMinutes: _duration(json['attendance'], 'subject.attendance'),
      studyMinutes: _duration(json['study'], 'subject.study'),
      courseMinutes: _duration(json['courses'], 'subject.courses'),
      totalMinutes: _duration(json['total'], 'subject.total'),
    );
  }

  final String key;
  final String name;
  final String instructor;
  final int attendanceMinutes;
  final int studyMinutes;
  final int courseMinutes;
  final int totalMinutes;
}

class PlanDay {
  const PlanDay({
    required this.id,
    required this.dayNumber,
    required this.date,
    required this.week,
    required this.type,
    required this.statedStudyMinutes,
    required this.sections,
    required this.interludes,
    this.sourcePage,
    this.headerTitle,
    this.title,
    this.note,
    this.startClock,
    this.endClock,
    this.computedTotalMinutes,
  });

  factory PlanDay.fromJson(Map<String, dynamic> json) {
    final List<PlanSection> sections = <PlanSection>[
      for (final Object? raw in _asList(
        json['sections'] ?? const <Object?>[],
        'day.sections',
      ))
        PlanSection.fromJson(_asMap(raw, 'day.sections[]')),
    ];
    final List<PlanInterlude> interludes = <PlanInterlude>[
      for (final Object? raw in _asList(
        json['interludes'] ?? const <Object?>[],
        'day.interludes',
      ))
        PlanInterlude.fromJson(_asMap(raw, 'day.interludes[]')),
    ];
    final Map<String, dynamic>? computed = json['computed'] == null
        ? null
        : _asMap(json['computed'], 'day.computed');

    return PlanDay(
      id: _asString(json['id'], 'day.id'),
      dayNumber: _asInt(json['day'], 'day.day'),
      date: _asDate(json['date'], 'day.date'),
      week: _asInt(json['week'], 'day.week'),
      sourcePage: _asIntOrNull(json['sourcePage']),
      type: _asString(json['type'], 'day.type'),
      headerTitle: _asStringOrNull(json['headerTitle']),
      title: _asStringOrNull(json['title']),
      note: _asStringOrNull(json['note']),
      statedStudyMinutes: _asInt(
        json['statedStudyMinutes'],
        'day.statedStudyMinutes',
      ),
      startClock: _asStringOrNull(json['start']),
      endClock: _asStringOrNull(json['end']),
      computedTotalMinutes: computed == null
          ? null
          : _asInt(computed['totalMinutes'], 'day.computed.totalMinutes'),
      sections: sections,
      interludes: interludes,
    );
  }

  final String id;
  final int dayNumber;
  final DateTime date;
  final int week;
  final int? sourcePage;
  final String type;
  final String? headerTitle;
  final String? title;
  final String? note;
  final int statedStudyMinutes;
  final String? startClock;
  final String? endClock;
  final int? computedTotalMinutes;
  final List<PlanSection> sections;
  final List<PlanInterlude> interludes;

  String? get displayTitle => headerTitle ?? title;
  bool get isRest => type == PlanDayTypes.rest;
  bool get isPractical => type == PlanDayTypes.practical;

  List<PlanItem> get items => <PlanItem>[
    for (final PlanSection section in sections)
      for (final PlanPeriod period in section.periods) ...period.items,
  ];

  int get attendanceMinutes => items.fold<int>(
    0,
    (int sum, PlanItem item) => sum + item.attendanceMinutes,
  );
  int get studyMinutes =>
      items.fold<int>(0, (int sum, PlanItem item) => sum + item.studyMinutes);
  int get questionMinutes => items.fold<int>(
    0,
    (int sum, PlanItem item) => sum + item.questionMinutes,
  );
  int get totalMinutes => attendanceMinutes + studyMinutes + questionMinutes;
}

class PlanSection {
  const PlanSection({
    required this.subjectName,
    required this.subjectKey,
    required this.rangeText,
    required this.periods,
  });

  factory PlanSection.fromJson(Map<String, dynamic> json) {
    final String subjectName = _asString(json['subject'], 'section.subject');
    final String subjectKey = _asString(
      json['subjectKey'],
      'section.subjectKey',
    );

    return PlanSection(
      subjectName: subjectName,
      subjectKey: subjectKey,
      rangeText: _asString(json['rangeText'], 'section.rangeText'),
      periods: <PlanPeriod>[
        for (final Object? raw in _asList(json['periods'], 'section.periods'))
          PlanPeriod.fromJson(
            _asMap(raw, 'section.periods[]'),
            subjectKey: subjectKey,
            subjectName: subjectName,
          ),
      ],
    );
  }

  final String subjectName;
  final String subjectKey;
  final String rangeText;
  final List<PlanPeriod> periods;
}

class PlanPeriod {
  const PlanPeriod({
    required this.index,
    required this.start,
    required this.end,
    required this.items,
  });

  factory PlanPeriod.fromJson(
    Map<String, dynamic> json, {
    required String subjectKey,
    required String subjectName,
  }) {
    final int index = _asInt(json['index'], 'period.index');
    return PlanPeriod(
      index: index,
      start: _asString(json['start'], 'period.start'),
      end: _asString(json['end'], 'period.end'),
      items: <PlanItem>[
        for (final Object? raw in _asList(json['items'], 'period.items'))
          PlanItem.fromJson(
            _asMap(raw, 'period.items[]'),
            subjectKey: subjectKey,
            subjectName: subjectName,
            periodIndex: index,
          ),
      ],
    );
  }

  final int index;
  final String start;
  final String end;
  final List<PlanItem> items;
}

class PlanItem {
  const PlanItem({
    required this.id,
    required this.type,
    required this.group,
    required this.title,
    required this.subjectKey,
    required this.subjectName,
    required this.periodIndex,
    this.attendance,
    this.study,
  });

  factory PlanItem.fromJson(
    Map<String, dynamic> json, {
    required String subjectKey,
    required String subjectName,
    required int periodIndex,
  }) {
    return PlanItem(
      id: _asString(json['id'], 'item.id'),
      type: _asString(json['type'], 'item.type'),
      group: _asString(json['group'], 'item.group'),
      title: _asString(json['title'], 'item.title'),
      subjectKey: subjectKey,
      subjectName: subjectName,
      periodIndex: periodIndex,
      attendance: json['attendance'] == null
          ? null
          : PlanSpan.fromJson(_asMap(json['attendance'], 'item.attendance')),
      study: json['study'] == null
          ? null
          : PlanSpan.fromJson(_asMap(json['study'], 'item.study')),
    );
  }

  final String id;
  final String type;
  final String group;
  final String title;
  final String subjectKey;
  final String subjectName;
  final int periodIndex;
  final PlanSpan? attendance;
  final PlanSpan? study;

  bool get isVideo => type == PlanItemTypes.video;
  bool get isCourseQuestions => type == PlanItemTypes.courseQuestions;

  int get attendanceMinutes => attendance?.minutes ?? 0;

  /// Study minutes for videos only. Course-question hours are tracked in
  /// [questionMinutes] so analytics keep the three buckets separate (PRD 5.7).
  int get studyMinutes => isVideo ? (study?.minutes ?? 0) : 0;
  int get questionMinutes => isCourseQuestions ? (study?.minutes ?? 0) : 0;

  /// The page-printed span for the task as a whole.
  String? get startClock => attendance?.start ?? study?.start;
  String? get endClock => study?.end ?? attendance?.end;
}

class PlanSpan {
  const PlanSpan({
    required this.start,
    required this.end,
    required this.minutes,
  });

  factory PlanSpan.fromJson(Map<String, dynamic> json) {
    return PlanSpan(
      start: _asString(json['start'], 'span.start'),
      end: _asString(json['end'], 'span.end'),
      minutes: _asInt(json['minutes'], 'span.minutes'),
    );
  }

  final String start;
  final String end;
  final int minutes;
}

class PlanInterlude {
  const PlanInterlude({
    required this.type,
    required this.afterPeriod,
    required this.start,
    required this.end,
    required this.minutes,
    this.label,
  });

  factory PlanInterlude.fromJson(Map<String, dynamic> json) {
    return PlanInterlude(
      type: _asString(json['type'], 'interlude.type'),
      afterPeriod: _asInt(json['afterPeriod'], 'interlude.afterPeriod'),
      start: _asString(json['start'], 'interlude.start'),
      end: _asString(json['end'], 'interlude.end'),
      minutes: _asInt(json['minutes'], 'interlude.minutes'),
      label: _asStringOrNull(json['label']),
    );
  }

  final String type;
  final int afterPeriod;
  final String start;
  final String end;
  final int minutes;
  final String? label;

  bool get isBreak => type == 'break';
  bool get isFreeTime => type == 'free_time';
}

// ---------------------------------------------------------------------------
// Strict JSON helpers. `jsonDecode` returns dynamic; these convert once so no
// `dynamic` call escapes into the rest of the parser (strict-casts is on).
// ---------------------------------------------------------------------------

Map<String, dynamic> _asMap(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map<Object?, Object?>) return value.cast<String, dynamic>();
  throw PlanDatasetException('$field must be an object');
}

List<Object?> _asList(Object? value, String field) {
  if (value is List<Object?>) return value;
  throw PlanDatasetException('$field must be a list');
}

String _asString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw PlanDatasetException('$field must be a non-empty string');
}

String? _asStringOrNull(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int _asInt(Object? value, String field) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw PlanDatasetException('$field must be a number');
}

int? _asIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

List<int> _asIntList(Object? value, String field) {
  return <int>[
    for (final Object? entry in _asList(value, field))
      _asInt(entry, '$field[]'),
  ];
}

DateTime _asDate(Object? value, String field) {
  final String raw = _asString(value, field);
  final List<String> parts = raw.split('-');
  if (parts.length != 3) {
    throw PlanDatasetException('$field must be YYYY-MM-DD, got $raw');
  }
  final int? year = int.tryParse(parts[0]);
  final int? month = int.tryParse(parts[1]);
  final int? day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    throw PlanDatasetException('$field must be YYYY-MM-DD, got $raw');
  }
  return DateTime(year, month, day);
}

/// Parses the PDF's `"70 س 6 د"` duration strings. Pure Dart so it can run
/// before Flutter (and its localization delegates) is initialized.
int _duration(Object? value, String field) {
  if (value is int) return value;
  if (value is! String) {
    throw PlanDatasetException('$field must be a duration string');
  }
  final Iterable<RegExpMatch> matches = RegExp(r'(\d+)\s*([سد])')
      .allMatches(value);
  if (matches.isEmpty) {
    throw PlanDatasetException('$field is not a duration: $value');
  }
  int minutes = 0;
  for (final RegExpMatch match in matches) {
    final int amount = int.parse(match.group(1)!);
    minutes += match.group(2) == 'س' ? amount * 60 : amount;
  }
  return minutes;
}

bool _sameInts(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
