import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/sound/sound_effects.dart';
import '../../../core/utils/format.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../domain/plan/practical_weekdays.dart';
import '../../../l10n/l10n.dart';
import '../../plan/application/plan_browser_controller.dart';
import '../../plan/application/task_schedule_controller.dart';
import '../application/practical_days_controller.dart';

/// Dedicated practical-day configuration.
///
/// Settings only carries a compact navigation row; the weekday selector, the
/// one-to-three rule and the before/after preview live here, where they have
/// room to breathe.
class PracticalDaysScreen extends ConsumerStatefulWidget {
  const PracticalDaysScreen({super.key});

  @override
  ConsumerState<PracticalDaysScreen> createState() =>
      _PracticalDaysScreenState();
}

class _PracticalDaysScreenState extends ConsumerState<PracticalDaysScreen> {
  /// Arabic weeks start on Saturday, which is also how the plan prints them.
  static const List<int> _weekOrder = <int>[
    DateTime.saturday,
    DateTime.sunday,
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  ];

  Set<int>? _selection;
  bool _busy = false;

  KhutatiPalette get _palette => context.palette;

  int get _manualCount =>
      ref.watch(planBrowserProvider).valueOrNull?.manualTaskIds.length ?? 0;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PracticalDaysSettings> settings = ref.watch(
      practicalDaysSettingsProvider,
    );

