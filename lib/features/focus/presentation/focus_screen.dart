import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/feedback.dart';
import '../../../core/design/widgets/surfaces.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/utils/format.dart';
import '../../../l10n/l10n.dart';
import '../application/focus_controller.dart';
import '../../../data/database/app_database.dart';
import '../application/focus_setup_controller.dart';
import '../../today/application/today_controller.dart';
import '../../../domain/plan/plan_task.dart';
import '../../../domain/plan/plan_step.dart';
import '../domain/focus_setup.dart';

/// Colours used by the dashed ring, mirroring the HTML reference's CSS vars.
const Color _trackColor = Color(0xFF26395A);
const Color _gold = Color(0xFFE8B65A);
const Color _ok = Color(0xFF7CCBB0);
const Color _red = Color(0xFFB52A20);

class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key});

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen>
    with WidgetsBindingObserver {
  bool _immersive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(focusControllerProvider.notifier).consumePendingAction();
      _applySystemUi();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final FocusController controller =
          ref.read(focusControllerProvider.notifier);
      controller.consumePendingAction();
      controller.syncWithNative();
    }
  }

  void _applySystemUi() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  void _setImmersive(bool value) {
    if (_immersive == value) return;
    setState(() => _immersive = value);
    ref.read(focusImmersiveProvider.notifier).state = value;
    SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    _applySystemUi();
    ref.read(hapticsProvider).selection();
  }

  @override
  Widget build(BuildContext context) {
    final FocusSessionState session = ref.watch(focusControllerProvider);
    final KhutatiPalette palette = context.palette;

    // Toasts for phase transitions and pause, mirroring the HTML's status line.
    ref.listen<FocusSessionState>(focusControllerProvider, (
      FocusSessionState? previous,
      FocusSessionState next,
    ) {
      if (previous == null) return;
      final AppLocalizations l10n = context.l10n;
      if (previous.isRunning && next.isPaused) {
        showKToast(context, l10n.focusPause, kind: KToastKind.info);
      }
      if (previous.phase != next.phase && next.isRunning) {
        if (next.isBreak) {
          showKToast(
            context,
            next.rounds >= 3 ? 'استراحة طويلة، أحسنت' : 'وقت الاستراحة',
            kind: KToastKind.info,
          );
        } else {
          showKToast(context, 'جلسة تركيز جديدة', kind: KToastKind.info);
        }
      }
      if (previous.isRunning && next.isFinished && next.reason == FocusEndReason.completed) {
        if (next.mode == FocusMode.linked) {
          showKToast(context, 'انتهى الوقت', kind: KToastKind.info);
        }
      }
    });

    // Auto-load the next task/step when the user opens the Focus tab directly
    // in Task mode without a draft (mirrors the HTML's example task).
    ref.listen<AsyncValue<TodayData?>>(todayDataProvider, (
      AsyncValue<TodayData?>? previous,
      AsyncValue<TodayData?> next,
    ) {
      if (!session.isIdle) return;
      final FocusSetup setup = ref.read(focusSetupProvider);
      if (setup.mode != FocusMode.linked) return;
      if (ref.read(focusDraftProvider) != null) return;
      final TodayData? data = next.valueOrNull;
      if (data == null) return;
      final PlanTask? task = data.nextTask;
      if (task == null) return;
      final List<PlanStep> steps = task.stepsInOrder;
      final PlanStep? step = task.nextStep;
      final int currentIndex = step == null
          ? 0
          : steps.indexWhere((PlanStep s) => s.id == step.id);
      final AppLocalizations l10n = context.l10n;
      final FocusTaskDraft draft = FocusTaskDraft(
        taskId: task.id,
        taskTitle: task.title,
        subjectName: task.subjectName ?? data.subjectNames[task.subjectKey],
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
    });

    if (session.isFinished) {
      return _FinishedView(
        session: session,
        onDismiss: () {
          ref.read(focusControllerProvider.notifier).dismissFinished();
        },
      );
    }

    return PopScope(
      canPop: !_immersive,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_immersive) _setImmersive(false);
      },
      child: Scaffold(
        backgroundColor: palette.bg,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _AmbientBackdrop(palette: palette),
            SafeArea(
              bottom: false,
              child: OrientationBuilder(
                builder: (BuildContext context, Orientation orientation) {
                  return _FocusView(
                    session: session,
                    immersive: _immersive,
                    onToggleImmersive: () => _setImmersive(!_immersive),
                    landscape: orientation == Orientation.landscape,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusView extends ConsumerWidget {
  const _FocusView({
    required this.session,
    required this.immersive,
    required this.onToggleImmersive,
    required this.landscape,
  });

  final FocusSessionState session;
  final bool immersive;
  final VoidCallback onToggleImmersive;
  final bool landscape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final KhutatiHaptics haptics = ref.read(hapticsProvider);
    final FocusController controller = ref.read(focusControllerProvider.notifier);
    final FocusSetup setup = ref.watch(focusSetupProvider);
    final FocusSetupController setupController = ref.read(focusSetupProvider.notifier);
    final FocusTaskDraft? draft = ref.watch(focusDraftProvider);

    // When idle, the displayed mode comes from the setup (segmented control),
    // not from the session (which defaults to pomodoro). This is what makes
    // switching between Task / Pomodoro / Free actually update the UI.
    final FocusMode effectiveMode =
        session.isIdle ? setup.mode : session.mode;
    final bool isFree = effectiveMode == FocusMode.free;
    final bool isTask = effectiveMode == FocusMode.linked;
    final bool isPomo = effectiveMode == FocusMode.pomodoro;
    final bool isBreak = session.isBreak && !session.isIdle;
    final bool running = session.isRunning;
    final bool paused = session.isPaused;
    final Color phaseColor = isBreak
        ? _ok
        : isTask
        ? (draft != null ? _subjectColor(draft) : const Color(0xFF6AA6FF))
        : isPomo
        ? _gold
        : palette.tx;

    final bool isLastTaskStep = isTask && session.nextStep == null;
    final bool hideSkip = isFree || isLastTaskStep;

    // Idle preview duration, so the timer shows the total (e.g. 25:00) before
    // Play instead of 00:00. Free counts up from zero, so it stays 00:00.
    final int idlePlannedSeconds = isFree
        ? 3600
        : isPomo
        ? setup.focusMinutes * 60
        : (draft?.minutes ?? 25) * 60;
    final int displayPlannedSeconds =
        session.isIdle ? idlePlannedSeconds : session.plannedSeconds;
    final int displayRemainingSeconds = session.isIdle
        ? (isFree ? 0 : idlePlannedSeconds)
        : session.remainingSeconds;

    final int segments = isFree
        ? 60
        : (displayPlannedSeconds / 60).ceil().clamp(1, 360);

    final String timeText = _clock(displayRemainingSeconds, free: isFree);

    final String goLabel = running
        ? l10n.focusPause
        : paused
        ? l10n.focusResume
        : l10n.focusStartFocusNow;
    final String skipLabel = isTask
        ? l10n.focusSkip
        : isBreak
        ? l10n.focusSkipBreak
        : l10n.focusStartBreak;

    void startSession() {
      haptics.selection();
      if (isTask) {
        if (draft == null || draft.steps.isEmpty) {
          showKToast(context, l10n.focusNoTaskTitle, kind: KToastKind.info);
          return;
        }
        controller.start(
          mode: FocusMode.linked,
          minutes: draft.minutes > 0 ? draft.minutes : 25,
          draft: draft,
        );
        return;
      }
      if (isPomo) {
        controller.start(
          mode: FocusMode.pomodoro,
          minutes: setup.focusMinutes,
          breakMinutes: setup.breakMinutes,
          autoBreak: setup.autoBreak,
        );
        return;
      }
      controller.start(mode: FocusMode.free, minutes: 0);
    }

    void onGo() {
      if (running) {
        haptics.selection();
        controller.pause();
      } else if (paused) {
        haptics.selection();
        controller.resume();
      } else {
        startSession();
      }
    }

    void onEnd() {
      haptics.medium();
      final int elapsed = isFree
          ? session.remainingSeconds
          : session.plannedSeconds - session.remainingSeconds;
      final int minutes = elapsed ~/ 60;
      if (minutes > 0) {
        showKToast(context, 'حُفظت الجلسة: $minutes دقيقة', kind: KToastKind.success);
      }
      controller.endStep();
    }

    void onSkip() {
      haptics.selection();
      if (isTask) {
        final FocusStepRef? next = session.nextStep;
        if (next != null) {
          showKToast(context, 'انتقلت إلى: ${next.label}', kind: KToastKind.info);
        }
        controller.skipPhase();
      } else if (isPomo) {
        controller.skipPhase();
      }
    }

    // Header: large title + subtitle on the right, history + fullscreen on the left.
    final Widget fsButton = _FsButton(
      immersive: immersive,
      onTap: onToggleImmersive,
    );
    final Widget historyButton = _HistoryButton(
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: palette.card,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (BuildContext ctx) => _FocusHistorySheet(palette: palette),
        );
      },
    );

    final Widget header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'التركيز',
                style: TextStyle(
                  fontFamily: KTypography.displayFamily,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: palette.tx,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'اختر نمط الجلسة ثم ابدأ',
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 14,
                  color: palette.mute,
                ),
              ),
            ],
          ),
        ),
        historyButton,
        const SizedBox(width: 8),
        fsButton,
      ],
    );

    // Segmented control (below the header).
    final Widget segmented = Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: <Widget>[
          _SegButton(
            label: l10n.focusModeLinked,
            selected: isTask,
            onTap: session.isIdle ? () => setupController.setMode(FocusMode.linked) : null,
          ),
          _SegButton(
            label: l10n.focusModePomodoro,
            selected: isPomo,
            onTap: session.isIdle ? () => setupController.setMode(FocusMode.pomodoro) : null,
          ),
          _SegButton(
            label: l10n.focusModeFree,
            selected: isFree,
            onTap: session.isIdle ? () => setupController.setMode(FocusMode.free) : null,
          ),
        ],
      ),
    );

    // Panel
    final Widget panel = _PanelSwitcher(
      mode: effectiveMode,
      draft: draft,
      setup: setup,
      setupController: setupController,
      l10n: l10n,
      palette: palette,
      haptics: haptics,
    );

    final Widget infoTag = Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: phaseColor,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          isTask
              ? (draft != null ? '${draft.subjectName ?? ''} — ${draft.taskTitle}' : 'مهمة')
              : isPomo
              ? 'بومودورو'
              : 'مؤقت حر',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF0D1A2D),
          ),
        ),
      ),
    );

    final Widget ring = _FocusRing(
      fraction: session.progress,
      segments: segments,
      color: phaseColor,
      trackColor: _trackColor,
      time: timeText,
      label: isBreak ? 'استراحة' : 'تركيز',
      sub: _subText(session, draft, l10n, effectiveMode),
      dots: _dots(session, draft, effectiveMode),
      size: immersive
          ? (landscape ? 360.0 : 320.0)
          : (landscape ? 280.0 : 260.0),
    );

    final Widget controls = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ControlColumn(
          label: l10n.focusEnd,
          child: _CircleButton(
            size: 56,
            color: palette.card,
            borderColor: palette.line,
            icon: Icons.stop_rounded,
            iconColor: palette.tx,
            onTap: onEnd,
          ),
        ),
        const SizedBox(width: 28),
        _ControlColumn(
          label: goLabel,
          child: _CircleButton(
            size: 84,
            color: _red,
            borderColor: _red,
            icon: running ? Icons.pause_rounded : Icons.play_arrow_rounded,
            iconColor: Colors.white,
            onTap: onGo,
          ),
        ),
        if (!hideSkip) ...<Widget>[
          const SizedBox(width: 28),
          _ControlColumn(
            label: skipLabel,
            child: _CircleButton(
              size: 56,
              color: palette.card,
              borderColor: palette.line,
              icon: Icons.skip_next_rounded,
              iconColor: palette.tx,
              onTap: onSkip,
            ),
          ),
        ],
      ],
    );

    if (landscape) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(flex: 5, child: Center(child: ring)),
            const SizedBox(width: 48),
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  header,
                  if (!immersive) ...<Widget>[
                    const SizedBox(height: 12),
                    segmented,
                    const SizedBox(height: 16),
                    panel,
                    const SizedBox(height: 16),
                  ] else ...<Widget>[
                    const SizedBox(height: 8),
                    infoTag,
                    const SizedBox(height: 16),
                  ],
                  const Spacer(),
                  controls,
                  SizedBox(height: immersive ? 24 : 40),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          header,
          if (!immersive) ...<Widget>[
            const SizedBox(height: 12),
            segmented,
            const SizedBox(height: 16),
            panel,
            const SizedBox(height: 16),
          ] else ...<Widget>[
            const SizedBox(height: 8),
            infoTag,
            const SizedBox(height: 16),
          ],
          Expanded(child: Center(child: ring)),
          const SizedBox(height: 16),
          controls,
          SizedBox(height: immersive ? 24 : 96),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panels
