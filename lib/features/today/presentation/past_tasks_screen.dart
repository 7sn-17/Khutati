import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/sound/sound_effects.dart';
import '../../../core/utils/format.dart';
import '../../../domain/plan/plan_calendar.dart';
import '../../../domain/plan/plan_task.dart';
import '../../../features/plan/application/plan_browser_controller.dart';
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
      error: (Object error, StackTrace stack) => _PastTasksError(error: error),
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
          return date.isBefore(today) || day.status == PlanDayStatus.overdue;
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

      final int firstNumber = number + 1;
      number += openTasks.length;

      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: KMetrics.cardGap),
          child: _DayAccordion(
            key: ValueKey<int>(day.day.dayNumber),
            title: l10n.planSearchDay(
              day.day.dayNumber,
              KhutatiFormat.planDate(day.date),
            ),
            tasks: openTasks,
            firstNumber: firstNumber,
            accents: day.subjectAccents,
            format: format,
            // The list always opens fully collapsed. The only exception is the
            // single-day drill-down (`/past-tasks?day=N`), where the user has
            // already asked for that one day and a closed card would just be
            // an extra tap.
            initiallyExpanded: dayNumber != null,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.pastTasksTitle)),
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

/// One collapsible day: a compact header that expands into its task cards.
///
/// Everything starts closed so the screen is a short, scannable list of days
/// rather than a long scroll of tasks. Expansion is a plain [AnimatedSize] over
/// `Curves.easeInOut` — the child is only built while open, so a collapsed day
/// costs one header row and nothing else.
class _DayAccordion extends StatefulWidget {
  const _DayAccordion({
    required this.title,
    required this.tasks,
    required this.firstNumber,
    required this.accents,
    required this.format,
    this.initiallyExpanded = false,
    super.key,
  });

  final String title;
  final List<PlanTask> tasks;

  /// Number of the first task in the screen-wide sequence, so the numbers stay
  /// continuous across days whether a day is open or closed.
  final int firstNumber;
  final Map<String, Color> accents;
  final KhutatiFormat format;
  final bool initiallyExpanded;

  @override
  State<_DayAccordion> createState() => _DayAccordionState();
}

class _DayAccordionState extends State<_DayAccordion> {
  static const Duration _duration = Duration(milliseconds: 320);

  late bool _open = widget.initiallyExpanded;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final BorderRadius radius = BorderRadius.circular(KMetrics.cardRadius);
    final String countLabel = context.l10n.pastTasksOverdueCount(
      widget.tasks.length,
    );

    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: radius,
        border: Border.all(color: palette.line),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            KInkSurface(
              onTap: _toggle,
              borderRadius: radius,
              sound: KSound.toggle,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Semantics(
                button: true,
                expanded: _open,
                label: widget.title,
                value: countLabel,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KTypography.displayFamily,
                          fontSize: KTypography.h2Size,
                          fontWeight: FontWeight.w700,
                          color: palette.tx,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: palette.red.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(
                          KMetrics.pillRadius,
                        ),
                      ),
                      child: Text(
                        countLabel,
                        style: TextStyle(
                          fontFamily: KTypography.bodyFamily,
                          fontSize: KTypography.tagSize,
                          fontWeight: FontWeight.w500,
                          color: palette.redtx,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: _duration,
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 22,
                        color: palette.mute,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: _duration,
              curve: Curves.easeInOut,
              alignment: AlignmentDirectional.topStart,
              child: _open
                  ? _buildTasks(palette)
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasks(KhutatiPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(height: 1, color: palette.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < widget.tasks.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: KMetrics.cardGap),
                  child: TaskCard(
                    key: ValueKey<String>(widget.tasks[i].id),
                    task: widget.tasks[i],
                    number: widget.firstNumber + i,
                    accent:
                        widget.accents[widget.tasks[i].subjectKey] ??
                        palette.gold,
                    format: widget.format,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PastTasksError extends StatelessWidget {
  const _PastTasksError({this.error});

  /// Debug-only detail, so a failing provider never looks like a blank page.
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.pastTasksTitle)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              context.l10n.todayLoadError,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                color: context.palette.mute,
              ),
            ),
            if (kDebugMode && error != null) ...<Widget>[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.smallSize,
                    color: context.palette.redtx,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
