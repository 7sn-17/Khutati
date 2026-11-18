import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/progress.dart';
import '../../../core/design/widgets/surfaces.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/utils/format.dart';
import '../../../l10n/l10n.dart';
import '../application/focus_controller.dart';
import '../application/focus_setup_controller.dart';
import '../domain/focus_setup.dart';

/// Premium gold → deep-orange sweep for a focus phase.
const List<Color> _focusArc = <Color>[
  Color(0xFFF2CD86),
  Color(0xFFE8B65A),
  Color(0xFFD9823C),
  Color(0xFFB8501F),
];

/// Mint → teal for a break, so the phase is readable at a glance.
const List<Color> _breakArc = <Color>[
  Color(0xFFD3F1E4),
  Color(0xFF9BDCC2),
  Color(0xFF6BC0A1),
  Color(0xFF2F8F71),
];

const List<Color> _ctaGradient = <Color>[
  Color(0xFFF8E3B4),
  Color(0xFFEDC271),
  Color(0xFFD98A3E),
];

/// Deep navy that stays readable on every gold stop.
const Color _ctaInk = Color(0xFF0D1A2D);

/// The Focus tab.
///
/// One screen per state-machine stage, driven only by [FocusSessionState]:
/// setup (idle) → timer (running/paused) → completion (finished) → setup.
/// Nothing here infers state from timers or flags, which is what removes the
/// stuck-screen class of bugs.
class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key});

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  bool _immersive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(focusControllerProvider.notifier).consumePendingAction();
      _applySystemUi();
    });
  }

  @override
  void dispose() {
    if (_immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      _applySystemUi();
    }
    super.dispose();
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
    final KhutatiPalette palette = context.palette;
    final FocusSessionState session = ref.watch(focusControllerProvider);
    final Color accent = session.isBreak ? palette.ok : palette.gold;

    // A completion screen always leaves full screen, so the user can see the
    // status bar and the navigation again without hunting for the icon.
    ref.listen<FocusSessionState>(focusControllerProvider, (
      FocusSessionState? previous,
      FocusSessionState next,
    ) {
      if (next.isFinished && _immersive) _setImmersive(false);
    });

    return PopScope(
      canPop: !_immersive && !session.isFinished,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_immersive) {
          _setImmersive(false);
          return;
        }
        if (session.isFinished) {
          ref.read(focusControllerProvider.notifier).dismissFinished();
        }
      },
      child: Scaffold(
        backgroundColor: palette.bg,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _AmbientBackdrop(
              accent: accent,
              gold: palette.gold,
              active: session.isRunning,
            ),
            SafeArea(
              bottom: false,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: switch (session.stage) {
                  FocusStage.idle => _SetupView(
                    key: const ValueKey<String>('setup'),
                    immersive: _immersive,
                    onToggleImmersive: () => _setImmersive(!_immersive),
                  ),
                  FocusStage.running || FocusStage.paused => _TimerView(
                    key: const ValueKey<String>('timer'),
                    session: session,
                    immersive: _immersive,
                    onToggleImmersive: () => _setImmersive(!_immersive),
                  ),
                  FocusStage.finished => _FinishedView(
                    key: const ValueKey<String>('finished'),
                    session: session,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ambient background
// ---------------------------------------------------------------------------

/// Layered radial glows that fade to full transparency at every edge, painted
/// behind the whole scaffold body.
///
/// Because this lives below the scroll content (not inside it) there is no
/// AppBar elevation, no divider and no clipped container edge above the title:
/// the background is one continuous gradient in every state.
class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop({
    required this.accent,
    required this.gold,
    required this.active,
  });

  final Color accent;
  final Color gold;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: palette.bg),
        IgnorePointer(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOutCubic,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.42),
                radius: 1.08,
                colors: <Color>[
                  accent.withValues(alpha: active ? 0.26 : 0.14),
                  accent.withValues(alpha: active ? 0.09 : 0.05),
                  accent.withValues(alpha: 0),
                ],
                stops: const <double>[0.0, 0.46, 1.0],
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1.15, 1.2),
                radius: 0.95,
                colors: <Color>[
                  gold.withValues(alpha: 0.10),
                  gold.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Setup (idle)
// ---------------------------------------------------------------------------

class _SetupView extends ConsumerWidget {
  const _SetupView({
    required this.immersive,
    required this.onToggleImmersive,
    super.key,
  });

  final bool immersive;
  final VoidCallback onToggleImmersive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final KhutatiFormat format = KhutatiFormat(l10n);
    final FocusSetup setup = ref.watch(focusSetupProvider);
    final FocusSetupController setupController = ref.read(
      focusSetupProvider.notifier,
    );
    final FocusTaskDraft? draft = ref.watch(focusDraftProvider);
    final KhutatiHaptics haptics = ref.read(hapticsProvider);
    final FocusController controller = ref.read(focusControllerProvider.notifier);

    final bool hasDraft = draft != null && draft.steps.isNotEmpty;
    final FocusMode mode = setup.mode;
    final int minutes = mode == FocusMode.linked
        ? ((draft?.minutes ?? 0) > 0 ? draft!.minutes : 25)
        : setup.startMinutes;

    void startSession() {
      haptics.selection();
      if (mode == FocusMode.linked && hasDraft) {
        controller.start(
          mode: FocusMode.linked,
          minutes: minutes,
          draft: draft,
        );
        return;
      }
      final FocusMode effective = mode == FocusMode.linked
          ? FocusMode.pomodoro
          : mode;
      controller.start(
        mode: effective,
        minutes: setup.startMinutes,
        breakMinutes: setup.breakMinutes,
        autoBreak: effective == FocusMode.pomodoro && setup.autoBreak,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.navFocus,
                      style: TextStyle(
                        fontFamily: KTypography.displayFamily,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        color: palette.tx,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.focusSetupSubtitle,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 13,
                        color: palette.mute,
                      ),
                    ),
                  ],
                ),
              ),
              _CornerIcon(
                icon: immersive
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                onTap: onToggleImmersive,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _ModeSelector(
                    mode: mode,
                    onChanged: (FocusMode value) {
                      haptics.selection();
                      setupController.setMode(value);
                    },
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: KeyedSubtree(
                      key: ValueKey<FocusMode>(mode),
                      child: switch (mode) {
                        FocusMode.linked => hasDraft
                            ? _LinkedPanel(draft: draft!, format: format)
                            : const _NoTaskPanel(),
                        FocusMode.pomodoro => _PomodoroPanel(
                          setup: setup,
                          controller: setupController,
                        ),
                        FocusMode.free => _FreePanel(
                          setup: setup,
                          controller: setupController,
                          format: format,
                        ),
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.focusFinishHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: 12,
                      color: palette.mute.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            // The shell floats the navigation bar over the body, so the pinned
            // start button reserves its height unless full screen is on.
            padding: EdgeInsets.fromLTRB(0, 12, 0, immersive ? 22 : 96),
            child: _GoldButton(
              label: l10n.focusStartWithDuration(minutes),
              icon: Icons.play_arrow_rounded,
              onTap: startSession,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final FocusMode mode;
  final ValueChanged<FocusMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.card.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.line.withValues(alpha: 0.9)),
      ),
      child: Row(
        children: <Widget>[
          _ModeTab(
            label: l10n.focusModeLinked,
            icon: Icons.link_rounded,
            selected: mode == FocusMode.linked,
            onTap: () => onChanged(FocusMode.linked),
          ),
          _ModeTab(
            label: l10n.focusModePomodoro,
            icon: Icons.timer_outlined,
            selected: mode == FocusMode.pomodoro,
            onTap: () => onChanged(FocusMode.pomodoro),
          ),
          _ModeTab(
            label: l10n.focusModeFree,
            icon: Icons.hourglass_bottom_rounded,
            selected: mode == FocusMode.free,
            onTap: () => onChanged(FocusMode.free),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? palette.tx : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 18,
                color: selected ? palette.bg : palette.mute,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? palette.bg : palette.mute,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkedPanel extends StatelessWidget {
  const _LinkedPanel({required this.draft, required this.format});

  final FocusTaskDraft draft;
  final KhutatiFormat format;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final FocusStepRef? step = draft.current;
    final int remaining = draft.steps.length - draft.startIndex;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (draft.subjectName != null && draft.subjectName!.isNotEmpty)
                KTag(label: draft.subjectName!, color: palette.gold),
              const Spacer(),
              if (remaining > 0)
                Text(
                  l10n.focusRemainingSteps(remaining),
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 12,
                    color: palette.mute,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            draft.taskTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: KTypography.displayFamily,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: palette.tx,
            ),
          ),
          if (step != null) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Icon(
                  Icons.play_circle_outline_rounded,
                  size: 18,
                  color: palette.gold,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${step.label} · ${format.duration(step.minutes)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: 14,
                      color: palette.mute,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NoTaskPanel extends StatelessWidget {
  const _NoTaskPanel();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.inbox_outlined,
                size: 22,
                color: palette.mute,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.focusNoTaskTitle,
                  style: TextStyle(
                    fontFamily: KTypography.displayFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: palette.tx,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.focusNoTaskBody,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 13,
              height: 1.6,
              color: palette.mute,
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => context.go('/today'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.line),
              ),
              child: Text(
                l10n.focusGoToday,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.tx,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PomodoroPanel extends StatelessWidget {
  const _PomodoroPanel({required this.setup, required this.controller});

  final FocusSetup setup;
  final FocusSetupController controller;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;

    return _Panel(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _PresetChip(
                label: l10n.focusPresetClassic,
                selected: setup.preset == PomodoroPreset.classic,
                onTap: () => controller.setPreset(PomodoroPreset.classic),
              ),
              const SizedBox(width: 8),
              _PresetChip(
                label: l10n.focusPresetDeep,
                selected: setup.preset == PomodoroPreset.deep,
                onTap: () => controller.setPreset(PomodoroPreset.deep),
              ),
              const SizedBox(width: 8),
              _PresetChip(
                label: l10n.focusPresetCustom,
                selected: setup.preset == PomodoroPreset.custom,
                onTap: () => controller.setPreset(PomodoroPreset.custom),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _MinuteStepper(
                  label: l10n.focusFocusLength,
                  value: setup.focusMinutes,
                  min: FocusSetup.minMinutes,
                  max: FocusSetup.maxMinutes,
                  step: 5,
                  onChanged: controller.setFocusMinutes,
                ),
              ),
              Container(
                width: 1,
                height: 56,
                color: palette.line.withValues(alpha: 0.7),
              ),
              Expanded(
                child: _MinuteStepper(
                  label: l10n.focusBreakLength,
                  value: setup.breakMinutes,
                  min: 1,
                  max: 60,
                  step: 1,
                  onChanged: controller.setBreakMinutes,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: palette.line.withValues(alpha: 0.7)),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.focusAutoBreak,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 13.5,
                    color: palette.tx,
                  ),
                ),
              ),
              Switch.adaptive(
                value: setup.autoBreak,
                activeTrackColor: palette.gold,
                onChanged: controller.setAutoBreak,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FreePanel extends StatelessWidget {
  const _FreePanel({
    required this.setup,
    required this.controller,
    required this.format,
  });

  final FocusSetup setup;
  final FocusSetupController controller;
  final KhutatiFormat format;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MinuteStepper(
            label: l10n.focusFreeLength,
            value: setup.freeMinutes,
            min: FocusSetup.minMinutes,
            max: FocusSetup.maxMinutes,
            step: 5,
            onChanged: controller.setFreeMinutes,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final int minutes in <int>[15, 25, 45, 60, 90])
                _PresetChip(
                  label: format.duration(minutes),
                  selected: setup.freeMinutes == minutes,
                  expand: false,
                  onTap: () => controller.setFreeMinutes(minutes),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.focusSetupSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 12,
              color: palette.mute,
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.line.withValues(alpha: 0.9)),
      ),
      child: child,
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.expand = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// `true` inside a Row (equal widths), `false` inside a Wrap.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    final Widget chip = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? palette.gold.withValues(alpha: 0.16)
              : palette.card2.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? palette.gold.withValues(alpha: 0.65)
                : palette.line.withValues(alpha: 0.8),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? palette.tx : palette.mute,
          ),
        ),
      ),
    );

    return expand ? Expanded(child: chip) : chip;
  }
}

class _MinuteStepper extends StatelessWidget {
  const _MinuteStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Column(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 12,
            color: palette.mute,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _StepButton(
              icon: Icons.remove_rounded,
              onTap: value - step >= min ? () => onChanged(value - step) : null,
            ),
            SizedBox(
              width: 66,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontFamily: KTypography.displayFamily,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: palette.tx,
                ),
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              onTap: value + step <= max ? () => onChanged(value + step) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final bool enabled = onTap != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: palette.line.withValues(alpha: enabled ? 1 : 0.4),
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled
              ? palette.tx
              : palette.mute.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timer (running / paused)
// ---------------------------------------------------------------------------

class _TimerView extends ConsumerWidget {
  const _TimerView({
    required this.session,
    required this.immersive,
    required this.onToggleImmersive,
    super.key,
  });

  final FocusSessionState session;
  final bool immersive;
  final VoidCallback onToggleImmersive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final KhutatiFormat format = KhutatiFormat(l10n);
    final KhutatiHaptics haptics = ref.read(hapticsProvider);
    final FocusController controller = ref.read(focusControllerProvider.notifier);
    final Color accent = session.isBreak ? palette.ok : palette.gold;
    final FocusStepRef? step = session.currentStep;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _PhasePill(
                label: session.isBreak
                    ? l10n.focusPhaseBreak
                    : l10n.focusPhaseFocus,
                color: accent,
              ),
              const Spacer(),
              _CornerIcon(
                icon: immersive
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                onTap: onToggleImmersive,
              ),
            ],
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double ringSize = math
                    .min(
                      math.min(constraints.maxWidth * 0.92, constraints.maxHeight * 0.74),
                      360.0,
                    )
                    .clamp(150.0, 360.0);

                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const SizedBox(height: 8),
                        KProgressRing(
                          progress: session.progress,
                          numeral: _clock(session.remainingSeconds),
                          caption: session.isBreak
                              ? l10n.focusBreak
                              : _modeLabel(l10n, session.mode),
                          size: ringSize,
                          arcDegrees: 270,
                          glow: true,
                          gradientColors: session.isBreak
                              ? _breakArc
                              : _focusArc,
                        ),
                        const SizedBox(height: 24),
                        if (session.taskTitle != null &&
                            session.taskTitle!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              session.taskTitle!,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: KTypography.displayFamily,
                                fontSize: 23,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                                color: palette.tx,
                              ),
                            ),
                          ),
                        if (session.isBreak) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            l10n.focusBreakHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: KTypography.bodyFamily,
                              fontSize: 13,
                              color: palette.mute,
                            ),
                          ),
                        ] else if (step != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            '${step.label} · ${format.duration(step.minutes)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: KTypography.bodyFamily,
                              fontSize: 13.5,
                              color: palette.mute,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (!session.isBreak && step != null)
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () {
                  haptics.selection();
                  controller.skipStep();
                },
                icon: Icon(
                  Icons.skip_next_rounded,
                  size: 18,
                  color: palette.mute,
                ),
                label: Text(
                  l10n.focusSkip,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 13,
                    color: palette.mute,
                  ),
                ),
              ),
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: _ControlPill(
                  icon: session.isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  label: session.isPaused ? l10n.focusResume : l10n.focusPause,
                  onTap: () {
                    haptics.selection();
                    if (session.isPaused) {
                      controller.resume();
                    } else {
                      controller.pause();
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ControlPill(
                  icon: session.isBreak
                      ? Icons.check_rounded
                      : Icons.stop_rounded,
                  label: l10n.focusEnd,
                  danger: true,
                  onTap: () {
                    haptics.medium();
                    controller.endStep();
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: immersive ? 20 : 96),
        ],
      ),
    );
  }
}

class _PhasePill extends StatelessWidget {
  const _PhasePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: palette.tx,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlPill extends StatelessWidget {
  const _ControlPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final Color tint = danger ? palette.redtx : palette.tx;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: danger
                ? palette.red.withValues(alpha: 0.12)
                : palette.card.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: danger
                  ? palette.red.withValues(alpha: 0.38)
                  : palette.line,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 19, color: tint),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: tint,
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
// Finished
// ---------------------------------------------------------------------------

class _FinishedView extends ConsumerWidget {
  const _FinishedView({required this.session, super.key});

  final FocusSessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final KhutatiHaptics haptics = ref.read(hapticsProvider);
    final FocusController controller = ref.read(focusControllerProvider.notifier);
    final FocusSetup setup = ref.watch(focusSetupProvider);

    final bool isBreak = session.isBreak;
    final bool skipped = session.reason == FocusEndReason.skipped;
    final Color accent = isBreak
        ? palette.ok
        : skipped
        ? palette.mute
        : palette.gold;
    final String title = isBreak
        ? l10n.focusBreakFinished
        : skipped
        ? l10n.focusStepSkippedTitle
        : l10n.focusSessionComplete;
    final IconData badge = isBreak
        ? Icons.local_cafe_rounded
        : skipped
        ? Icons.skip_next_rounded
        : Icons.check_rounded;
    final FocusStepRef? next = session.nextStep;

    final bool stepRecorded =
        !isBreak &&
        !skipped &&
        session.mode == FocusMode.linked &&
        session.currentStep != null;

    Future<void> startRound() async {
      final FocusMode mode = setup.mode == FocusMode.free
          ? FocusMode.free
          : FocusMode.pomodoro;
      await controller.start(
        mode: mode,
        minutes: setup.startMinutes,
        breakMinutes: setup.breakMinutes,
        autoBreak: mode == FocusMode.pomodoro && setup.autoBreak,
      );
    }

    final Widget? primary;
    if (!isBreak && next != null) {
      primary = _GoldButton(
        label: l10n.focusNextStepWithDuration(next.minutes),
        icon: Icons.arrow_forward_rounded,
        onTap: () {
          haptics.selection();
          controller.startNextStep();
        },
      );
    } else if (isBreak) {
      primary = _GoldButton(
        label: l10n.focusStartFocusNow,
        icon: Icons.play_arrow_rounded,
        onTap: () {
          haptics.selection();
          startRound();
        },
      );
    } else if (session.mode != FocusMode.linked || session.steps.isEmpty) {
      primary = _GoldButton(
        label: l10n.focusAnotherRound,
        icon: Icons.replay_rounded,
        onTap: () {
          haptics.selection();
          startRound();
        },
      );
    } else {
      primary = null;
    }

    return Center(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (BuildContext context, double t, Widget? child) {
            return Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.14),
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.18),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(badge, size: 40, color: accent),
              ),
              const SizedBox(height: 22),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KTypography.displayFamily,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: palette.tx,
                ),
              ),
              if (session.taskTitle != null &&
                  session.taskTitle!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  session.taskTitle!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 14,
                    color: palette.mute,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: palette.card.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _FinishedStat(
                      label: l10n.focusRecorded,
                      value: _clock(session.recordedSeconds),
                    ),
                    Container(
                      width: 1,
                      height: 34,
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      color: palette.line,
                    ),
                    _FinishedStat(
                      label: l10n.focusPlanned,
                      value: _clock(session.plannedSeconds),
                    ),
                  ],
                ),
              ),
              if (stepRecorded) ...<Widget>[
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: palette.ok,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.focusStepMarkedDone,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 12.5,
                        color: palette.ok,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              if (primary != null) primary,
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  haptics.selection();
                  controller.dismissFinished();
                },
                child: Text(
                  l10n.focusBackToSetup,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.mute,
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

class _FinishedStat extends StatelessWidget {
  const _FinishedStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: palette.tx,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 11.5,
            color: palette.mute,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

class _GoldButton extends StatelessWidget {
  const _GoldButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFE8B65A).withValues(alpha: 0.32),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _ctaGradient,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, size: 20, color: _ctaInk),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: _ctaInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CornerIcon extends StatelessWidget {
  const _CornerIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Material(
      color: palette.card.withValues(alpha: 0.7),
      shape: CircleBorder(
        side: BorderSide(color: palette.line.withValues(alpha: 0.9)),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 19, color: palette.tx),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _clock(int totalSeconds) {
  final int safe = totalSeconds < 0 ? 0 : totalSeconds;
  final int minutes = safe ~/ 60;
  final int seconds = safe % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

String _modeLabel(AppLocalizations l10n, FocusMode mode) {
  return switch (mode) {
    FocusMode.linked => l10n.focusModeLinked,
    FocusMode.pomodoro => l10n.focusModePomodoro,
    FocusMode.free => l10n.focusModeFree,
  };
}