// ---------------------------------------------------------------------------

class _PanelSwitcher extends StatelessWidget {
  const _PanelSwitcher({
    required this.mode,
    required this.draft,
    required this.setup,
    required this.setupController,
    required this.l10n,
    required this.palette,
    required this.haptics,
  });

  final FocusMode mode;
  final FocusTaskDraft? draft;
  final FocusSetup setup;
  final FocusSetupController setupController;
  final AppLocalizations l10n;
  final KhutatiPalette palette;
  final KhutatiHaptics haptics;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: KeyedSubtree(
        key: ValueKey<FocusMode>(mode),
        child: switch (mode) {
          FocusMode.linked => _TaskPanel(draft: draft, palette: palette),
          FocusMode.pomodoro => _PomodoroPanel(
            setup: setup,
            controller: setupController,
            l10n: l10n,
            palette: palette,
            haptics: haptics,
          ),
          FocusMode.free => _FreePanel(l10n: l10n, palette: palette),
        },
      ),
    );
  }
}

class _TaskPanel extends StatelessWidget {
  const _TaskPanel({required this.draft, required this.palette});

  final FocusTaskDraft? draft;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    final FocusTaskDraft? d = draft;
    if (d == null || d.steps.isEmpty) {
      return _EmptyTaskPanel(palette: palette);
    }
    final FocusStepRef? step = d.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF6AA6FF),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            d.subjectName ?? 'الكيمياء الطبية',
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF0D1A2D),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          d.taskTitle,
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: palette.tx,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          step == null ? '' : '${step.label} · ${step.minutes} دقيقة',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 14,
            color: palette.mute,
          ),
        ),
      ],
    );
  }
}

