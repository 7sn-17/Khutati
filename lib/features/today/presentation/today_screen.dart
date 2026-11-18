import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/tokens.dart';
import '../../../core/sound/sound_effects.dart';
import '../../../features/focus/application/focus_controller.dart';
import '../../../features/focus/application/focus_setup_controller.dart';
import '../../../features/focus/domain/focus_setup.dart';
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
      error: (Object error, StackTrace stack) => _LoadError(error: error),
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
            // The ECG line animates itself for 600 ms on every progress change;
            // keeping it in its own layer stops that repaint from touching the
            // rest of the hero card.
            child: RepaintBoundary(
              child: KEcgLine(progress: data.progress.fraction),
            ),
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
          _Quote(text: _quoteOfDay(data.now)),
          _Hero(data: data, format: format),
          if (data.overdueTasks > 0)
            _OverdueAlert(
              tasks: data.overdueTasks,
              minutes: data.overdueMinutes,
              format: format,
            ),
          KSectionHeader(title: l10n.todaySchedule),
          if (data.tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: Text(
                l10n.todayAllDoneBody,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.muteSize,
                  color: palette.mute,
                ),
              ),
            )
          else
            ..._timeline(context, l10n, format),
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
              format.tryRange(rest.startClock, rest.endClock) ?? '—',
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
    try {
      final String clock = KhutatiFormat.twelveHour(end);
      final String part = format.dayPart(KhutatiFormat.minutesOfDay(end) ~/ 60);
      return '$clock $part';
    } on FormatException {
      return '—';
    }
  }

  String _quoteOfDay(DateTime now) {
    // A quiet dhikr rotates with the local calendar date. Keeping the change
    // daily (not per rebuild) means the section is stable while the user reads
    // it and never animates while they are tapping steps.
    final List<String> phrases = <String>[
      'سبحان الله',
      'الحمد لله',
      'لا إله إلا الله',
      'الله أكبر',
      'اللهم صلِّ على سيدنا محمد',
      'أستغفر الله العظيم وأتوب إليه',
      'لا حول ولا قوة إلا بالله',
      'سبحان الله وبحمده، سبحان الله العظيم',
      'حسبي الله ونعم الوكيل',
      'اللهم إني أسألك العلم النافع والعمل الصالح',
    ];
    final int day = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(2026)).inDays.abs();
    return phrases[day % phrases.length];
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

    final BorderRadius borderRadius = BorderRadius.circular(
      KMetrics.quoteRadius,
    );
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
            decoration: BoxDecoration(
              color: palette.card2,
              borderRadius: borderRadius,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4),
                  child: Icon(
                    Icons.format_quote_rounded,
                    size: 22,
                    color: palette.gold.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: KTypography.quoteSize,
                      height: 1.7,
                      color: palette.tx,
                    ),
                  ),
                ),
              ],
            ),
          ),
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: palette.gold),
          ),
        ],
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
                onPressed: () {
                  final List<PlanStep> steps = next.stepsInOrder;
                  final PlanStep? step = next.nextStep;
                  final int currentIndex = step == null
                      ? 0
                      : steps.indexWhere((PlanStep s) => s.id == step.id);
                  final FocusTaskDraft draft = FocusTaskDraft(
                    taskId: next.id,
                    taskTitle: next.title,
                    subjectName:
                        next.subjectName ?? data.subjectNames[next.subjectKey],
                    startIndex: currentIndex < 0 ? 0 : currentIndex,
                    steps: <FocusStepRef>[
                      for (final PlanStep s in steps)
                        FocusStepRef(
                          id: s.id,
                          label: s.isAttendance
                              ? l10n.galleryAttend
                              : s.isStudy
                              ? l10n.galleryStudy
                              : l10n.gallerySolve,
                          minutes: s.minutes > 0 ? s.minutes : 25,
                        ),
                    ],
                  );
                  ref.read(focusDraftProvider.notifier).state = draft;
                  ref
                      .read(focusSetupProvider.notifier)
                      .setMode(FocusMode.linked);
                  context.go('/focus');
                },
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
    final String timing =
        format.tryRange(step.suggestedStart, step.suggestedEnd) ?? '';

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
    // Never throws: a malformed clock string hides the time line instead of
    // taking the whole schedule down with it.
    final String? range = widget.format.tryRange(
      task.suggestedStart,
      task.suggestedEnd,
    );
    final int stepCount = task.steps.length;

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
                          '${task.status == PlanTaskStatus.completed ? stepCount : task.completedStepCount}/$stepCount',
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

class StepChips extends ConsumerStatefulWidget {
  const StepChips({required this.task, required this.format, super.key});

  final PlanTask task;
  final KhutatiFormat format;

  @override
  ConsumerState<StepChips> createState() => _StepChipsState();
}