    return Scaffold(
      backgroundColor: _palette.bg,
      appBar: AppBar(
        backgroundColor: _palette.bg,
        surfaceTintColor: Colors.transparent,
        leading: const BackButton(),
        titleSpacing: 0,
        title: Text(
          context.l10n.settingsPracticalDays,
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _palette.tx,
          ),
        ),
      ),
      body: settings.when(
        data: (PracticalDaysSettings value) {
          _selection ??= value.selected.toSet();
          return _body(value);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.l10n.pdLoadError,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.muteSize,
                color: _palette.mute,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(PracticalDaysSettings value) {
    final AppLocalizations l10n = context.l10n;
    final Set<int> selected = _selection!;
    final List<int> ordered = _ordered(selected);
    final bool dirty = !_sameDays(ordered, value.selected);
    final bool canSave =
        ordered.isNotEmpty &&
        ordered.length <= PracticalWeekdays.maxDays &&
        dirty;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              KMetrics.appPaddingX,
              4,
              KMetrics.appPaddingX,
              24,
            ),
            children: <Widget>[
              Text(
                l10n.pdIntro,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.muteSize,
                  height: 1.7,
                  color: _palette.mute,
                ),
              ),
              const SizedBox(height: 16),
              _CurrentCard(
                days: _label(value.selected),
                isCustom: value.isCustom,
              ),
              const SizedBox(height: 20),
              Text(
                l10n.pdPickDays,
                style: TextStyle(
                  fontFamily: KTypography.displayFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _palette.tx,
                ),
              ),
              const SizedBox(height: 10),
              _DayGrid(
                weekOrder: _weekOrder,
                selected: selected,
                onToggle: _toggle,
                nameOf: _name,
                selectedLabel: l10n.pdSelectedLabel,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      ordered.isEmpty ? l10n.pdMinHint : _label(ordered),
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.smallSize,
                        fontWeight: FontWeight.w500,
                        color: _palette.tx,
                      ),
                    ),
                  ),
                ],
              ),
              if (selected.length >= PracticalWeekdays.maxDays)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l10n.pdMaxHint,
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: KTypography.tagSize,
                      color: _palette.gold,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              const _Explainer(),
              if (value.isCustom || dirty) ...<Widget>[
                const SizedBox(height: 20),
                KButton(
                  label: l10n.settingsPracticalDaysReset,
                  variant: KButtonVariant.secondary,
                  expand: true,
                  icon: Icons.restart_alt_rounded,
                  onPressed: _busy ? null : _reset,
                ),
              ],
              if (_manualCount > 0) ...<Widget>[
                const SizedBox(height: 10),
                KButton(
                  label: l10n.pdClearManual(_manualCount),
                  variant: KButtonVariant.secondary,
                  expand: true,
                  icon: Icons.settings_backup_restore_rounded,
                  onPressed: _busy ? null : _clearManual,
                ),
              ],
            ],
          ),
        ),
        _BottomBar(
          enabled: canSave && !_busy,
          busy: _busy,
          label: dirty ? l10n.pdSave : l10n.pdNoChange,
          onPressed: _preview,
        ),
      ],
    );
  }

  void _toggle(int weekday) {
    final Set<int> selected = _selection!;
    if (selected.contains(weekday)) {
      ref.read(hapticsProvider).selection();
      SoundEffects.toggle();
      setState(() => selected.remove(weekday));
      return;
    }
    if (selected.length >= PracticalWeekdays.maxDays) {
      showKToast(context, context.l10n.pdMaxToast, kind: KToastKind.error);
      return;
    }
    ref.read(hapticsProvider).selection();
    SoundEffects.toggle();
    setState(() => selected.add(weekday));
  }

  Future<void> _preview() async {
    final AppLocalizations l10n = context.l10n;
    final List<int> selected = _ordered(_selection!);
    if (selected.isEmpty) {
      showKToast(context, l10n.pdMinToast, kind: KToastKind.error);
      return;
    }
    if (selected.length > PracticalWeekdays.maxDays) {
      showKToast(context, l10n.pdMaxToast, kind: KToastKind.error);
      return;
    }

    setState(() => _busy = true);
    try {
      final SchedulePreview preview = await ref
          .read(practicalDaysActionsProvider)
          .preview(selected);
      if (!mounted) return;
      setState(() => _busy = false);

      final bool? confirmed = await showKDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => KDialog(
          eyebrow: l10n.pdPreviewEyebrow,
          title: l10n.settingsPracticalDaysPreviewTitle,
          icon: Icons.calendar_month_rounded,
          child: _PreviewBody(preview: preview),
          actions: <KDialogAction>[
            KDialogAction(
              label: l10n.pdConfirmSave,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
          secondaryActions: <KDialogAction>[
            KDialogAction(
              label: l10n.settingsPracticalDaysCancel,
              variant: KButtonVariant.secondary,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ],
          onClose: () => Navigator.of(ctx).pop(false),
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() => _busy = true);
      await ref.read(practicalDaysActionsProvider).save(selected);
      if (!mounted) return;
      // Toast first: it lives in the Navigator's overlay, so it stays visible
      // over Settings after the pop. Returning to Settings is the completion
      // signal — the screen has nothing left to do.
      showKToast(context, l10n.settingsPracticalDaysSaved);
      context.pop();
    } catch (_) {
      if (!mounted) return;
      showKToast(
        context,
        l10n.settingsPracticalDaysFailed,
        kind: KToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearManual() async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showKDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => KDialog(
        eyebrow: l10n.settingsPlanSection,
        title: l10n.pdClearManualTitle,
        message: l10n.pdClearManualMessage,
        icon: Icons.settings_backup_restore_rounded,
        accent: context.palette.gold,
        actions: <KDialogAction>[
          KDialogAction(
            label: l10n.pdClearManualConfirm,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        secondaryActions: <KDialogAction>[
          KDialogAction(
            label: l10n.pdBack,
            variant: KButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
        onClose: () => Navigator.of(ctx).pop(false),
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(taskScheduleActionsProvider).clearAll();
      if (!mounted) return;
      showKToast(context, l10n.pdClearManualDone);
    } catch (_) {
      if (!mounted) return;
      showKToast(
        context,
        l10n.settingsPracticalDaysFailed,
        kind: KToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showKDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => KDialog(
        eyebrow: l10n.settingsPlanSection,
        title: l10n.settingsPracticalDaysResetTitle,
        message: l10n.settingsPracticalDaysResetMessage,
        icon: Icons.restart_alt_rounded,
        accent: context.palette.gold,
        actions: <KDialogAction>[
          KDialogAction(
            label: l10n.settingsPracticalDaysResetConfirm,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        secondaryActions: <KDialogAction>[
          KDialogAction(
            label: l10n.settingsPracticalDaysCancel,
            variant: KButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
        onClose: () => Navigator.of(ctx).pop(false),
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(practicalDaysActionsProvider).reset();
      if (!mounted) return;
      setState(() => _selection = PracticalWeekdays.original.toSet());
      showKToast(context, l10n.settingsPracticalDaysResetDone);
    } catch (_) {
      if (!mounted) return;
      showKToast(
        context,
        l10n.settingsPracticalDaysFailed,
        kind: KToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static List<int> _ordered(Iterable<int> days) {
    final Set<int> set = days.toSet();
    return <int>[
      for (final int weekday in _weekOrder)
        if (set.contains(weekday)) weekday,
    ];
  }

  static bool _sameDays(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _name(int weekday) {
    final DateTime date = DateTime(2026, 11, 16 + weekday - 1);
    return KhutatiFormat.westernDigits(DateFormat('EEEE', 'ar').format(date));
  }

  static String _label(Iterable<int> days) {
    final List<int> ordered = _ordered(days);
    if (ordered.isEmpty) return '—';
    return ordered.map(_name).join(' و');
  }
}

class _CurrentCard extends StatelessWidget {
  const _CurrentCard({required this.days, required this.isCustom});

  final String days;
  final bool isCustom;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final Color tint = isCustom ? palette.gold : palette.ok;

    return KCard(
      showPattern: false,
      padding: const EdgeInsets.symmetric(
        horizontal: KMetrics.statPaddingX,
        vertical: KMetrics.statPaddingY,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.l10n.pdCurrent,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.tagSize,
                    color: palette.mute,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  days,
                  style: TextStyle(
                    fontFamily: KTypography.displayFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: palette.tx,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(KMetrics.pillRadius),
              border: Border.all(color: tint.withValues(alpha: 0.4)),
            ),
            child: Text(
              isCustom
                  ? context.l10n.settingsPracticalDaysCustom
                  : context.l10n.settingsPracticalDaysOriginal,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.tagSize,
                fontWeight: FontWeight.w600,
                color: tint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two columns: one card per weekday plus a counter tile, so the selector is
/// scannable at a glance instead of a seven-row list.
class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.weekOrder,
    required this.selected,
    required this.onToggle,
    required this.nameOf,
    required this.selectedLabel,
  });

  final List<int> weekOrder;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final String Function(int) nameOf;
  final String selectedLabel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool full = selected.length >= PracticalWeekdays.maxDays;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      mainAxisSpacing: KMetrics.gridGap,
      crossAxisSpacing: KMetrics.gridGap,
      childAspectRatio: 2.2,
      children: <Widget>[
        for (final int weekday in weekOrder)
          _DayCard(
            label: nameOf(weekday),
            selected: selected.contains(weekday),
            disabled: !selected.contains(weekday) && full,
            selectedLabel: selectedLabel,
            availableLabel: l10n.pdDayAvailable,
            onTap: () => onToggle(weekday),
          ),
        _CountCard(count: selected.length, full: full, label: selectedLabel),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.label,
    required this.selected,
    required this.disabled,
    required this.selectedLabel,
    required this.availableLabel,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool disabled;
  final String selectedLabel;
  final String availableLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final Color tint = selected ? palette.gold : palette.mute;

    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: '$label، ${selected ? selectedLabel : availableLabel}',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: KMotion.navMs),
        opacity: disabled ? 0.42 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: KMotion.navMs),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? palette.gold.withValues(alpha: 0.14)
                : palette.card2,
            borderRadius: BorderRadius.circular(KMetrics.cardRadius),
            border: Border.all(
              color: selected ? palette.gold : palette.line,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: KInkSurface(
            onTap: disabled ? null : onTap,
            borderRadius: BorderRadius.circular(KMetrics.cardRadius),
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 10, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KTypography.displayFamily,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: palette.tx,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selected ? selectedLabel : availableLabel,
                        style: TextStyle(
                          fontFamily: KTypography.bodyFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tint,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedScale(
                  duration: const Duration(milliseconds: KMotion.navMs),
                  curve: Curves.easeOutBack,
                  scale: selected ? 1 : 0.6,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: KMotion.navMs),
                    opacity: selected ? 1 : 0,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: palette.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.count,
    required this.full,
    required this.label,
  });

  final int count;
  final bool full;
  final String label;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final Color tint = full ? palette.gold : palette.mute;
    return Semantics(
      label: '$count / ${PracticalWeekdays.maxDays} $label',
      child: Container(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(KMetrics.cardRadius),
          border: Border.all(color: tint.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$count / ${PracticalWeekdays.maxDays}',
              style: TextStyle(
                fontFamily: KTypography.displayFamily,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: tint,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: palette.mute,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.auto_awesome_rounded, size: 18, color: palette.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.pdExplainer,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.smallSize,
                height: 1.65,
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
    required this.enabled,
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final bool busy;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border(top: BorderSide(color: palette.line)),
      ),
      padding: EdgeInsets.fromLTRB(
        KMetrics.appPaddingX,
        12,
        KMetrics.appPaddingX,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: KButton(
        label: label,
        expand: true,
        loading: busy,
        onPressed: enabled ? onPressed : null,
      ),
    );
  }
}

/// Shows what actually happens, day by day: how many tasks arrive, how many
/// leave, and how the finish line moves. A before/after table made the user do
/// the arithmetic; this states the result.
class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.preview});

  final SchedulePreview preview;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final AppLocalizations l10n = context.l10n;
    final KhutatiFormat format = KhutatiFormat(l10n);
    final List<DayLoadChange> changes = preview.loadChanges;
    final int finishDelta = preview.finishDayDelta;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.pdPreviewDays(_days(preview.nextWeekdays)),
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: KTypography.smallSize,
            height: 1.6,
            color: palette.tx,
          ),
        ),
        const SizedBox(height: 12),
        _HeadlineRow(
          icon: Icons.event_repeat_rounded,
          text: l10n.pdImpactDaysChanged(changes.length),
          palette: palette,
          tint: palette.tx,
        ),
        const SizedBox(height: 6),
        _HeadlineRow(
          icon: finishDelta > 0
              ? Icons.schedule_rounded
              : finishDelta < 0
              ? Icons.fast_forward_rounded
              : Icons.flag_rounded,
          text: finishDelta == 0
              ? l10n.pdImpactFinishSame
              : finishDelta > 0
              ? l10n.pdImpactFinishLater(finishDelta)
              : l10n.pdImpactFinishEarlier(-finishDelta),
          palette: palette,
          tint: finishDelta == 0 ? palette.mute : palette.gold,
        ),
        if (changes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: palette.card2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.line),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              children: <Widget>[
                for (final DayLoadChange change in changes.take(8))
                  _ImpactRow(change: change, palette: palette, format: format),
                if (changes.length > 8)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.pdImpactMoreDays(changes.length - 8),
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.tagSize,
                        color: palette.mute,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (preview.droppedOverrides.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              l10n.pdPreviewDropped(preview.droppedOverrides.length),
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.smallSize,
                height: 1.6,
                color: palette.gold,
              ),
            ),
          ),
      ],
    );
  }

  static String _days(List<int> weekdays) {
    return weekdays
        .map((int weekday) {
          final DateTime date = DateTime(2026, 11, 16 + weekday - 1);
          return KhutatiFormat.westernDigits(
            DateFormat('EEEE', 'ar').format(date),
          );
        })
        .join(' و');
  }
}

class _HeadlineRow extends StatelessWidget {
  const _HeadlineRow({
    required this.icon,
    required this.text,
    required this.palette,
    required this.tint,
  });

  final IconData icon;
  final String text;
  final KhutatiPalette palette;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 17, color: tint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.smallSize,
              fontWeight: FontWeight.w600,
              color: tint,
            ),
          ),
        ),
      ],
    );
  }
}

class _ImpactRow extends StatelessWidget {
  const _ImpactRow({
    required this.change,
    required this.palette,
    required this.format,
  });

  final DayLoadChange change;
  final KhutatiPalette palette;
  final KhutatiFormat format;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final int tasks = change.deltaTasks;
    final int minutes = change.deltaMinutes;

    final Color tint = tasks > 0
        ? palette.ok
        : tasks < 0
        ? palette.redtx
        : palette.mute;
    final IconData icon = tasks > 0
        ? Icons.add_circle_rounded
        : tasks < 0
        ? Icons.remove_circle_rounded
        : Icons.swap_horiz_rounded;
    final String label = tasks > 0
        ? l10n.pdImpactAdded(tasks)
        : tasks < 0
        ? l10n.pdImpactRemoved(-tasks)
        : l10n.pdImpactTimeOnly;
    final String time = minutes == 0
        ? ''
        : '${minutes > 0 ? '+' : '−'}${format.duration(minutes.abs())}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: 8),
          Text(
            l10n.pdImpactDay(change.dayNumber),
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.smallSize,
              fontWeight: FontWeight.w600,
              color: palette.tx,
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.smallSize,
                  fontWeight: FontWeight.w700,
                  color: tint,
                ),
              ),
              if (time.isNotEmpty)
                Text(
                  time,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.tagSize,
                    color: palette.mute,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
