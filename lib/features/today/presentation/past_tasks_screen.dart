import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/utils/format.dart';
import '../../../domain/plan/plan_calendar.dart';
import '../../../domain/plan/plan_task.dart';
import '../../../features/plan/application/plan_browser_controller.dart';
import '../../../features/today/application/today_controller.dart';
import '../../../features/today/presentation/today_screen.dart';
import '../../../l10n/l10n.dart';

/// A focused view for overdue and past plan tasks.
///
/// It reuses the Today task card so reviewing and completing past work feels
/// identical to the current day, while the Plan tab keeps its compact map.
class PastTasksScreen extends ConsumerWidget {
  const PastTasksScreen({this.dayNumber, super.key});

  final int? dayNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PlanBrowserData?> plan = ref.watch(planBrowserProvider);

    return plan.when(
      data: (PlanBrowserData? data) => data == null
          ? const _PastTasksError()
          : _PastTasksBody(data: data, dayNumber: dayNumber),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) => const _PastTasksError(),
    );
  }
}

class _PastTasksBody extends ConsumerWidget {
  const _PastTasksBody({required this.data, this.dayNumber});

  final PlanBrowserData data;
  final int? dayNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final KhutatiFormat format = KhutatiFormat(l10n);
    final DateTime today = DateTime(
      data.now.year,
      data.now.month,
      data.now.day,
    );

    final List<PlanDayData> pastDays = data.days
        .where((PlanDayData day) {
          if (day.isRest) return false;
          if (dayNumber != null && day.day.dayNumber != dayNumber) {
            return false;
          }
          final DateTime date = DateTime(
            day.date.year,
            day.date.month,
            day.date.day,
          );
          return date.isBefore(today) ||
              day.status == PlanDayStatus.overdue;
        })
        .toList(growable: false);

    int number = 0;
    final List<Widget> children = <Widget>[];
    bool hasTasks = false;

    for (final PlanDayData day in pastDays) {
      final List<PlanTask> openTasks = day.tasks
          .where((PlanTask task) => !task.isComplete)
          .toList(growable: false);
      if (openTasks.isEmpty) continue;
      hasTasks = true;

      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Row(
            children: <Widget>[
              Text(
                l10n.planSearchDay(day.day.dayNumber, KhutatiFormat.planDate(day.date)),
                style: TextStyle(
                  fontFamily: KTypography.displayFamily,
                  fontSize: KTypography.h2Size,
                  fontWeight: FontWeight.w700,
                  color: palette.tx,
                ),
              ),
              const Spacer(),
              Text(
                l10n.planTaskCount(openTasks.length),
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.smallSize,
                  color: palette.mute,
                ),
              ),
            ],
          ),
        ),
      );

      for (final PlanTask task in openTasks) {
        number += 1;
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: KMetrics.cardGap),
            child: TaskCard(
              key: ValueKey<String>(task.id),
              task: task,
              number: number,
              accent: day.subjectAccents[task.subjectKey] ?? palette.gold,
              format: format,
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pastTasksTitle),
      ),
      body: children.isEmpty || !hasTasks
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.pastTasksEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.muteSize,
                    color: palette.mute,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                KMetrics.appPaddingX,
                KMetrics.appPaddingTop,
                KMetrics.appPaddingX,
                KMetrics.appPaddingBottom,
              ),
              children: children,
            ),
    );
  }
}

class _PastTasksError extends StatelessWidget {
  const _PastTasksError();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.pastTasksTitle)),
      body: Center(
        child: Text(
          context.l10n.todayLoadError,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            color: context.palette.mute,
          ),
        ),
      ),
    );
  }
}
