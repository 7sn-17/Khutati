import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/domain/plan/plan_actuals.dart';
import 'package:khutati/domain/plan/plan_dataset.dart';
import 'package:khutati/domain/plan/plan_progress.dart';
import 'package:khutati/domain/plan/plan_task.dart';

/// Task/step model rules (PRD 5.4) and focus-session actual time (PRD 5.6).
void main() {
  final PlanDataset dataset = PlanDataset.parse(
    File('khutati_plan_data.json').readAsStringSync(),
  );

  PlanTask taskFor(PlanItem item, int dayNumber) => PlanTask(
    id: item.id,
    dayNumber: dayNumber,
    subjectKey: item.subjectKey,
    subjectName: item.subjectName,
    title: item.title,
    groupTitle: item.group,
    type: item.taskType,
    suggestedStart: item.startClock,
    suggestedEnd: item.endClock,
    steps: item.steps,
  );

  test('every task keeps exact minutes and matches its day total', () {
    int taskCount = 0;
    int stepCount = 0;

    for (final PlanDay day in dataset.days) {
      final List<PlanTask> tasks = <PlanTask>[
        for (final PlanItem item in day.items) taskFor(item, day.dayNumber),
      ];
      taskCount += tasks.length;

      expect(
        tasks.fold<int>(
          0,
          (int sum, PlanTask task) => sum + task.plannedMinutes,
        ),
        day.totalMinutes,
        reason: 'day ${day.dayNumber} planned minutes',
      );

      for (final PlanTask task in tasks) {
        stepCount += task.steps.length;
        expect(
          task.plannedMinutes,
          task.minutesFor(ProgressStepKinds.attend) +
              task.minutesFor(ProgressStepKinds.study) +
              task.minutesFor(ProgressStepKinds.questions),
          reason: 'task ${task.id} buckets add up',
        );
        expect(
          task.stepsInOrder.map((PlanStep step) => step.order).toList(),
          <int>[for (int i = 1; i <= task.steps.length; i++) i],
          reason: 'task ${task.id} steps are ordered',
        );
      }
    }

    expect(taskCount, 725);
    expect(stepCount, 1390);
  });

  test('foundation videos never carry a course step', () {
    int foundation = 0;
    int lecture = 0;
    int course = 0;

    for (final PlanDay day in dataset.days) {
      for (final PlanItem item in day.items) {
        final PlanTask task = taskFor(item, day.dayNumber);

        if (task.type == PlanTaskType.courseQuestions) {
          course += 1;
          expect(task.steps, hasLength(1), reason: task.id);
          expect(task.steps.single.kind, ProgressStepKinds.questions);
          expect(task.minutesFor(ProgressStepKinds.attend), 0);
          expect(task.steps.single.minutes, task.plannedMinutes);
        } else {
          if (task.type == PlanTaskType.foundation) {
            foundation += 1;
          } else {
            lecture += 1;
          }
          expect(
            task.steps.map((PlanStep step) => step.kind).toList(),
            <String>[ProgressStepKinds.attend, ProgressStepKinds.study],
            reason: task.id,
          );
          expect(
            task.minutesFor(ProgressStepKinds.questions),
            0,
            reason: '${task.id} is a video, not a question task',
          );
        }
      }
    }

    expect(foundation, 29);
    expect(lecture, 636);
    expect(course, 60);
  });

  test('partial completion rolls up per step', () {
    const PlanTask task = PlanTask(
      id: 'video-1',
      dayNumber: 1,
      subjectKey: 'chem',
      subjectName: 'الكيمياء الطبية',
      title: 'فيديو تأسيسي الذرة 1',
      type: PlanTaskType.foundation,
      steps: <PlanStep>[
        PlanStep(
          id: 'video-1-attend',
          kind: ProgressStepKinds.attend,
          minutes: 40,
          order: 1,
        ),
        PlanStep(
          id: 'video-1-study',
          kind: ProgressStepKinds.study,
          minutes: 20,
          order: 2,
        ),
      ],
    );

    expect(task.isComplete, isFalse);
    expect(task.status, PlanTaskStatus.notStarted);
    expect(task.completedMinutes, 0);
    expect(task.fraction, 0);
    expect(task.nextStep?.id, 'video-1-attend');
    expect(task.hasStarted, isFalse);

    final PlanTask afterAttendance = task.withStepCompletion(
      'video-1-attend',
      true,
    );
    expect(afterAttendance.completedMinutes, 40);
    expect(afterAttendance.fraction, closeTo(2 / 3, 1e-9));
    expect(afterAttendance.isComplete, isFalse);
    expect(afterAttendance.hasStarted, isTrue);
    expect(afterAttendance.nextStep?.id, 'video-1-study');

    // The original snapshot is untouched.
    expect(task.completedMinutes, 0);

    final PlanTask doneStepByStep = afterAttendance.withStepCompletion(
      'video-1-study',
      true,
    );
    expect(doneStepByStep.isComplete, isTrue);
    expect(doneStepByStep.completedMinutes, 60);
    expect(doneStepByStep.nextStep, isNull);

    // Unchecking one step reopens a task that was completed step by step.
    expect(
      doneStepByStep.withStepCompletion('video-1-attend', false).isComplete,
      isFalse,
    );

    // An unknown step id is a no-op, never a crash.
    expect(task.withStepCompletion('missing', true), same(task));
  });

  test('explicit completion counts every step without rewriting rows', () {
    const PlanTask task = PlanTask(
      id: 'questions-1',
      dayNumber: 2,
      subjectKey: 'chem',
      title: 'حل أسئلة الفصل',
      type: PlanTaskType.courseQuestions,
      steps: <PlanStep>[
        PlanStep(
          id: 'questions-1-questions',
          kind: ProgressStepKinds.questions,
          minutes: 30,
          order: 1,
        ),
      ],
    );

    final PlanTask markedDone = task.withStatus(PlanTaskStatus.completed);
    expect(markedDone.isComplete, isTrue);
    expect(markedDone.completedMinutes, 30);
    expect(markedDone.remainingMinutes, 0);
    expect(markedDone.fraction, 1);
    expect(markedDone.steps.single.completed, isFalse);
    expect(markedDone.toProgressTask().completed, isTrue);

    // Status transitions clear a stale postpone target.
    final PlanTask postponed = task.withStatus(
      PlanTaskStatus.postponed,
      postponedToDay: 20,
    );
    expect(postponed.status.wireValue, 'postponed');
    expect(postponed.postponedToDay, 20);
    expect(postponed.isComplete, isFalse);
    expect(
      postponed.withStatus(PlanTaskStatus.completed).postponedToDay,
      isNull,
    );
  });

  test('expansion state is immutable', () {
    const PlanTask task = PlanTask(
      id: 't',
      dayNumber: 3,
      subjectKey: 'bio',
      title: 'نموذج',
      type: PlanTaskType.lecture,
      steps: <PlanStep>[
        PlanStep(
          id: 't-attend',
          kind: ProgressStepKinds.attend,
          minutes: 10,
          order: 1,
        ),
      ],
    );

    expect(task.expanded, isFalse);
    expect(task.toggleExpanded().expanded, isTrue);
    expect(task.toggleExpanded().toggleExpanded().expanded, isFalse);
    expect(task.expanded, isFalse);
  });

  test('task progress feeds the hours engine exactly once', () {
    const PlanTask task = PlanTask(
      id: 'video-2',
      dayNumber: 4,
      subjectKey: 'eng',
      title: 'محاضرة',
      type: PlanTaskType.lecture,
      steps: <PlanStep>[
        PlanStep(
          id: 'video-2-attend',
          kind: ProgressStepKinds.attend,
          minutes: 45,
          order: 1,
          completed: true,
        ),
        PlanStep(
          id: 'video-2-study',
          kind: ProgressStepKinds.study,
          minutes: 15,
          order: 2,
        ),
      ],
    );

    final PlanProgress progress = PlanProgress.of(<ProgressTaskInput>[
      task.toProgressTask(),
    ]);

    expect(progress.plannedMinutes, 60);
    expect(progress.completedMinutes, 45);
    expect(progress.plannedMinutesFor(ProgressStepKinds.attend), 45);
    expect(progress.completedMinutesFor(ProgressStepKinds.study), 0);
    expect(progress.remainingMinutes, 15);
    expect(
      progress.plannedMinutes,
      task.plannedMinutes,
      reason: 'model and engine cannot disagree',
    );
  });

  test('actual time comes only from focus sessions', () {
    final ActualTime time = ActualTime.of(const <FocusSessionInput>[
      FocusSessionInput(
        actualSeconds: 600,
        taskId: 'video-1',
        stepId: 'video-1-study',
      ),
      FocusSessionInput(actualSeconds: 120, taskId: 'video-1'),
      FocusSessionInput(actualSeconds: 300, phase: FocusPhases.breakTime),
    ]);

    expect(time.focusSeconds, 720);
    expect(time.breakSeconds, 300);
    expect(time.focusMinutes, 12);
    expect(time.breakMinutes, 5);
    expect(time.focusHours, closeTo(0.2, 1e-9));
    expect(time.focusSecondsForTask('video-1'), 720);
    expect(time.focusMinutesForTask('video-1'), 12);
    expect(time.focusSecondsForTask('missing'), 0);
    expect(time.hasFocusTime, isTrue);
    expect(ActualTime.none.hasFocusTime, isFalse);

    final ActualTime combined = ActualTime.combine(<ActualTime>[
      time,
      ActualTime.of(const <FocusSessionInput>[
        FocusSessionInput(actualSeconds: 60, taskId: 'video-1'),
      ]),
    ]);
    expect(combined.focusSeconds, 780);
    expect(combined.focusMinutesForTask('video-1'), 13);
  });
}
