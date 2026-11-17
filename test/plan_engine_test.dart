import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/data/database/app_database.dart';
import 'package:khutati/data/import/plan_importer.dart';
import 'package:khutati/data/repositories/template_repository.dart';
import 'package:khutati/domain/plan/plan_calendar.dart';
import 'package:khutati/domain/plan/plan_progress.dart';
import 'package:khutati/features/updates/domain/app_release.dart';

/// One compact suite for the plan engine and update versioning. The full matrix
/// runs in CI; keep additions here short so `flutter test` stays fast.
void main() {
  test('the bundled dataset imports once and reconciles', () async {
    final AppDatabase db = AppDatabase.memory();
    addTearDown(db.close);
    final PlanImporter importer = PlanImporter(db);
    final String json = File('khutati_plan_data.json').readAsStringSync();

    final PlanImportResult first = await importer.ensureImported(json);
    expect(first.imported, isTrue);
    expect((await db.select(db.days).get()), hasLength(68));
    expect((await db.select(db.tasks).get()), hasLength(725));
    expect((await db.select(db.steps).get()), hasLength(1390));

    final DayBundle day = (await TemplateRepository(db).dayBundle(1))!;
    expect(day.plannedMinutes, 550);
    expect((await TemplateRepository(db).dayBundle(15))!.tasks, isEmpty);

    expect((await importer.ensureImported(json)).imported, isFalse);
    expect(
      (await TemplateRepository(db).plannedTotals()).attendance,
      12735,
    );
  });

  test('calendar maps day numbers, weeks and statuses', () {
    final PlanCalendar calendar =
        PlanCalendar(startDate: DateTime(2026, 11, 19), totalDays: 68);
    final DateTime day12 = DateTime(2026, 11, 30);

    expect(calendar.dateOfDay(68), DateTime(2027, 1, 25));
    expect(calendar.dayNumberFor(day12), 12);
    expect(calendar.weekCount, 10);
    expect(calendar.daysInWeek(10), hasLength(5));
    expect(calendar.daysAfterToday(day12), 56);
    expect(
      calendar.statusOf(dayNumber: 3, isCompleted: false, isRest: false, now: day12),
      PlanDayStatus.overdue,
    );
    expect(
      calendar.statusOf(dayNumber: 15, isCompleted: false, isRest: true, now: day12),
      PlanDayStatus.rest,
    );
  });

  test('progress separates buckets and honours manual completion', () {
    final PlanProgress progress = PlanProgress.of(<ProgressTaskInput>[
      ProgressTaskInput(
        id: 'video',
        completed: true,
        steps: const <ProgressStepInput>[
          ProgressStepInput(
            id: 'a',
            kind: ProgressStepKinds.attend,
            minutes: 40,
            completed: false,
          ),
          ProgressStepInput(
            id: 's',
            kind: ProgressStepKinds.study,
            minutes: 20,
            completed: false,
          ),
        ],
      ),
      const ProgressTaskInput(
        id: 'questions',
        steps: <ProgressStepInput>[
          ProgressStepInput(
            id: 'q',
            kind: ProgressStepKinds.questions,
            minutes: 30,
            completed: false,
          ),
        ],
      ),
    ]);

    expect(progress.plannedMinutes, 90);
    expect(progress.completedMinutes, 60);
    expect(progress.completedMinutesFor(ProgressStepKinds.questions), 0);
    expect(progress.fraction, closeTo(2 / 3, 1e-9));
  });

  test('update manifests compare semantic versions and build numbers', () {
    expect(AppVersion.tryParse('v1.4.2')!.compareTo(const AppVersion(major: 1, minor: 4, patch: 1)), greaterThan(0));
    expect(AppVersion.tryParse('nope'), isNull);

    const UpdateManifest manifest = UpdateManifest(
      versionName: '0.3.0',
      versionCode: 3,
      apkUrl: 'https://github.com/7sn-17/Khutati/releases/download/latest/Khutati.apk',
    );

    expect(manifest.isNewerThan(const AppVersion(major: 0, minor: 2, patch: 0, build: 2)), isTrue);
    expect(manifest.isNewerThan(const AppVersion(major: 0, minor: 3, patch: 0, build: 3)), isFalse);
  });
}
