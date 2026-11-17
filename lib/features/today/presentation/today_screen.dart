import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/utils/format.dart';
import '../../../data/database/app_database.dart' show BreakRow;
import '../../../domain/plan/plan_task.dart';
import '../../../domain/plan/step_progress.dart';
import '../../../l10n/l10n.dart';
import '../application/today_controller.dart';

/// Today (PRD 5.2) — prototype v0.
///
/// Header, ECG progress, summary cells, quote, next-task hero, overdue alert
/// and the expandable task timeline. Every number comes from the imported plan
/// and user state; there is no sample plan data in this file.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TodayData?> today = ref.watch(todayDataProvider);

    return today.when(
      data: (TodayData? data) =>
          data == null ? const _LoadError() : _TodayBody(data: data),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) => const _LoadError(),
    );
  }
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody({required this.data});

  final TodayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final KhutatiFormat format = KhutatiFormat(l10n);

    final int hour = data.now.hour;
    final String greeting = hour < 12
        ? l10n.todayGreetingMorning
        : hour < 18
        ? l10n.todayGreetingEvening
        : l10n.todayGreetingNight;

    final String dayType = data.isRest
        ? l10n.todayRestDay
        : data.day.type == 'practical'
        ? l10n.todayPracticalDay
        : l10n.todayStudyDay;
    final String dateLine =
        '${KhutatiFormat.planDate(data.date)}، $dayType، '
        '${l10n.todayRemainingDays(data.daysRemaining)}';

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(todayDataProvider);
        await ref.read(todayDataProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          KMetrics.appPaddingX,
          KMetrics.appPaddingTop,
          KMetrics.appPaddingX,
          KMetrics.appPaddingBottom,
        ),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  greeting,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.muteSize,
                    color: palette.mute,
                  ),
                ),
              ),
              KPill(label: l10n.galleryPillStreak, value: '${data.streak}'),
              const SizedBox(width: 8),
              KPill(label: l10n.galleryPillPoints, value: '${data.points}'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.todayDayNumber(data.dayNumber),
            style: TextStyle(
              fontFamily: KTypography.displayFamily,
              fontSize: KTypography.h1Size,
              fontWeight: FontWeight.w700,
              height: KTypography.h1Height,
              color: palette.tx,
            ),
          ),
          Text(
            dateLine,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.muteSize,
              color: palette.mute,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: KEcgLine(progress: data.progress.fraction),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _SummaryCell(
                  label: l10n.todayDone,
                  value: format.duration(data.progress.completedMinutes),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCell(
                  label: l10n.todayRemaining,
                  value: format.duration(data.progress.remainingMinutes),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCell(
                  label: l10n.todayEnds,
                  value: _endsLabel(data, format),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Quote(text: _quoteOfDay(l10n, data.now)),
          _Hero(data: data, format: format),
          if (data.overdueTasks > 0)
            _OverdueAlert(
              tasks: data.overdueTasks,
              minutes: data.overdueMinutes,
              format: format,
            ),
          if (data.tasks.isNotEmpty) ...<Widget>[
            KSectionHeader(title: l10n.todaySchedule),
            ..._timeline(context, l10n, format),
          ],
          if (kDebugMode) ...<Widget>[
            const SizedBox(height: 24),
            KButton(
              label: l10n.galleryOpen,
              variant: KButtonVariant.secondary,
              expand: true,
              onPressed: () => context.push('/gallery'),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _timeline(
    BuildContext context,
    AppLocalizations l10n,
    KhutatiFormat format,
  ) {
    final List<Widget> children = <Widget>[];
    final Set<String> placedBreaks = <String>{};
    int number = 0;

    for (final PlanTask task in data.tasks) {
      number += 1;
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: KMetrics.cardGap),
          child: TaskCard(
            key: ValueKey<String>(task.id),
            task: task,
            number: number,
            accent:
                data.subjectAccents[task.subjectKey] ?? context.palette.gold,
            format: format,
          ),
        ),
      );

      for (final BreakRow rest in data.breaks) {
        if (rest.startClock != task.suggestedEnd) continue;
        if (!placedBreaks.add(rest.id)) continue;
        children.add(
          KBreakDivider(
            label: l10n.todayBreakLabel(
              format.duration(rest.minutes),
              format.range(rest.startClock, rest.endClock),
            ),
          ),
        );
      }
    }

    return children;
  }

  String _endsLabel(TodayData data, KhutatiFormat format) {
    final String? end = data.day.endClock;
    if (end == null) return '—';
    final String clock = KhutatiFormat.twelveHour(end);
    final String part = format.dayPart(KhutatiFormat.minutesOfDay(end) ~/ 60);
    return '$clock $part';
  }

  String _quoteOfDay(AppLocalizations l10n, DateTime now) {
    // The prototype rotates six quotes by weekday; % 6 keeps the same order.
    final List<String> quotes = <String>[
      l10n.todayQuote1,
      l10n.todayQuote2,
      l10n.todayQuote3,
      l10n.todayQuote4,
      l10n.todayQuote5,
      l10n.todayQuote6,
    ];
    return quotes[now.weekday % quotes.length];
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KMetrics.statPaddingX,
        vertical: KMetrics.statPaddingY,
      ),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(KMetrics.statRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.smallSize,
              color: palette.mute,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.quoteSize,
              fontWeight: FontWeight.w500,
              color: palette.tx,
            ),
          ),
        ],
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KMetrics.quotePaddingX,
        vertical: KMetrics.quotePaddingY,
      ),
      decoration: BoxDecoration(
        color: palette.card2,
        borderRadius: BorderRadius.circular(KMetrics.quoteRadius),
        border: BorderDirectional(
          start: BorderSide(color: palette.gold, width: 3),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: KTypography.bodyFamily,
          fontSize: KTypography.quoteSize,
          color: palette.tx,
        ),
      ),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.data, required this.format});

  final TodayData data;
  final KhutatiFormat format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final PlanTask? next = data.nextTask;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: KCard(
        radius: KMetrics.heroRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (next == null) ...<Widget>[
              Text(
                data.isRest ? l10n.todayRestDay : l10n.todayAllDoneTitle,
                style: TextStyle(
                  fontFamily: KTypography.displayFamily,
                  fontSize: KTypography.heroTitleSize,
                  fontWeight: FontWeight.w700,
                  height: KTypography.heroTitleHeight,
                  color: palette.tx,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                data.isRest ? l10n.todayRestBody : l10n.todayAllDoneBody,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.muteSize,
                  color: palette.mute,
                ),
              ),
            ] else ...<Widget>[
              Text(
                l10n.todayNextTask,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.smallSize,
                  color: palette.mute,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${next.subjectName ?? data.subjectNames[next.subjectKey] ?? next.subjectKey} — ${next.title}',
                style: TextStyle(
                  fontFamily: KTypography.displayFamily,
                  fontSize: KTypography.heroTitleSize,
                  fontWeight: FontWeight.w700,
                  height: KTypography.heroTitleHeight,
                  color: palette.tx,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _nextDetail(next, l10n),
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.muteSize,
                  color: palette.mute,
                ),
              ),
              const SizedBox(height: 8),
              KTag(
                label:
                    next.subjectName ??
                    data.subjectNames[next.subjectKey] ??
                    next.subjectKey,
                color: data.subjectAccents[next.subjectKey] ?? palette.gold,
              ),
              const SizedBox(height: 12),
              KButton(
                label: l10n.todayStartFocus,
                expand: true,
                onPressed: () => context.go('/focus'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _nextDetail(PlanTask task, AppLocalizations l10n) {
    final PlanStep? step = task.nextStep;
    if (step == null) return '';

    final String kind = step.isAttendance
        ? l10n.galleryAttend
        : step.isStudy
        ? l10n.galleryStudy
        : l10n.gallerySolve;
    final String? start = step.suggestedStart;
    final String? end = step.suggestedEnd;
    final String timing = start != null && end != null
        ? format.range(start, end)
        : '';

    return <String>[
      kind,
      if (timing.isNotEmpty) timing,
      format.duration(step.minutes),
    ].join('، ');
  }
}

class _OverdueAlert extends StatelessWidget {
  const _OverdueAlert({
    required this.tasks,
    required this.minutes,
    required this.format,
  });

  final int tasks;
  final int minutes;
  final KhutatiFormat format;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/past-tasks'),
        borderRadius: BorderRadius.circular(KMetrics.statRadius),
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(
            horizontal: KMetrics.timelinePaddingX,
            vertical: KMetrics.timelinePaddingY,
          ),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(KMetrics.statRadius),
            border: Border.all(color: palette.red),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.todayOverdueTitle(tasks),
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.quoteSize,
                        fontWeight: FontWeight.w500,
                        color: palette.redtx,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.todayOverdueBody(format.duration(minutes)),
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.muteSize,
                        color: palette.mute,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_left_rounded, color: palette.redtx),
            ],
          ),
        ),
      ),
    );
  }
}

