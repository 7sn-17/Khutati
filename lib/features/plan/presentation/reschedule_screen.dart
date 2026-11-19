import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/sound/sound_effects.dart';
import '../../../core/utils/format.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../domain/plan/plan_calendar.dart';
import '../../../domain/plan/schedule_engine.dart' show ScheduleOverrideInput;
import '../../../l10n/l10n.dart';
import '../application/plan_browser_controller.dart';
import '../application/reschedule_draft.dart';

/// Manual rescheduling, as a screen instead of a bottom sheet.
///
/// The sheet showed one task and a list of numbers, so the user could not see
/// the day they were moving into or what would happen to the rest of the week.
/// This screen shows the whole week as a timeline, lets a task be dragged or
/// nudged with arrows, and states the consequence of a move before it is saved.
class RescheduleScreen extends ConsumerStatefulWidget {
  const RescheduleScreen({super.key});

  @override
  ConsumerState<RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends ConsumerState<RescheduleScreen> {
  PlanCalendar? _calendar;
  RescheduleDraft? _draft;
  ScheduleImpact? _impact;
  int? _week;
  int? _expandedDay;

  // The move panel edits a candidate before it becomes part of the draft.
  String? _movingId;
  int _moveDay = 0;
  int _movePosition = 1;
  RescheduleDraft? _candidateDraft;
  ScheduleImpact? _candidateImpact;
  bool _candidateLoading = false;
  int _candidateRequest = 0;

  bool _loading = true;
  bool _busy = false;

  KhutatiPalette get _palette => context.palette;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final PlanCalendar? calendar = await ref.read(planCalendarProvider.future);
    if (!mounted || calendar == null) return;
    final ScheduleImpact impact = await ref
        .read(scheduleRepositoryProvider)
        .previewOverrides(calendar, const <String, ScheduleOverrideInput>{});
    if (!mounted) return;
    setState(() {
      _calendar = calendar;
      _draft = RescheduleDraft(impact.schedule);
      _impact = impact;
      _week = _currentWeek(impact.schedule);
      _movingId = null;
      _candidateDraft = null;
      _candidateImpact = null;
      _loading = false;
    });
  }

  int _currentWeek(ScheduleSnapshot snapshot) {
    final PlanBrowserData? data = ref.read(planBrowserProvider).valueOrNull;
    if (data == null) return snapshot.days.first.week;
    return data.currentWeek;
  }

