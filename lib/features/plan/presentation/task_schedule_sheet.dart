import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/sound/sound_effects.dart';
import '../../../core/utils/format.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../domain/plan/plan_task.dart';
import '../../../l10n/l10n.dart';
import '../application/plan_browser_controller.dart';
import '../application/task_schedule_controller.dart';

/// Opens the manual scheduling sheet for one task.
Future<void> showTaskScheduleSheet(
  BuildContext context, {
  required PlanTask task,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => _TaskScheduleSheet(task: task),
  );
}

class _TaskScheduleSheet extends ConsumerStatefulWidget {
  const _TaskScheduleSheet({required this.task});

  final PlanTask task;

  @override
  ConsumerState<_TaskScheduleSheet> createState() => _TaskScheduleSheetState();
}

class _TaskScheduleSheetState extends ConsumerState<_TaskScheduleSheet> {
  int? _day;
  int? _position;
  String? _startClock;
  bool _seeded = false;
  bool _busy = false;
  int _request = 0;
  TaskMovePreview? _preview;
  bool _previewLoading = false;

  PlanTask get _task => widget.task;

  KhutatiPalette get _palette => context.palette;

  @override
  void initState() {
    super.initState();
    _day = _task.dayNumber;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PlanBrowserData?> plan = ref.watch(planBrowserProvider);
    final PlanBrowserData? data = plan.valueOrNull;

    if (!_seeded && data != null) {
      _seeded = true;
      _startClock ??= data.manualStartClocks[_task.id];
      _position ??= _currentPosition(data);
    }

    final List<PlanDayData> weekDays = data == null
        ? const <PlanDayData>[]
        : <PlanDayData>[
            for (final PlanDayData day in data.days)
              if (!day.isRest && _sameWeek(data, day)) day,
          ];

    final int targetDay = _day ?? _task.dayNumber;
    final List<PlanTask> targetTasks = data == null
        ? const <PlanTask>[]
        : (data.days.length >= targetDay
              ? data.days[targetDay - 1].tasks
              : const <PlanTask>[]);
    final int slotCount =
        targetTasks.where((PlanTask task) => task.id != _task.id).length + 1;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      decoration: BoxDecoration(
        color: _palette.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: _palette.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: _palette.line,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.l10n.msTitle,
                        style: TextStyle(
                          fontFamily: KTypography.displayFamily,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: _palette.tx,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KTypography.bodyFamily,
                          fontSize: KTypography.smallSize,
                          color: _palette.mute,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.msClose,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: _palette.mute),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _label(context.l10n.msDayLabel),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final PlanDayData day in weekDays)
                        _Choice(
                          label: context.l10n.msDayOption(day.day.dayNumber),
                          selected: targetDay == day.day.dayNumber,
                          onTap: () => _selectDay(day.day.dayNumber),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _label(context.l10n.msOrderLabel),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (int slot = 1; slot <= slotCount; slot++)
                        _Choice(
                          label: '$slot',
                          selected: (_position ?? slotCount) == slot,
                          onTap: () => _selectPosition(slot),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _label(context.l10n.msStartLabel),
                  const SizedBox(height: 8),
                  _TimeRow(
                    clock: _displayClock(data),
                    auto: _startClock == null,
                    onEarlier: () => _shiftClock(-15),
                    onLater: () => _shiftClock(15),
                    onAuto: _useAutomaticTime,
                  ),
                  const SizedBox(height: 16),
                  _PreviewBox(
                    preview: _preview,
                    loading: _previewLoading,
                    palette: _palette,
                  ),
                  if (_manual) ...<Widget>[
                    const SizedBox(height: 12),
                    KButton(
                      label: context.l10n.msRestoreAuto,
                      variant: KButtonVariant.secondary,
                      expand: true,
                      icon: Icons.settings_backup_restore_rounded,
                      onPressed: _busy ? null : _restoreAutomatic,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _palette.line)),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              10,
              20,
              10 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: KButton(
                    label: context.l10n.msCancel,
                    variant: KButtonVariant.secondary,
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: KButton(
                    label: context.l10n.msSave,
                    loading: _busy,
                    onPressed: _canSave ? _save : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _manual {
    final PlanBrowserData? data = ref.read(planBrowserProvider).valueOrNull;
    return data?.manualTaskIds.contains(_task.id) ?? false;
  }

  bool get _canSave => !_busy && _preview?.ok == true;

  bool _sameWeek(PlanBrowserData data, PlanDayData day) {
    final int currentWeek = data.calendar.weekOfDay(_task.dayNumber);
    return day.day.week == currentWeek;
  }

  int _currentPosition(PlanBrowserData data) {
    final List<PlanTask> tasks = data.days.length >= _task.dayNumber
        ? data.days[_task.dayNumber - 1].tasks
        : const <PlanTask>[];
    final int index = tasks.indexWhere((PlanTask item) => item.id == _task.id);
    return index < 0 ? tasks.length + 1 : index + 1;
  }

  String? _displayClock(PlanBrowserData? data) {
    if (_startClock != null) return _startClock;
    final PlanDayData? day = data != null && data.days.length >= (_day ?? 0)
        ? data.days[(_day ?? 1) - 1]
        : null;
    if (day != null) {
      for (final PlanTask task in day.tasks) {
        if (task.id == _task.id) return task.suggestedStart;
      }
    }
    return _task.suggestedStart;
  }

  void _selectDay(int day) {
    if (_day == day) return;
    ref.read(hapticsProvider).selection();
    SoundEffects.toggle();
    setState(() {
      _day = day;
      _position = null;
    });
    _refresh();
  }

  void _selectPosition(int position) {
    if (_position == position) return;
    ref.read(hapticsProvider).selection();
    setState(() => _position = position);
    _refresh();
  }

  void _shiftClock(int minutes) {
    final String? base = _displayClock(
      ref.read(planBrowserProvider).valueOrNull,
    );
    final int? current = _minutes(base);
    if (current == null) return;
    final int next = (current + minutes).clamp(6 * 60, 23 * 60);
    ref.read(hapticsProvider).selection();
    setState(() => _startClock = _clock(next));
    _refresh();
  }

  void _useAutomaticTime() {
    if (_startClock == null) return;
    ref.read(hapticsProvider).selection();
    setState(() => _startClock = null);
    _refresh();
  }

  Future<void> _refresh() async {
    final int request = ++_request;
    setState(() => _previewLoading = true);
    try {
      final TaskMovePreview preview = await ref
          .read(taskScheduleActionsProvider)
          .preview(
            taskId: _task.id,
            dayNumber: _day,
            position: _position,
            startClock: _startClock,
          );
      if (!mounted || request != _request) return;
      setState(() {
        _preview = preview;
        _previewLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _preview = const TaskMovePreview(issue: TaskMoveIssue.unavailable);
        _previewLoading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final TaskMovePreview result = await ref
          .read(taskScheduleActionsProvider)
          .commit(
            taskId: _task.id,
            dayNumber: _day,
            position: _position,
            startClock: _startClock,
          );
      if (!mounted) return;
      if (!result.ok) {
        setState(() {
          _preview = result;
          _busy = false;
        });
        return;
      }
      showKToast(context, context.l10n.msSaved);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showKToast(context, context.l10n.msSaveFailed, kind: KToastKind.error);
    }
  }

  Future<void> _restoreAutomatic() async {
    setState(() => _busy = true);
    try {
      await ref.read(taskScheduleActionsProvider).clear(_task.id);
      if (!mounted) return;
      showKToast(context, context.l10n.msRestored);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showKToast(context, context.l10n.msSaveFailed, kind: KToastKind.error);
    }
  }

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: KTypography.bodyFamily,
        fontSize: KTypography.smallSize,
        fontWeight: FontWeight.w600,
        color: _palette.mute,
      ),
    );
  }

  static int? _minutes(String? clock) {
    if (clock == null) return null;
    final List<String> parts = clock.split(':');
    if (parts.length != 2) return null;
    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  static String _clock(int minutes) {
    final int hour = minutes ~/ 60;
    final int minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: PressScale(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: KMotion.navMs),
              constraints: const BoxConstraints(minWidth: 52, minHeight: 42),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? palette.tx : palette.card2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? palette.tx : palette.line),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.smallSize,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? palette.bg : palette.tx,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.clock,
    required this.auto,
    required this.onEarlier,
    required this.onLater,
    required this.onAuto,
  });

  final String? clock;
  final bool auto;
  final VoidCallback onEarlier;
  final VoidCallback onLater;
  final VoidCallback onAuto;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final AppLocalizations l10n = context.l10n;
    return Row(
      children: <Widget>[
        _StepButton(
          icon: Icons.remove_rounded,
          tooltip: l10n.msEarlier15,
          onTap: onEarlier,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: KMetrics.tapTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.card2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.line),
            ),
            child: Text(
              clock == null ? '—' : KhutatiFormat.westernDigits(clock!),
              style: TextStyle(
                fontFamily: KTypography.displayFamily,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: palette.tx,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _StepButton(
          icon: Icons.add_rounded,
          tooltip: l10n.msLater15,
          onTap: onLater,
        ),
        const SizedBox(width: 10),
        _Choice(label: l10n.msAuto, selected: auto, onTap: onAuto),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: PressScale(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.card2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.line),
                ),
                child: Icon(icon, size: 20, color: palette.tx),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({
    required this.preview,
    required this.loading,
    required this.palette,
  });

  final TaskMovePreview? preview;
  final bool loading;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TaskMovePreview? value = preview;
    final bool ok = value?.ok == true;
    final Color tint = value == null
        ? palette.mute
        : ok
        ? palette.ok
        : palette.red;

    final String text;
    if (loading || value == null) {
      text = l10n.msCalculating;
    } else if (ok) {
      final ScheduledTask task = value.task!;
      final String affected = value.affected.length <= 1
          ? ''
          : l10n.msAffected(value.affected.length - 1);
      text =
          '${l10n.msPreviewLine(task.dayNumber, task.startClock ?? '', task.endClock ?? '', task.order)}'
          '$affected';
    } else {
      text = _issueText(l10n, value);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            loading
                ? Icons.hourglass_empty_rounded
                : ok
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            size: 18,
            color: tint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.smallSize,
                height: 1.6,
                color: palette.tx,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _issueText(AppLocalizations l10n, TaskMovePreview value) {
    final String blocker = value.blocking?.task.title ?? '';
    return switch (value.issue) {
      TaskMoveIssue.restDay => l10n.msRestDay,
      TaskMoveIssue.dependencyBefore => l10n.msDependencyBefore(blocker),
      TaskMoveIssue.dependencyAfter => l10n.msDependencyAfter(blocker),
      TaskMoveIssue.overlap => l10n.msOverlap(
        blocker,
        value.blocking?.startClock ?? '',
      ),
      TaskMoveIssue.pastMidnight => l10n.msPastMidnight,
      TaskMoveIssue.invalidTime => l10n.msInvalidTime,
      TaskMoveIssue.unknownTask => l10n.msUnknownTask,
      _ => l10n.msGenericIssue,
    };
  }
}
