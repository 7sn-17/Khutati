import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/plan/plan_dataset.dart';
import '../../domain/plan/plan_task.dart';
import '../database/app_database.dart';
import '../database/tables.dart';

/// The stable id of the single built-in plan (PRD section 2, decision 4).
const String kPlanId = 'medx-68';

/// Result of a bootstrap attempt, useful for logs and tests.
class PlanImportResult {
  const PlanImportResult({
    required this.imported,
    required this.datasetVersion,
    required this.days,
    required this.tasks,
    required this.steps,
  });

  final bool imported;
  final int datasetVersion;
  final int days;
  final int tasks;
  final int steps;
}

/// Writes the validated JSON dataset into the read-only template tables.
///
/// Guarantees:
/// * the whole import is one transaction — a crash leaves the old plan intact;
/// * a matching [PlanRow.datasetVersion] skips the work on every later launch;
/// * user tables are never touched, so progress survives a dataset refresh;
/// * the plan content in the DB is byte-for-byte derived from the bundle.
class PlanImporter {
  PlanImporter(this._db);

  final AppDatabase _db;

  /// Content hash used as the dataset version. FNV-1a keeps the value stable
  /// across platforms and much cheaper than storing the whole JSON in the DB.
  static int versionOf(String jsonText) {
    int hash = 0x811c9dc5;
    for (final int byte in utf8.encode(jsonText)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  Future<bool> isImported(int datasetVersion) async {
    final PlanRow? row = await (_db.select(
      _db.plans,
    )..where((Plans t) => t.id.equals(kPlanId))).getSingleOrNull();
    return row != null && row.datasetVersion == datasetVersion;
  }

  Future<PlanRow?> currentPlan() {
    return (_db.select(
      _db.plans,
    )..where((Plans t) => t.id.equals(kPlanId))).getSingleOrNull();
  }

  /// Parses and validates first: an invalid dataset never touches the database.
  Future<PlanImportResult> ensureImported(String jsonText) async {
    final int version = versionOf(jsonText);
    final PlanRow? existing = await currentPlan();

    if (existing != null && existing.datasetVersion == version) {
      // Hash matches: skip the expensive parse entirely. The bundled plan is
      // therefore free on every launch after the first.
      return PlanImportResult(
        imported: false,
        datasetVersion: version,
        days: existing.totalDays,
        tasks: (await _db.select(_db.tasks).get()).length,
        steps: (await _db.select(_db.steps).get()).length,
      );
    }

    final PlanDataset dataset = PlanDataset.parse(jsonText);
    return importDataset(dataset, version);
  }

  /// Exposed for tests and for a future "re-import dataset" maintenance action.
  Future<PlanImportResult> importDataset(
    PlanDataset dataset,
    int datasetVersion,
  ) async {
    final _TemplateRows rows = _buildRows(dataset, datasetVersion);

    await _db.transaction(() async {
      // Children first: foreign keys are ON (see AppDatabase.beforeOpen).
      await _db.delete(_db.steps).go();
      await _db.delete(_db.tasks).go();
      await _db.delete(_db.breaks).go();
      await _db.delete(_db.lessons).go();
      await _db.delete(_db.chapters).go();
      await _db.delete(_db.days).go();
      await _db.delete(_db.subjects).go();
      await _db.delete(_db.plans).go();

      await _db.batch((Batch batch) {
        batch.insert(_db.plans, rows.plan);
        batch.insertAll(_db.subjects, rows.subjects);
        batch.insertAll(_db.chapters, rows.chapters);
        batch.insertAll(_db.days, rows.days);
        batch.insertAll(_db.tasks, rows.tasks);
        batch.insertAll(_db.steps, rows.steps);
        batch.insertAll(_db.breaks, rows.breaks);
      });
    });

    return PlanImportResult(
      imported: true,
      datasetVersion: datasetVersion,
      days: rows.days.length,
      tasks: rows.tasks.length,
      steps: rows.steps.length,
    );
  }

  _TemplateRows _buildRows(PlanDataset dataset, int datasetVersion) {
    final DateTime start = DateTime(
      dataset.meta.startDate.year,
      dataset.meta.startDate.month,
      dataset.meta.startDate.day,
    );

    final PlansCompanion plan = PlansCompanion.insert(
      id: kPlanId,
      name: dataset.meta.name,
      datasetVersion: datasetVersion,
      startDate: start,
      totalDays: dataset.days.length,
      studyDays: dataset.meta.studyDays,
      totalPlannedMinutes: dataset.totalMinutes,
    );

    final List<SubjectsCompanion> subjects = <SubjectsCompanion>[
      for (int i = 0; i < dataset.meta.subjects.length; i++)
        SubjectsCompanion.insert(
          id: dataset.meta.subjects[i].key,
          key: dataset.meta.subjects[i].key,
          nameAr: dataset.meta.subjects[i].name,
          instructor: dataset.meta.subjects[i].instructor,
          accentHex: _subjectAccent(dataset.meta.subjects[i].key),
          sortOrder: i,
          attendanceMinutes: Value<int>(
            dataset.meta.subjects[i].attendanceMinutes,
          ),
          studyMinutes: Value<int>(dataset.meta.subjects[i].studyMinutes),
          courseMinutes: Value<int>(dataset.meta.subjects[i].courseMinutes),
        ),
    ];

    final List<DaysCompanion> days = <DaysCompanion>[];
    final List<TasksCompanion> tasks = <TasksCompanion>[];
    final List<StepsCompanion> steps = <StepsCompanion>[];
    final List<BreaksCompanion> breaks = <BreaksCompanion>[];
    final Map<String, ChaptersCompanion> chapters =
        <String, ChaptersCompanion>{};
    final Map<String, int> chapterSort = <String, int>{};

    for (final PlanDay day in dataset.days) {
      days.add(
        DaysCompanion.insert(
          id: day.id,
          dayNumber: day.dayNumber,
          week: day.week,
          type: day.type,
          statedStudyMinutes: Value<int>(day.statedStudyMinutes),
          startClock: Value<String?>(day.startClock),
          endClock: Value<String?>(day.endClock),
          headerTitle: Value<String?>(day.displayTitle),
          note: Value<String?>(day.note),
        ),
      );

      int taskOrder = 0;
      for (final PlanItem item in day.items) {
        taskOrder += 1;

        final String chapterKey = '${item.subjectKey}|${item.group}';
        final String chapterId =
            'chapter-${item.subjectKey}-'
            '${PlanImporter.versionOf(item.group).toRadixString(16)}';
        chapters.putIfAbsent(
          chapterKey,
          () => ChaptersCompanion.insert(
            id: chapterId,
            subjectId: item.subjectKey,
            title: item.group,
            sortOrder: chapterSort.update(
              item.subjectKey,
              (int v) => v + 1,
              ifAbsent: () => 0,
            ),
          ),
        );

        tasks.add(
          TasksCompanion.insert(
            id: item.id,
            dayId: day.id,
            subjectId: item.subjectKey,
            chapterId: Value<String?>(chapterId),
            title: item.title,
            type: item.taskType.wireValue,
            groupTitle: Value<String?>(item.group),
            sortOrder: taskOrder,
            suggestedStart: Value<String?>(item.startClock),
            suggestedEnd: Value<String?>(item.endClock),
            attendanceMinutes: Value<int>(item.attendanceMinutes),
            // Course-question hours are stored in their own bucket so the
            // analytics engine keeps attendance/study/solving separate.
            studyMinutes: Value<int>(item.studyMinutes),
            questionMinutes: Value<int>(item.questionMinutes),
          ),
        );

        // Step ids, kinds and order come from the model, so the template rows
        // and the task list can never disagree (PRD 5.4).
        for (final PlanStep step in item.steps) {
          steps.add(
            StepsCompanion.insert(
              id: step.id,
              taskId: item.id,
              kind: step.kind,
              minutes: step.minutes,
              suggestedStart: Value<String?>(step.suggestedStart),
              suggestedEnd: Value<String?>(step.suggestedEnd),
              sortOrder: step.order,
            ),
          );
        }
      }

      for (int i = 0; i < day.interludes.length; i++) {
        final PlanInterlude interlude = day.interludes[i];
        breaks.add(
          BreaksCompanion.insert(
            id: '${day.id}-int-${i + 1}',
            dayId: day.id,
            afterPeriod: interlude.afterPeriod,
            kind: interlude.type,
            startClock: interlude.start,
            endClock: interlude.end,
            minutes: interlude.minutes,
            label: Value<String?>(interlude.label),
          ),
        );
      }
    }

    return _TemplateRows(
      plan: plan,
      subjects: subjects,
      chapters: chapters.values.toList(growable: false),
      days: days,
      tasks: tasks,
      steps: steps,
      breaks: breaks,
    );
  }

  static String _subjectAccent(String datasetKey) {
    // Exact accents from the prototype's subject palette
    // (`C={ch:['الكيمياء الطبية','#6AA6FF'], ...}` in the HTML source).
    switch (datasetKey) {
      case 'chem':
        return '#6AA6FF';
      case 'phys':
        return '#5DD6C0';
      case 'eng':
        return '#F0A8C8';
      case 'hist':
        return '#E8B65A';
      case 'bio':
        return '#F0766B';
      default:
        throw PlanDatasetException('no accent colour for subject $datasetKey');
    }
  }
}

class _TemplateRows {
  const _TemplateRows({
    required this.plan,
    required this.subjects,
    required this.chapters,
    required this.days,
    required this.tasks,
    required this.steps,
    required this.breaks,
  });

  final PlansCompanion plan;
  final List<SubjectsCompanion> subjects;
  final List<ChaptersCompanion> chapters;
  final List<DaysCompanion> days;
  final List<TasksCompanion> tasks;
  final List<StepsCompanion> steps;
  final List<BreaksCompanion> breaks;
}