  Future<void> _apply(RescheduleDraft next) async {
    final PlanCalendar? calendar = _calendar;
    if (calendar == null) return;
    setState(() => _busy = true);
    try {
      final ScheduleImpact impact = await ref
          .read(scheduleRepositoryProvider)
          .previewOverrides(calendar, next.entries);
      if (!mounted) return;
      if (!impact.ok) {
        showKToast(context, context.l10n.rsMoveInvalid, kind: KToastKind.error);
        return;
      }
      setState(() {
        _draft = next;
        _impact = impact;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final PlanCalendar? calendar = _calendar;
    final RescheduleDraft? draft = _draft;
    if (calendar == null || draft == null || draft.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(scheduleRepositoryProvider)
          .commitOverrides(calendar, draft.entries);
      if (!mounted) return;
      showKToast(context, context.l10n.rsSaved);
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showKToast(context, context.l10n.rsSaveFailed, kind: KToastKind.error);
    }
  }

  Future<void> _restoreAll() async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showKDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => KDialog(
        eyebrow: l10n.settingsPlanSection,
        title: l10n.rsRestore,
        message: l10n.pdClearManualMessage,
        icon: Icons.settings_backup_restore_rounded,
        accent: _palette.gold,
        actions: <KDialogAction>[
          KDialogAction(
            label: l10n.settingsPracticalDaysResetConfirm,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        secondaryActions: <KDialogAction>[
          KDialogAction(
            label: l10n.rsCancelMove,
            variant: KButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
        onClose: () => Navigator.of(ctx).pop(false),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(scheduleRepositoryProvider).clearAllOverrides();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      showKToast(context, l10n.rsRestored);
    } catch (_) {
      if (!mounted) return;
      showKToast(context, l10n.rsSaveFailed, kind: KToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- Move panel -----------------------------------------------------------

  void _startMove(ScheduledTask task) {
    ref.read(hapticsProvider).selection();
    setState(() {
      _movingId = task.task.id;
      _moveDay = task.dayNumber;
      _movePosition = task.order;
      _candidateImpact = null;
    });
    _refreshCandidate();
  }

  void _cancelMove() {
    setState(() {
      _movingId = null;
      _candidateDraft = null;
      _candidateImpact = null;
    });
  }

  List<int> _studyDays() {
    final ScheduleImpact? impact = _impact;
    final int? week = _week;
    if (impact == null || week == null) return const <int>[];
    return <int>[
      for (final ScheduledDay day in impact.schedule.days)
        if (day.week == week && !day.isRest) day.dayNumber,
    ];
  }

  void _stepDay(int delta) {
    final List<int> days = _studyDays();
    final int index = days.indexOf(_moveDay);
    if (index < 0) return;
    final int target = index + delta;
    if (target < 0 || target >= days.length) return;
    ref.read(hapticsProvider).selection();
    SoundEffects.toggle();
    setState(() {
      _moveDay = days[target];
      _movePosition = _clampPosition(_movePosition, _moveDay);
    });
    _refreshCandidate();
  }

  int _maxPosition(int dayNumber) {
    final ScheduleImpact? impact = _impact;
    if (impact == null) return 1;
    final int count = impact.schedule
        .tasksForDay(dayNumber)
        .where((ScheduledTask task) => task.task.id != _movingId)
        .length;
    return count + 1;
  }

  int _clampPosition(int position, int dayNumber) {
    final int max = _maxPosition(dayNumber);
    return position < 1 ? 1 : (position > max ? max : position);
  }

  void _stepPosition(int delta) {
    final int next = _clampPosition(_movePosition + delta, _moveDay);
    if (next == _movePosition) return;
    ref.read(hapticsProvider).selection();
    SoundEffects.toggle();
    setState(() => _movePosition = next);
    _refreshCandidate();
  }

  Future<void> _refreshCandidate() async {
    final PlanCalendar? calendar = _calendar;
    final RescheduleDraft? draft = _draft;
    final String? taskId = _movingId;
    if (calendar == null || draft == null || taskId == null) return;

    final int request = ++_candidateRequest;
    setState(() => _candidateLoading = true);
    final RescheduleDraft candidate = draft.move(
      taskId,
      toDay: _moveDay,
      position: _movePosition,
    );
    final ScheduleImpact impact = await ref
        .read(scheduleRepositoryProvider)
        .previewOverrides(calendar, candidate.entries);
    if (!mounted || request != _candidateRequest) return;
    setState(() {
      _candidateDraft = candidate;
      _candidateImpact = impact;
      _candidateLoading = false;
    });
  }

  void _confirmMove() {
    final RescheduleDraft? candidate = _candidateDraft;
    final ScheduleImpact? impact = _candidateImpact;
    if (candidate == null || impact == null || !impact.ok) return;
    ref.read(hapticsProvider).selection();
    SoundEffects.toggle();
    setState(() {
      _draft = candidate;
      _impact = impact;
      _expandedDay = _moveDay;
      _movingId = null;
      _candidateDraft = null;
      _candidateImpact = null;
    });
  }

  void _nudge(ScheduledTask task, int delta) {
    final ScheduleImpact? impact = _impact;
    final RescheduleDraft? draft = _draft;
    if (impact == null || draft == null) return;
    final List<ScheduledTask> tasks = impact.schedule.tasksForDay(
      task.dayNumber,
    );
    final int? position = RescheduleDraft.targetPosition(
      tasks,
      task.task.id,
      delta,
    );
    if (position == null) return;
    ref.read(hapticsProvider).selection();
    SoundEffects.toggle();
    _apply(draft.move(task.task.id, toDay: task.dayNumber, position: position));
  }

  void _drop(String taskId, int dayNumber, int position) {
    final RescheduleDraft? draft = _draft;
    if (draft == null) return;
    ref.read(hapticsProvider).selection();
    SoundEffects.toggle();
    // Reveal the destination so the drop has a visible result even when the
    // target day was collapsed.
    setState(() => _expandedDay = dayNumber);
    _apply(draft.move(taskId, toDay: dayNumber, position: position));
  }

  void _undo() {
    final RescheduleDraft? previous = _draft?.undo();
    if (previous == null) return;
    ref.read(hapticsProvider).selection();
    _apply(previous);
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<PlanBrowserData?> browser = ref.watch(planBrowserProvider);
    final PlanBrowserData? data = browser.valueOrNull;
    final ScheduleImpact? impact = _impact;
    final RescheduleDraft? draft = _draft;

    return Scaffold(
      backgroundColor: _palette.bg,
      appBar: AppBar(
        backgroundColor: _palette.bg,
        surfaceTintColor: Colors.transparent,
        leading: const BackButton(),
        titleSpacing: 0,
        title: Text(
          l10n.rsTitle,
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _palette.tx,
          ),
        ),
        actions: <Widget>[
          if (draft != null && draft.canUndo)
            IconButton(
              tooltip: l10n.rsUndo,
              onPressed: _busy ? null : _undo,
              icon: Icon(Icons.undo_rounded, color: _palette.tx),
            ),
          if (draft != null &&
              draft.isEmpty &&
              (impact?.schedule.hasOverrides ?? false))
            IconButton(
              tooltip: l10n.rsRestore,
              onPressed: _busy ? null : _restoreAll,
              icon: Icon(
                Icons.settings_backup_restore_rounded,
                color: _palette.gold,
              ),
            ),
        ],
      ),
      body: _loading || data == null || impact == null || draft == null
          ? const Center(child: CircularProgressIndicator())
          : _body(data, draft, impact),
    );
  }

  Widget _body(
    PlanBrowserData data,
    RescheduleDraft draft,
    ScheduleImpact impact,
  ) {
    final AppLocalizations l10n = context.l10n;
    final int week = _week ?? data.currentWeek;
    final List<ScheduledDay> days = <ScheduledDay>[
      for (final ScheduledDay day in impact.schedule.days)
        if (day.week == week) day,
    ];
    final int first = days.isEmpty ? 1 : days.first.dayNumber;
    final int last = days.isEmpty ? 1 : days.last.dayNumber;

    return Column(
      children: <Widget>[
        Expanded(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  KMetrics.appPaddingX,
                  4,
                  KMetrics.appPaddingX,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: _WeekHeader(
                    week: week,
                    totalWeeks: data.calendar.weekCount,
                    firstDay: first,
                    lastDay: last,
                    onPrevious: week > 1
                        ? () => setState(() {
                            _week = week - 1;
                            _expandedDay = null;
                            _cancelMove();
                          })
                        : null,
                    onNext: week < data.calendar.weekCount
                        ? () => setState(() {
                            _week = week + 1;
                            _expandedDay = null;
                            _cancelMove();
                          })
                        : null,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  KMetrics.appPaddingX,
                  12,
                  KMetrics.appPaddingX,
                  12,
                ),
                sliver: SliverList.builder(
                  itemCount: days.length,
                  itemBuilder: (BuildContext context, int index) {
                    final ScheduledDay day = days[index];
                    final List<ScheduledTask> tasks = impact.schedule
                        .tasksForDay(day.dayNumber);
                    final DateTime date = data.days[day.dayNumber - 1].date;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: KMetrics.cardGap),
                      child: _DayBlock(
                        day: day,
                        tasks: tasks,
                        date: date,
                        expanded: _expandedDay == day.dayNumber,
                        movingId: _movingId,
                        busy: _busy,
                        onToggle: day.isRest
                            ? null
                            : () {
                                ref.read(hapticsProvider).selection();
                                setState(() {
                                  _expandedDay = _expandedDay == day.dayNumber
                                      ? null
                                      : day.dayNumber;
                                  _cancelMove();
                                });
                              },
                        onStartMove: _startMove,
                        onNudge: _nudge,
                        onDrop: _drop,
                        movePanel: _movePanelFor(day, tasks),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (!draft.isEmpty) _ImpactPanel(impact: impact),
        _BottomBar(
          busy: _busy,
          count: draft.count,
          onCancel: () => context.pop(),
          onSave: draft.isEmpty || _busy ? null : _save,
        ),
      ],
    );
  }

  Widget? _movePanelFor(ScheduledDay day, List<ScheduledTask> tasks) {
    final String? movingId = _movingId;
    if (movingId == null) return null;
    ScheduledTask? task;
    for (final ScheduledTask item in tasks) {
      if (item.task.id == movingId) {
        task = item;
        break;
      }
    }
    if (task == null) return null;
    return _MovePanel(
      title: context.l10n.rsMoveTitle(task.task.title),
      dayLabel: context.l10n.pdImpactDay(_moveDay),
      positionLabel: context.l10n.rsPositionOf(
        _movePosition,
        _maxPosition(_moveDay),
      ),
      sameDay: _moveDay == day.dayNumber,
      canDecreaseDay: _studyDays().indexOf(_moveDay) > 0,
      canIncreaseDay: _studyDays().indexOf(_moveDay) < _studyDays().length - 1,
      canDecreasePosition: _movePosition > 1,
      canIncreasePosition: _movePosition < _maxPosition(_moveDay),
      loading: _candidateLoading,
      impact: _candidateImpact,
      movingId: movingId,
      onDay: _stepDay,
      onPosition: _stepPosition,
      onCancel: _cancelMove,
      onConfirm: _confirmMove,
    );
  }
}

// ---------------------------------------------------------------------------
// Week header
// ---------------------------------------------------------------------------

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.week,
    required this.totalWeeks,
    required this.firstDay,
    required this.lastDay,
    required this.onPrevious,
    required this.onNext,
  });

  final int week;
  final int totalWeeks;
  final int firstDay;
  final int lastDay;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final AppLocalizations l10n = context.l10n;

    return KCard(
      showPattern: false,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _RoundStep(
                icon: Icons.chevron_right_rounded,
                onTap: onPrevious,
                palette: palette,
              ),
              Expanded(
                child: Column(
                  children: <Widget>[
                    Text(
                      l10n.rsWeekOf(week, totalWeeks),
                      style: TextStyle(
                        fontFamily: KTypography.displayFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.tx,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.rsWeekRange(firstDay, lastDay),
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 11,
                        color: palette.mute,
                      ),
                    ),
                  ],
                ),
              ),
              _RoundStep(
                icon: Icons.chevron_left_rounded,
                onTap: onNext,
                palette: palette,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.rsHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 12,
              height: 1.6,
              color: palette.mute,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundStep extends StatelessWidget {
  const _RoundStep({
    required this.icon,
    required this.onTap,
    required this.palette,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: KInkSurface(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KMetrics.pillRadius),
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 22, color: palette.tx),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day block
// ---------------------------------------------------------------------------

class _DayBlock extends StatelessWidget {
  const _DayBlock({
    required this.day,
    required this.tasks,
    required this.date,
    required this.expanded,
    required this.movingId,
    required this.busy,
    required this.onToggle,
    required this.onStartMove,
    required this.onNudge,
    required this.onDrop,
    required this.movePanel,
  });

  final ScheduledDay day;
  final List<ScheduledTask> tasks;
  final DateTime date;
  final bool expanded;
  final String? movingId;
  final bool busy;
  final VoidCallback? onToggle;
  final ValueChanged<ScheduledTask> onStartMove;
  final void Function(ScheduledTask task, int delta) onNudge;
  final void Function(String taskId, int dayNumber, int position) onDrop;
  final Widget? movePanel;

  int get _minutes =>
      tasks.fold<int>(0, (int sum, ScheduledTask t) => sum + t.plannedMinutes);

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final AppLocalizations l10n = context.l10n;
    final KhutatiFormat format = KhutatiFormat(l10n);

    return KCard(
      showPattern: false,
      padding: EdgeInsets.zero,
      onTap: onToggle,
      child: Column(
        children: <Widget>[
          // The header is a drop target too, so a task can be sent to a day
          // that is still collapsed instead of forcing the user to open it
          // first. Dropping here appends to the end of that day.
          DragTarget<String>(
            onWillAcceptWithDetails: (DragTargetDetails<String> details) =>
                !day.isRest,
            onAcceptWithDetails: (DragTargetDetails<String> details) =>
                onDrop(details.data, day.dayNumber, tasks.length + 1),
            builder:
                (
                  BuildContext context,
                  List<String?> candidates,
                  List<dynamic> rejected,
                ) {
                  final bool hovering = candidates.isNotEmpty;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    color: hovering
                        ? palette.gold.withValues(alpha: 0.07)
                        : Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        14,
                        12,
                        10,
                        12,
                      ),
                      child: Row(
                        children: <Widget>[
                          _DayNumber(
                            number: day.dayNumber,
                            practical: day.isPractical,
                            rest: day.isRest,
                            palette: palette,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  _weekday(date),
                                  style: TextStyle(
                                    fontFamily: KTypography.displayFamily,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: palette.tx,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  day.isRest
                                      ? l10n.rsRestDay
                                      : l10n.rsTasksAndTime(
                                          tasks.length,
                                          format.duration(_minutes),
                                        ),
                                  style: TextStyle(
                                    fontFamily: KTypography.bodyFamily,
                                    fontSize: 11,
                                    color: palette.mute,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!day.isRest)
                            _TypePill(
                              practical: day.isPractical,
                              palette: palette,
                            ),
                          if (!day.isRest) const SizedBox(width: 4),
                          if (!day.isRest)
                            AnimatedRotation(
                              duration: const Duration(
                                milliseconds: KMotion.navMs,
                              ),
                              turns: expanded ? 0.5 : 0,
                              child: Icon(
                                Icons.expand_more_rounded,
                                size: 22,
                                color: palette.mute,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: KMotion.navMs),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: <Widget>[
                      Container(height: 1, color: palette.line),
                      if (tasks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            l10n.rsNoTasks,
                            style: TextStyle(
                              fontFamily: KTypography.bodyFamily,
                              fontSize: 12,
                              color: palette.mute,
                            ),
                          ),
                        )
                      else
                        for (int index = 0; index < tasks.length; index++)
                          _TaskRow(
                            index: index,
                            task: tasks[index],
                            moving: movingId == tasks[index].task.id,
                            busy: busy,
                            canUp: index > 0,
                            canDown: index < tasks.length - 1,
                            onMove: () => onStartMove(tasks[index]),
                            onUp: () => onNudge(tasks[index], -1),
                            onDown: () => onNudge(tasks[index], 1),
                            onDrop: (String taskId) =>
                                onDrop(taskId, day.dayNumber, index + 1),
                            panel: movingId == tasks[index].task.id
                                ? movePanel
                                : null,
                          ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _weekday(DateTime date) {
    return KhutatiFormat.westernDigits(DateFormat('EEEE', 'ar').format(date));
  }
}

class _DayNumber extends StatelessWidget {
  const _DayNumber({
    required this.number,
    required this.practical,
    required this.rest,
    required this.palette,
  });

  final int number;
  final bool practical;
  final bool rest;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    final Color tint = rest
        ? palette.mute
        : practical
        ? palette.gold
        : palette.tx;
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: rest ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          fontFamily: KTypography.displayFamily,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: tint,
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.practical, required this.palette});

  final bool practical;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final Color tint = practical ? palette.gold : palette.mute;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(KMetrics.pillRadius),
      ),
      child: Text(
        practical ? l10n.planPracticalDay : l10n.planStudyDay,
        style: TextStyle(
          fontFamily: KTypography.bodyFamily,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: tint,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Task row
// ---------------------------------------------------------------------------

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.index,
    required this.task,
    required this.moving,
    required this.busy,
    required this.canUp,
    required this.canDown,
    required this.onMove,
    required this.onUp,
    required this.onDown,
    required this.onDrop,
    required this.panel,
  });

  final int index;
  final ScheduledTask task;
  final bool moving;
  final bool busy;
  final bool canUp;
  final bool canDown;
  final VoidCallback onMove;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final ValueChanged<String> onDrop;
  final Widget? panel;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final AppLocalizations l10n = context.l10n;

    final Widget row = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 6, 6),
      child: Row(
        children: <Widget>[
          _OrderChip(number: index + 1, palette: palette),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  task.task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: palette.tx,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${task.startClock ?? '—'} – ${task.endClock ?? '—'}',
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 11,
                    color: palette.mute,
                  ),
                ),
              ],
            ),
          ),
          if (task.isManual)
            Tooltip(
              message: l10n.rsManual,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.edit_calendar_rounded,
                  size: 14,
                  color: palette.gold,
                ),
              ),
            ),
          _Arrow(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: l10n.rsMoveUp,
            onTap: busy || !canUp ? null : onUp,
            palette: palette,
          ),
          _Arrow(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: l10n.rsMoveDown,
            onTap: busy || !canDown ? null : onDown,
            palette: palette,
          ),
        ],
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (DragTargetDetails<String> details) =>
          details.data != task.task.id,
      onAcceptWithDetails: (DragTargetDetails<String> details) =>
          onDrop(details.data),
      builder:
          (
            BuildContext context,
            List<String?> candidates,
            List<dynamic> rejected,
          ) {
            final bool hovering = candidates.isNotEmpty;
            return Column(
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  decoration: BoxDecoration(
                    color: moving
                        ? palette.gold.withValues(alpha: 0.08)
                        : hovering
                        ? palette.gold.withValues(alpha: 0.06)
                        : Colors.transparent,
                    border: BorderDirectional(
                      top: BorderSide(
                        color: hovering ? palette.gold : Colors.transparent,
                        width: 1.4,
                      ),
                    ),
                  ),
                  child: LongPressDraggable<String>(
                    data: task.task.id,
                    delay: const Duration(milliseconds: 180),
                    feedback: Material(
                      color: Colors.transparent,
                      child: _DragFeedback(title: task.task.title),
                    ),
                    childWhenDragging: Opacity(opacity: 0.35, child: row),
                    child: KInkSurface(onTap: busy ? null : onMove, child: row),
                  ),
                ),
                if (panel != null) panel!,
              ],
            );
          },
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.gold),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.drag_indicator_rounded, size: 16, color: palette.gold),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.tx,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderChip extends StatelessWidget {
  const _OrderChip({required this.number, required this.palette});

  final int number;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.card2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.line),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          fontFamily: KTypography.bodyFamily,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: palette.mute,
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.palette,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.3 : 1,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        iconSize: 22,
        icon: Icon(icon, color: palette.tx),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Move panel
// ---------------------------------------------------------------------------

class _MovePanel extends StatelessWidget {
  const _MovePanel({
    required this.title,
    required this.dayLabel,
    required this.positionLabel,
    required this.sameDay,
    required this.canDecreaseDay,
    required this.canIncreaseDay,
    required this.canDecreasePosition,
    required this.canIncreasePosition,
    required this.loading,
    required this.impact,
    required this.movingId,
    required this.onDay,
    required this.onPosition,
    required this.onCancel,
    required this.onConfirm,
  });

  final String title;
  final String dayLabel;
  final String positionLabel;
  final bool sameDay;
  final bool canDecreaseDay;
  final bool canIncreaseDay;
  final bool canDecreasePosition;
  final bool canIncreasePosition;
  final bool loading;
  final ScheduleImpact? impact;
  final String movingId;
  final ValueChanged<int> onDay;
  final ValueChanged<int> onPosition;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final AppLocalizations l10n = context.l10n;
    final ScheduleImpact? value = impact;
    final bool ok = value?.ok == true;

    final String message;
    if (loading || value == null) {
      message = l10n.msCalculating;
    } else if (!ok) {
      message = l10n.rsMoveInvalid;
    } else {
      final int affected = value.moves
          .where((TaskPlacementChange move) => move.task.task.id != movingId)
          .length;
      final int day = value.schedule.tasksById[movingId]?.dayNumber ?? 0;
      final int position = value.schedule.tasksById[movingId]?.order ?? 0;
      final int total = value.schedule.tasksForDay(day).length;
      final String sentence = sameDay
          ? l10n.rsMoveSameDay(position, total, day)
          : l10n.rsMoveOtherDay(day, position);
      message = affected == 0
          ? sentence
          : '$sentence ${l10n.rsMoveAffected(affected)}';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.card2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ok ? palette.line : palette.red),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: palette.tx,
            ),
          ),
          const SizedBox(height: 10),
          _StepperRow(
            label: l10n.rsToDay,
            value: dayLabel,
            onDecrease: canDecreaseDay ? () => onDay(-1) : null,
            onIncrease: canIncreaseDay ? () => onDay(1) : null,
            palette: palette,
          ),
          const SizedBox(height: 8),
          _StepperRow(
            label: l10n.rsPosition,
            value: positionLabel,
            onDecrease: canDecreasePosition ? () => onPosition(-1) : null,
            onIncrease: canIncreasePosition ? () => onPosition(1) : null,
            palette: palette,
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(
                ok ? Icons.info_outline_rounded : Icons.error_outline_rounded,
                size: 15,
                color: ok ? palette.mute : palette.redtx,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 11,
                    height: 1.5,
                    color: ok ? palette.mute : palette.redtx,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: KButton(
                  label: l10n.rsCancelMove,
                  variant: KButtonVariant.secondary,
                  onPressed: onCancel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: KButton(
                  label: l10n.rsConfirmMove,
                  loading: loading,
                  onPressed: ok && !loading ? onConfirm : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    required this.palette,
  });

  final String label;
  final String value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 12,
            color: palette.mute,
          ),
        ),
        const Spacer(),
        _StepButton(
          icon: Icons.remove_rounded,
          onTap: onDecrease,
          palette: palette,
        ),
        SizedBox(
          width: 92,
          child: Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: palette.tx,
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          onTap: onIncrease,
          palette: palette,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.palette,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.3 : 1,
      child: KInkSurface(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        color: palette.card,
        border: BorderSide(color: palette.line),
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: palette.tx),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Impact panel and bottom bar
// ---------------------------------------------------------------------------

class _ImpactPanel extends StatelessWidget {
  const _ImpactPanel({required this.impact});

  final ScheduleImpact impact;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final AppLocalizations l10n = context.l10n;
    final KhutatiFormat format = KhutatiFormat(l10n);
    final int finish = impact.finishDayDelta;
    final List<DayImpact> days = impact.days.take(3).toList(growable: false);

    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(top: BorderSide(color: palette.line)),
      ),
      padding: const EdgeInsets.fromLTRB(
        KMetrics.appPaddingX,
        10,
        KMetrics.appPaddingX,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_awesome_rounded, size: 15, color: palette.gold),
              const SizedBox(width: 6),
              // Both labels are Arabic and the finish sentence grows with the
              // number of shifted days, so neither may take its natural width:
              // on a 390dp phone the two together overflowed the header row.
              Expanded(
                child: Text(
                  l10n.rsImpactTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: palette.tx,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  finish == 0
                      ? l10n.pdImpactFinishSame
                      : finish > 0
                      ? l10n.pdImpactFinishLater(finish)
                      : l10n.pdImpactFinishEarlier(-finish),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 11,
                    color: finish == 0 ? palette.mute : palette.gold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final DayImpact day in days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: <Widget>[
                  Icon(
                    day.deltaTasks > 0
                        ? Icons.add_circle_rounded
                        : day.deltaTasks < 0
                        ? Icons.remove_circle_rounded
                        : Icons.swap_horiz_rounded,
                    size: 14,
                    color: day.deltaTasks > 0
                        ? palette.ok
                        : day.deltaTasks < 0
                        ? palette.redtx
                        : palette.mute,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.pdImpactDay(day.dayNumber),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 11,
                        color: palette.tx,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      day.deltaTasks == 0
                          ? l10n.pdImpactTimeOnly
                          : '${day.deltaTasks > 0 ? '+' : '−'}'
                                '${day.deltaTasks.abs()} · '
                                '${day.deltaMinutes > 0 ? '+' : '−'}'
                                '${format.duration(day.deltaMinutes.abs())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: day.deltaTasks > 0
                            ? palette.ok
                            : day.deltaTasks < 0
                            ? palette.redtx
                            : palette.mute,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (impact.days.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.pdImpactMoreDays(impact.days.length - 3),
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 10,
                  color: palette.mute,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.busy,
    required this.count,
    required this.onCancel,
    required this.onSave,
  });

  final bool busy;
  final int count;
  final VoidCallback onCancel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final AppLocalizations l10n = context.l10n;

    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border(top: BorderSide(color: palette.line)),
      ),
      padding: EdgeInsets.fromLTRB(
        KMetrics.appPaddingX,
        10,
        KMetrics.appPaddingX,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: KButton(
              label: l10n.rsCancelMove,
              variant: KButtonVariant.secondary,
              onPressed: busy ? null : onCancel,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: KButton(
              label: count == 0 ? l10n.rsSave : l10n.rsSaveCount(count),
              loading: busy,
              onPressed: onSave,
            ),
          ),
        ],
      ),
    );
  }
}