class _EmptyTaskPanel extends StatelessWidget {
  const _EmptyTaskPanel({required this.palette});

  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.focusNoTaskTitle,
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: palette.tx,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.focusNoTaskBody,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 13,
            color: palette.mute,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => context.go('/today'),
          child: Text(
            l10n.focusGoToday,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.gold,
            ),
          ),
        ),
      ],
    );
  }
}

class _PomodoroPanel extends StatelessWidget {
  const _PomodoroPanel({
    required this.setup,
    required this.controller,
    required this.l10n,
    required this.palette,
    required this.haptics,
  });

  final FocusSetup setup;
  final FocusSetupController controller;
  final AppLocalizations l10n;
  final KhutatiPalette palette;
  final KhutatiHaptics haptics;

  @override
  Widget build(BuildContext context) {
    final bool custom = setup.preset == PomodoroPreset.custom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'جلسة بومودورو',
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: palette.tx,
          ),
        ),
        Text(
          'غير مرتبطة بأي مهمة.',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 14,
            color: palette.mute,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _PresetChip(
              label: '25 / 5',
              selected: setup.preset == PomodoroPreset.classic,
              onTap: () {
                haptics.selection();
                controller.setPreset(PomodoroPreset.classic);
              },
            ),
            _PresetChip(
              label: '50 / 10',
              selected: setup.preset == PomodoroPreset.deep,
              onTap: () {
                haptics.selection();
                controller.setPreset(PomodoroPreset.deep);
              },
            ),
            _PresetChip(
              label: '90 / 20',
              selected: setup.preset == PomodoroPreset.long,
              onTap: () {
                haptics.selection();
                controller.setPreset(PomodoroPreset.long);
              },
            ),
            _PresetChip(
              label: 'مخصص',
              selected: custom,
              onTap: () {
                haptics.selection();
                controller.setPreset(PomodoroPreset.custom);
              },
            ),
          ],
        ),
        if (custom) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _NumberField(
                  label: 'التركيز (دقيقة)',
                  value: setup.focusMinutes,
                  min: FocusSetup.minMinutes,
                  max: FocusSetup.maxMinutes,
                  onChanged: controller.setFocusMinutes,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  label: 'الاستراحة (دقيقة)',
                  value: setup.breakMinutes,
                  min: 1,
                  max: 60,
                  onChanged: controller.setBreakMinutes,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FreePanel extends StatelessWidget {
  const _FreePanel({required this.l10n, required this.palette});

  final AppLocalizations l10n;
  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'مؤقت حر',
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: palette.tx,
          ),
        ),
        Text(
          'يعدّ تصاعدياً حتى توقفه. الحلقة تدور كل ساعة، وكل شريحة دقيقة.',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 14,
            color: palette.mute,
          ),
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? palette.card2 : palette.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _gold : palette.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            color: selected ? _gold : palette.tx,
          ),
        ),
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value.toString(),
  );

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        int.tryParse(_controller.text) != widget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.label,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 13,
            color: palette.mute,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          onChanged: (String v) {
            final int? n = int.tryParse(v);
            if (n == null) return;
            final int clamped = n.clamp(widget.min, widget.max);
            widget.onChanged(clamped);
          },
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 14,
            color: palette.tx,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: palette.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _gold),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ring