class TaskCard extends ConsumerStatefulWidget {
  const TaskCard({
    required this.task,
    required this.number,
    required this.accent,
    required this.format,
    super.key,
  });

  final PlanTask task;
  final int number;
  final Color accent;
  final KhutatiFormat format;

  @override
  ConsumerState<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<TaskCard> {
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    // The prototype opens every unfinished task; finished ones stay compact.
    _expanded = !widget.task.isComplete;
  }

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final PlanTask task = widget.task;

    final String title = <String>[
      task.subjectName ?? task.subjectKey,
      task.title,
    ].join(' — ');
    final String? range =
        task.suggestedStart != null && task.suggestedEnd != null
        ? widget.format.range(task.suggestedStart!, task.suggestedEnd!)
        : null;

    return Semantics(
      button: true,
      child: KCard(
        accentColor: widget.accent,
        showPattern: false,
        padding: EdgeInsets.zero,
        child: Column(
          children: <Widget>[
            // The ripple is drawn inside the card's own clip, so it can no
            // longer spill past the rounded corners when the row expands.
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: KMetrics.timelinePaddingX,
                    vertical: KMetrics.timelinePaddingY,
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 30,
                        child: Text(
                          '${widget.number}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: KTypography.displayFamily,
                            fontSize: KTypography.timelineNumSize,
                            fontWeight: FontWeight.w700,
                            color: widget.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title,
                              style: TextStyle(
                                fontFamily: KTypography.bodyFamily,
                                fontSize: KTypography.quoteSize,
                                fontWeight: FontWeight.w500,
                                color: palette.tx,
                              ),
                            ),
                            if (task.groupTitle != null &&
                                task.groupTitle!.trim().isNotEmpty)
                              Text(
                                task.groupTitle!,
                                style: TextStyle(
                                  fontFamily: KTypography.bodyFamily,
                                  fontSize: KTypography.smallSize,
                                  color: palette.mute,
                                ),
                              ),
                            if (range != null)
                              Text(
                                range,
                                style: TextStyle(
                                  fontFamily: KTypography.bodyFamily,
                                  fontSize: KTypography.smallSize,
                                  color: palette.mute,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: task.isComplete
                              ? palette.ok
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            KMetrics.pillRadius,
                          ),
                          border: Border.all(
                            color: task.isComplete ? palette.ok : palette.line,
                          ),
                        ),
                        child: Text(
                          '${task.completedStepCount}/${task.steps.length}',
                          style: TextStyle(
                            fontFamily: KTypography.bodyFamily,
                            fontSize: KTypography.counterSize,
                            color: task.isComplete
                                ? KColors.dark.bg
                                : palette.mute,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_expanded)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  KMetrics.timelinePaddingX,
                  0,
                  KMetrics.timelinePaddingX,
                  KMetrics.timelinePaddingY,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: palette.line)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: StepChips(task: task, format: widget.format),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class StepChips extends ConsumerWidget {
  const StepChips({required this.task, required this.format});

  final PlanTask task;
  final KhutatiFormat format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final List<PlanStep> steps = task.stepsInOrder;

    final List<Widget> chips = <Widget>[
      for (final PlanStep step in steps)
        KChip(
          title: step.isAttendance
              ? l10n.galleryAttend
              : step.isStudy
              ? l10n.galleryStudy
              : l10n.gallerySolve,
          subtitle: step.suggestedStart != null && step.suggestedEnd != null
              ? format.range(step.suggestedStart!, step.suggestedEnd!)
              : format.duration(step.minutes),
          // The bar only appears between the two taps; a completed chip is
          // already filled, so a full bar would say nothing new.
          fraction: step.progress == StepProgress.partial ? 0.5 : 0.0,
          icon: step.progress == StepProgress.completed
              ? Icons.check_rounded
              : step.isAttendance
              ? Icons.play_circle_outline_rounded
              : step.isStudy
              ? Icons.menu_book_outlined
              : Icons.quiz_outlined,
          selected: step.progress != StepProgress.notStarted,
          wide: steps.length == 1,
          onTap: () => _toggle(context, ref, step),
        ),
    ];

    if (chips.length == 1) return chips.single;

    // Stretch keeps the three chips the same height even when one of them
    // carries the partial-progress bar.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < chips.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: chips[i]),
        ],
      ],
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    PlanStep step,
  ) async {
    final StepProgress next = step.progress.nextWithinSession();
    final AppLocalizations l10n = context.l10n;

    ref.read(hapticsProvider).selection();

    await ref.read(todayActionsProvider).setStepCompleted(step.id, next);

    if (!context.mounted) return;
    if (next == StepProgress.partial) {
      showKToast(context, l10n.todayStepPartialToast);
    } else if (next == StepProgress.completed) {
      showKToast(context, l10n.todayStepCompleteToast);
    }
  }
}

class _LoadError extends ConsumerWidget {
  const _LoadError();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KMetrics.appPaddingX,
        KMetrics.appPaddingTop,
        KMetrics.appPaddingX,
        KMetrics.appPaddingBottom,
      ),
      children: <Widget>[
        Text(
          l10n.todayLoadError,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: KTypography.bodySize,
            color: palette.mute,
          ),
        ),
        const SizedBox(height: 12),
        KButton(
          label: l10n.todayRetry,
          variant: KButtonVariant.secondary,
          onPressed: () => ref.invalidate(todayDataProvider),
        ),
      ],
    );
  }
}