class _StepChipsState extends ConsumerState<StepChips> {
  /// Immediate UI values for taps whose database write is still in flight.
  ///
  /// Four fast taps must walk the cycle four times. Reading `step.progress`
  /// from the last build would make every tap recompute the same first
  /// transition, which is exactly what skipped `partialDown`.
  final Map<String, StepProgress> _optimistic = <String, StepProgress>{};
  final Set<String> _pending = <String>{};
  final Map<String, Future<void>> _writes = <String, Future<void>>{};
  String? _toastStepId;
  Timer? _toastTimer;

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StepChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _optimistic.clear();
      _pending.clear();
      _writes.clear();
      return;
    }
    // Once the write queue drains, drop overrides that the live row has
    // already confirmed, so edits from Plan/another surface show up here.
    for (final PlanStep step in widget.task.stepsInOrder) {
      final StepProgress? local = _optimistic[step.id];
      if (local != null && !_pending.contains(step.id)) {
        if (local == _liveProgress(step)) _optimistic.remove(step.id);
      }
    }
  }

  bool get _taskCompleted => widget.task.status == PlanTaskStatus.completed;

  StepProgress _liveProgress(PlanStep step) {
    if (_taskCompleted && step.progress == StepProgress.notStarted) {
      return StepProgress.completed;
    }
    return step.progress;
  }

  StepProgress _displayProgress(PlanStep step) =>
      _optimistic[step.id] ?? _liveProgress(step);

  PlanStep? _stepById(String id) {
    for (final PlanStep step in widget.task.stepsInOrder) {
      if (step.id == id) return step;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<PlanStep> steps = widget.task.stepsInOrder;

    final List<Widget> chips = <Widget>[
      for (final PlanStep step in steps)
        () {
          final StepProgress effective = _displayProgress(step);
          return KChip(
            title: step.isAttendance
                ? l10n.galleryAttend
                : step.isStudy
                ? l10n.galleryStudy
                : l10n.gallerySolve,
            subtitle:
                widget.format.tryRange(
                  step.suggestedStart,
                  step.suggestedEnd,
                ) ??
                widget.format.duration(step.minutes),
            fraction: effective.isPartial ? 0.5 : 0.0,
            icon: effective == StepProgress.completed
                ? Icons.check_rounded
                : step.isAttendance
                ? Icons.play_circle_outline_rounded
                : step.isStudy
                ? Icons.menu_book_outlined
                : Icons.quiz_outlined,
            selected: effective != StepProgress.notStarted,
            wide: steps.length == 1,
            onTap: () => _toggle(step),
          );
        }(),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();
    if (chips.length == 1) return chips.single;

    // Equal-height chips: the partial-progress bar makes one chip taller, and
    // the row must still line up. IntrinsicHeight supplies the bounded height
    // that `stretch` needs — without it the Row asks for infinite height inside
    // the unbounded scroll list and the whole card collapses to blank space.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < chips.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: chips[i]),
          ],
        ],
      ),
    );
  }

  void _toggle(PlanStep step) {
    ref.read(hapticsProvider).selection();

    final StepProgress next = _displayProgress(step).next();
    setState(() {
      _optimistic[step.id] = next;
      _pending.add(step.id);
    });

    // One chain per step: every tap appends its write, so the database sees
    // partialUp → completed → partialDown → notStarted in order instead of
    // four concurrent updates racing to the same final row.
    final Future<void> previous = _writes[step.id] ?? Future<void>.value();
    final Future<void> write = previous
        .then(
          (_) => ref.read(todayActionsProvider).setStepCompleted(step.id, next),
        )
        .catchError((Object _) {});
    _writes[step.id] = write;

    unawaited(
      write.whenComplete(() {
        if (!mounted) return;
        if (!identical(_writes[step.id], write)) return;
        _writes.remove(step.id);
        _pending.remove(step.id);
        final StepProgress? local = _optimistic[step.id];
        final PlanStep? current = _stepById(step.id);
        if (local != null &&
            current != null &&
            local == _liveProgress(current)) {
          _optimistic.remove(step.id);
        }
        setState(() {});
      }),
    );

    _scheduleToast(step);
  }

  /// A single toast per burst of taps. Four rapid taps should read as one
  /// action, not four stacked snackbars.
  void _scheduleToast(PlanStep step) {
    _toastStepId = step.id;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 420), () {
      if (!mounted || _toastStepId != step.id) return;
      final PlanStep? current = _stepById(step.id);
      if (current == null) return;
      final StepProgress settled =
          _optimistic[step.id] ?? _liveProgress(current);
      final AppLocalizations l10n = context.l10n;
      if (settled.isPartial) {
        showKToast(context, l10n.todayStepPartialToast);
      } else if (settled == StepProgress.completed) {
        SoundEffects.success();
        showKToast(context, l10n.todayStepCompleteToast);
      }
    });
  }
}

class _LoadError extends ConsumerWidget {
  const _LoadError({this.error});

  /// Debug-only detail, so a failing provider can never look like a blank tab.
  final Object? error;

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
        if (kDebugMode && error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '$error',
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.smallSize,
              color: palette.redtx,
            ),
          ),
        ],
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