// ---------------------------------------------------------------------------

class _FocusRing extends StatelessWidget {
  const _FocusRing({
    required this.fraction,
    required this.segments,
    required this.color,
    required this.trackColor,
    required this.time,
    required this.label,
    required this.sub,
    required this.dots,
    required this.size,
  });

  final double fraction;
  final int segments;
  final Color color;
  final Color trackColor;
  final String time;
  final String label;
  final String sub;
  final List<Widget> dots;
  final double size;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: Size.square(size),
            painter: _FocusRingPainter(
              fraction: fraction,
              segments: segments,
              color: color,
              trackColor: trackColor,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 14,
                  color: palette.mute,
                ),
              ),
              Text(
                time,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontFamily: KTypography.displayFamily,
                  fontSize: size * 0.225,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                  color: palette.tx,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              if (sub.isNotEmpty)
                Text(
                  sub,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 13,
                    color: palette.mute,
                  ),
                ),
              if (dots.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: dots),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({
    required this.fraction,
    required this.segments,
    required this.color,
    required this.trackColor,
  });

  final double fraction;
  final int segments;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / 320.0;
    final double r = 130.0 * scale;
    final double stroke = 16.0 * scale;
    final Offset center = size.center(Offset.zero);
    final Rect rect = Rect.fromCircle(center: center, radius: r);

    final int n = segments.clamp(1, 360);
    final double stepAngle = (math.pi * 2) / n;
    final double circumference = 2 * math.pi * r;
    final double arcPerSeg = circumference / n;
    final double dashPx = math.min(5.0, arcPerSeg * 0.5);
    final double dashAngle = dashPx / r;

    final double limit = fraction.clamp(0.0, 1.0) * (math.pi * 2);
    const double startAngle = -math.pi / 2;

    // Track: all dashes in track colour.
    final Paint trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..color = trackColor;
    for (int i = 0; i < n; i++) {
      final double a0 = startAngle + i * stepAngle;
      canvas.drawArc(rect, a0, dashAngle, false, trackPaint);
    }

    // Glow behind the completed progress.
    if (limit > 0) {
      final Paint glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 6 * scale
        ..strokeCap = StrokeCap.butt
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * scale)
        ..color = color.withValues(alpha: 0.35);
      for (int i = 0; i < n; i++) {
        final double segStart = i * stepAngle;
        if (segStart >= limit) break;
        final double segEnd = segStart + dashAngle;
        final double drawEnd = math.min(segEnd, limit);
        final double sweep = drawEnd - segStart;
        if (sweep <= 0) continue;
        canvas.drawArc(rect, startAngle + segStart, sweep, false, glowPaint);
      }
    }

    // Completed dashes in phase colour.
    final Paint colorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..color = color;
    for (int i = 0; i < n; i++) {
      final double segStart = i * stepAngle;
      if (segStart >= limit) break;
      final double segEnd = segStart + dashAngle;
      final double drawEnd = math.min(segEnd, limit);
      final double sweep = drawEnd - segStart;
      if (sweep <= 0) continue;
      canvas.drawArc(rect, startAngle + segStart, sweep, false, colorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FocusRingPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.segments != segments ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

class _ControlColumn extends StatelessWidget {
  const _ControlColumn({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        child,
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 12,
            color: palette.mute,
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.size,
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  final double size;
  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: borderColor),
        ),
        child: Icon(icon, size: size * 0.42, color: iconColor),
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  const _SegButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? palette.tx : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? palette.bg : palette.mute,
            ),
          ),
        ),
      ),
    );
  }
}

