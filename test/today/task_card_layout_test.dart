import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/app/theme/khutati_theme.dart';
import 'package:khutati/core/design/widgets/widgets.dart';
import 'package:khutati/core/utils/format.dart';
import 'package:khutati/domain/plan/plan_progress.dart';
import 'package:khutati/domain/plan/plan_task.dart';
import 'package:khutati/domain/plan/step_progress.dart';
import 'package:khutati/features/today/presentation/today_screen.dart';
import 'package:khutati/l10n/l10n.dart';

/// The Today schedule and the Past Tasks screen both render `TaskCard` inside a
/// vertically scrolling list, where the vertical constraint is unbounded.
///
/// The two-tap progress feature once made the step chips a
/// `CrossAxisAlignment.stretch` row without a bounded height, which forces an
/// infinite height on every chip. The card then collapsed and the schedule
/// showed a large blank area while the header and hero card still rendered.
/// These tests keep that failure mode visible.
void main() {
  PlanTask taskWithSteps({StepProgress first = StepProgress.notStarted}) {
    return PlanTask(
      id: 'd001-chem-01',
      dayNumber: 1,
      subjectKey: 'chem',
      subjectName: 'الكيمياء',
      title: 'الأساسيات',
      type: PlanTaskType.foundation,
      suggestedStart: '08:00',
      suggestedEnd: '08:50',
      steps: <PlanStep>[
        PlanStep(
          id: 'd001-chem-01-01',
          kind: ProgressStepKinds.attend,
          minutes: 23,
          order: 1,
          suggestedStart: '08:00',
          suggestedEnd: '08:23',
          progress: first,
        ),
        const PlanStep(
          id: 'd001-chem-01-02',
          kind: ProgressStepKinds.study,
          minutes: 27,
          order: 2,
          suggestedStart: '08:23',
          suggestedEnd: '08:50',
        ),
      ],
    );
  }

  Widget host(PlanTask task) {
    return ProviderScope(
      child: MaterialApp(
        theme: KhutatiTheme.dark,
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) {
            final KhutatiFormat format = KhutatiFormat(
              AppLocalizations.of(context),
            );
            return Scaffold(
              body: ListView(
                children: <Widget>[
                  TaskCard(
                    task: task,
                    number: 1,
                    accent: const Color(0xFF6AA6FF),
                    format: format,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  testWidgets('a multi-step task card lays out inside a scroll list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(taskWithSteps()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TaskCard), findsOneWidget);
    expect(find.byType(KChip), findsNWidgets(2));

    final Size size = tester.getSize(find.byType(TaskCard));
    expect(size.height.isFinite, isTrue);
    expect(size.height, greaterThan(0));
  });

  testWidgets('a partially done step still lays out with equal-height chips', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(taskWithSteps(first: StepProgress.partial)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final List<KChip> chips = tester
        .widgetList<KChip>(find.byType(KChip))
        .toList(growable: false);
    expect(chips, hasLength(2));

    final Size first = tester.getSize(find.byType(KChip).at(0));
    final Size second = tester.getSize(find.byType(KChip).at(1));
    expect(first.height, second.height);
    expect(first.height, greaterThan(0));
  });
}
