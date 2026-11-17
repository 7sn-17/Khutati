import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/data/database/app_database.dart';
import 'package:khutati/data/repositories/template_repository.dart';
import 'package:khutati/data/repositories/user_state_repository.dart';
import 'package:khutati/domain/plan/step_progress.dart';

void main() {
  late AppDatabase db;
  late TemplateRepository template;
  late UserStateRepository userState;

  setUp(() {
    db = AppDatabase.memory();
    template = TemplateRepository(db);
    userState = UserStateRepository(db);
  });

  tearDown(() => db.close());

  Future<void> seedDay() async {
    await db
        .into(db.plans)
        .insert(
          PlansCompanion.insert(
            id: 'plan-1',
            name: 'خطة إنهاء المنهاج',
            datasetVersion: 1,
            startDate: DateTime(2026, 11, 19),
            totalDays: 68,
            studyDays: 64,
            totalPlannedMinutes: 28809,
          ),
        );
    await db
        .into(db.subjects)
        .insert(
          SubjectsCompanion.insert(
            id: 'subj-chem',
            key: 'chem',
            nameAr: 'الكيمياء الطبية',
            instructor: 'د. توفيق القطان',
            accentHex: '#6AA6FF',
            sortOrder: 1,
          ),
        );
    await db
        .into(db.days)
        .insert(
          DaysCompanion.insert(
            id: 'd001',
            dayNumber: 1,
            week: 1,
            type: 'normal',
            startClock: const Value<String>('08:00'),
            endClock: const Value<String>('21:26'),
            statedStudyMinutes: const Value<int>(550),
          ),
        );
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'd001-chem-01',
            dayId: 'd001',
            subjectId: 'subj-chem',
            title: 'فيديو تأسيسي الذرة 1',
            type: 'foundation',
            sortOrder: 1,
            attendanceMinutes: const Value<int>(23),
            studyMinutes: const Value<int>(12),
          ),
        );
    await db
        .into(db.steps)
        .insert(
          StepsCompanion.insert(
            id: 'd001-chem-01-01',
            taskId: 'd001-chem-01',
            kind: 'attend',
            minutes: 23,
            sortOrder: 1,
          ),
        );
    await db
        .into(db.steps)
        .insert(
          StepsCompanion.insert(
            id: 'd001-chem-01-02',
            taskId: 'd001-chem-01',
            kind: 'study',
            minutes: 12,
            sortOrder: 2,
          ),
        );
    await db
        .into(db.breaks)
        .insert(
          BreaksCompanion.insert(
            id: 'd001-b1',
            dayId: 'd001',
            afterPeriod: 1,
            kind: 'break',
            startClock: '09:14',
            endClock: '09:30',
            minutes: 16,
          ),
        );
  }

  test('creates the full schema from empty', () async {
    expect(await db.select(db.days).get(), isEmpty);
    await seedDay();
    expect(await db.select(db.days).get(), hasLength(1));
  });

  test('loads a day with its tasks and ordered steps', () async {
    await seedDay();

    final DayBundle? bundle = await template.dayBundle(1);

    expect(bundle, isNotNull);
    expect(bundle!.day.dayNumber, 1);
    expect(bundle.tasks, hasLength(1));
    expect(bundle.tasks.single.steps.map((StepRow s) => s.kind), <String>[
      'attend',
      'study',
    ]);
    expect(bundle.plannedMinutes, 35);
    expect(bundle.breaks.single.minutes, 16);
  });

  test('planned totals add up per bucket', () async {
    await seedDay();
    final ({int attendance, int study, int questions}) totals = await template
        .plannedTotals();
    expect(totals.attendance, 23);
    expect(totals.study, 12);
    expect(totals.questions, 0);
  });

  test('user progress never mutates the template', () async {
    await seedDay();

    await userState.setStepCompleted(
      'd001-chem-01-01',
      StepProgress.completed,
    );
    await userState.setTaskStatus('d001-chem-01', 'completed');

    final DayBundle? bundle = await template.dayBundle(1);
    expect(bundle!.tasks.single.steps.first.minutes, 23);
    expect(bundle.plannedMinutes, 35);

    final Set<String> done = await userState.completedStepIdsForDay('d001');
    expect(done, <String>{'d001-chem-01-01'});
  });

  test('task statuses are read per day from user state', () async {
    await seedDay();
    await userState.setTaskStatus('d001-chem-01', 'completed');

    final Map<String, String> statuses = await userState.taskStatusesForDay(
      'd001',
    );
    expect(statuses, <String, String>{'d001-chem-01': 'completed'});
  });

  test('step state writes are observable without polling', () async {
    await seedDay();

    final List<List<UserStepStateRow>> emissions = <List<UserStepStateRow>>[];
    final StreamSubscription<List<UserStepStateRow>> subscription = db
        .select(db.userStepStates)
        .watch()
        .listen(emissions.add);

    await pumpEventQueue();
    await userState.setStepCompleted(
      'd001-chem-01-01',
      StepProgress.completed,
    );
    await pumpEventQueue();
    await subscription.cancel();

    expect(
      emissions.any(
        (List<UserStepStateRow> rows) =>
            rows.isNotEmpty && rows.single.completed,
      ),
      isTrue,
    );
  });

  test('partial state is stored and read back per step', () async {
    await seedDay();

    await userState.setStepCompleted('d001-chem-01-01', StepProgress.partial);
    expect(
      await userState.stepProgress('d001-chem-01-01'),
      StepProgress.partial,
    );
    expect(
      (await userState.stepProgressForDay('d001'))['d001-chem-01-01'],
      StepProgress.partial,
    );
  });

  test('rows written before the progress column read as complete', () async {
    await seedDay();

    // A v1 row: `completed` only, `progress` left at its default.
    await db
        .into(db.userStepStates)
        .insert(
          UserStepStatesCompanion.insert(
            stepId: 'd001-chem-01-02',
            completed: const Value<bool>(true),
          ),
        );

    expect(
      await userState.stepProgress('d001-chem-01-02'),
      StepProgress.completed,
    );
  });

  test('uncompleting a step clears its completion time', () async {
    await seedDay();
    await userState.setStepCompleted(
      'd001-chem-01-01',
      StepProgress.completed,
    );
    await userState.setStepCompleted(
      'd001-chem-01-01',
      StepProgress.notStarted,
    );

    final UserStepStateRow state = await db
        .select(db.userStepStates)
        .getSingle();
    expect(state.completed, isFalse);
    expect(state.completedAt, isNull);
  });

  test('foreign keys are enforced', () async {
    await expectLater(
      db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'orphan',
              dayId: 'missing-day',
              subjectId: 'missing-subject',
              title: 'x',
              type: 'lecture',
              sortOrder: 1,
            ),
          ),
      throwsA(anything),
    );
  });

  test('notes and review flags are stored per task', () async {
    await seedDay();

    await userState.addNote('d001-chem-01', 'راجع الجدول الدوري');
    await userState.setReviewFlag('d001-chem-01', true);

    expect(await userState.notesFor('d001-chem-01'), hasLength(1));
    expect(await db.select(db.reviewFlags).get(), hasLength(1));

    await userState.setReviewFlag('d001-chem-01', false);
    expect(await db.select(db.reviewFlags).get(), isEmpty);
  });
}