class _FsButton extends StatelessWidget {
  const _FsButton({required this.immersive, required this.onTap});

  final bool immersive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: palette.card,
          border: Border.all(color: palette.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          immersive ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          color: palette.tx,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Finished
// ---------------------------------------------------------------------------

class _FinishedView extends StatelessWidget {
  const _FinishedView({required this.session, required this.onDismiss});

  final FocusSessionState session;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final bool isBreak = session.isBreak;
    final bool skipped = session.reason == FocusEndReason.skipped;
    final Color accent = isBreak
        ? _ok
        : skipped
        ? palette.mute
        : _gold;
    final String title = isBreak
        ? l10n.focusBreakFinished
        : skipped
        ? l10n.focusStepSkippedTitle
        : l10n.focusSessionComplete;

    return Scaffold(
      backgroundColor: palette.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.14),
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                ),
                child: Icon(
                  isBreak
                      ? Icons.local_cafe_rounded
                      : skipped
                      ? Icons.skip_next_rounded
                      : Icons.check_rounded,
                  size: 40,
                  color: accent,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KTypography.displayFamily,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: palette.tx,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${_clock(session.recordedSeconds, free: session.mode == FocusMode.free)}  /  ${_clock(session.plannedSeconds, free: false)}',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 14,
                  color: palette.mute,
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: onDismiss,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    l10n.focusBackToSetup,
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0D1A2D),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop({required this.palette});

  final KhutatiPalette palette;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: palette.bg);
  }
}

String _subText(
  FocusSessionState session,
  FocusTaskDraft? draft,
  AppLocalizations l10n,
  FocusMode mode,
) {
  if (mode == FocusMode.linked) {
    if (session.isBreak) return '';
    final FocusStepRef? step = session.currentStep;
    if (step == null) return '';
    return '${step.label} · ${step.minutes} دقيقة';
  }
  if (mode == FocusMode.pomodoro) {
    if (session.isBreak) {
      return session.rounds >= 3 ? 'استراحة طويلة' : 'استراحة قصيرة';
    }
    return 'الجلسة ${(session.rounds % 4) + 1} من 4';
  }
  return session.isRunning ? 'يعمل' : 'مفتوح';
}

List<Widget> _dots(
  FocusSessionState session,
  FocusTaskDraft? draft,
  FocusMode mode,
) {
  if (mode == FocusMode.linked) {
    final int total = session.steps.length;
    if (total == 0) return <Widget>[];
    return List<Widget>.generate(total, (int i) {
      Color c = _trackColor;
      if (i < session.stepIndex) c = _ok;
      if (i == session.stepIndex) c = const Color(0xFF6AA6FF);
      return _Dot(color: c);
    });
  }
  if (mode == FocusMode.pomodoro) {
    final int cycle = (session.rounds % 4) + 1;
    return List<Widget>.generate(4, (int i) {
      Color c = _trackColor;
      if (i + 1 < cycle) c = _ok;
      if (i + 1 == cycle) c = session.isBreak ? _ok : _gold;
      return _Dot(color: c);
    });
  }
  return <Widget>[];
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

Color _subjectColor(FocusTaskDraft d) {
  return const Color(0xFF6AA6FF);
}


String _clock(int totalSeconds, {required bool free}) {
  final int safe = totalSeconds < 0 ? 0 : totalSeconds;
  final int h = safe ~/ 3600;
  final int m = (safe % 3600) ~/ 60;
  final int s = safe % 60;
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

class _HistoryButton extends StatelessWidget {
  const _HistoryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: palette.card,
          border: Border.all(color: palette.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.history_rounded, color: palette.tx),
      ),
    );
  }
}

class _FocusHistorySheet extends ConsumerWidget {
  const _FocusHistorySheet({required this.palette});
  final KhutatiPalette palette;

  String _modeLabel(String mode) {
    switch (mode) {
      case 'linked':
        return 'مرتبط بمهمة';
      case 'free':
        return 'مؤقت حر';
      default:
        return 'بومودورو';
    }
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'linked':
        return const Color(0xFF6AA6FF);
      case 'free':
        return const Color(0xFFEAE5DA);
      default:
        return const Color(0xFFE8B65A);
    }
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'linked':
        return Icons.task_alt_rounded;
      case 'free':
        return Icons.all_inclusive_rounded;
      default:
        return Icons.timer_rounded;
    }
  }

  String _dateLabel(DateTime date, AppLocalizations l10n) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime d = DateTime(date.year, date.month, date.day);
    final int diff = today.difference(d).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _fmtDuration(int seconds) {
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    if (m == 0) return '$s ثانية';
    if (s == 0) return '$m دقيقة';
    return '$m دقيقة $s ثانية';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<FocusSession>> history = ref.watch(focusHistoryProvider);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext ctx, ScrollController scroll) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'سجل التركيز',
                style: TextStyle(
                  fontFamily: KTypography.displayFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: palette.tx,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: history.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (Object e, StackTrace st) => Center(
                    child: Text(
                      'تعذّر تحميل السجل',
                      style: TextStyle(color: palette.mute),
                    ),
                  ),
                  data: (List<FocusSession> sessions) {
                    if (sessions.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.history_toggle_off_rounded,
                              size: 56,
                              color: palette.mute,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'لم تبدأ أي جلسات تركيز بعد. ابدأ الآن!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: KTypography.bodyFamily,
                                fontSize: 15,
                                color: palette.mute,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    // Group by date.
                    final Map<String, List<FocusSession>> groups =
                        <String, List<FocusSession>>{};
                    for (final FocusSession s in sessions) {
                      final String key = _dateLabel(s.startedAt, l10n);
                      groups.putIfAbsent(key, () => <FocusSession>[]).add(s);
                    }
                    final List<String> keys = groups.keys.toList();
                    return ListView.builder(
                      controller: scroll,
                      itemCount: keys.length,
                      itemBuilder: (BuildContext c, int gi) {
                        final String key = keys[gi];
                        final List<FocusSession> items = groups[key]!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                key,
                                style: TextStyle(
                                  fontFamily: KTypography.displayFamily,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: palette.gold,
                                ),
                              ),
                            ),
                            ...items.map((FocusSession s) {
                              final String mode = s.mode;
                              final String title =
                                  (s.taskTitle != null && s.taskTitle!.isNotEmpty)
                                  ? s.taskTitle!
                                  : (s.taskId != null ? 'مهمة' : _modeLabel(mode));
                              final String typeLabel = _modeLabel(mode);
                              final String status =
                                  s.completed ? 'مكتمل' : 'متوقف';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: palette.bg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: palette.line),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: _modeColor(mode).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        _modeIcon(mode),
                                        color: _modeColor(mode),
                                        size: 20,
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
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: palette.tx,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '$typeLabel · ${_fmtDuration(s.actualSeconds)} · $status',
                                            style: TextStyle(
                                              fontFamily: KTypography.bodyFamily,
                                              fontSize: 12,
                                              color: palette.mute,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
