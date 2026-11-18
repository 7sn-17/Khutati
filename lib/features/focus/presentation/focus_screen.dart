import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/motion/haptics.dart';
import '../../../l10n/l10n.dart';
import '../application/focus_controller.dart'
    show FocusController, FocusSessionState, FocusStatus, focusControllerProvider, focusImmersiveProvider;

class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key});

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  bool _immersive = false;
  bool _completionPromptShown = false;
  bool _resumePromptShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(focusControllerProvider.notifier).consumePendingAction();
      _updateSystemUi();
    });
  }

  @override
  void dispose() {
    if (_immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _toggleImmersive() {
    setState(() => _immersive = !_immersive);
    ref.read(focusImmersiveProvider.notifier).state = _immersive;
    if (_immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _updateSystemUi();
  }

  void _updateSystemUi() {
    final Brightness brightness = Theme.of(context).brightness;
    final bool lightIcons = brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            lightIcons ? Brightness.light : Brightness.dark,
        statusBarBrightness:
            lightIcons ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            lightIcons ? Brightness.light : Brightness.dark,
      ),
    );
  }

  String _format(int seconds) {
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final FocusSessionState session = ref.watch(focusControllerProvider);
    final FocusController controller = ref.read(
      focusControllerProvider.notifier,
    );
    final KhutatiHaptics haptics = ref.read(hapticsProvider);

    final bool isBreak = session.isBreak;
    final Color ambient = isBreak ? palette.ok : palette.redtx;

    if (session.awaitingCompletion && !_completionPromptShown) {
      _completionPromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCompletionPrompt(context, controller, l10n, session);
      });
    }
    if (session.awaitingResume && !_resumePromptShown) {
      _resumePromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showResumePrompt(context, controller, l10n);
      });
    }

    final Size screenSize = MediaQuery.sizeOf(context);
    final bool landscape = screenSize.width > screenSize.height;
    final double ringSize = (screenSize.shortestSide * 0.42).clamp(
      180.0,
      320.0,
    );

    final String phaseLabel = isBreak ? l10n.focusBreak : l10n.navFocus;

    final Widget ring = KProgressRing(
      progress: session.plannedSeconds > 0
          ? session.remainingSeconds / session.plannedSeconds
          : 0,
      numeral: _format(session.remainingSeconds),
      caption: isBreak ? l10n.focusBreak : session.taskTitle,
      color: ambient,
      size: ringSize,
      arcDegrees: 270,
      glow: true,
    );

    final Widget details = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (session.subjectName != null)
          Text(
            session.subjectName!,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.muteSize,
              color: palette.mute,
            ),
          ),
        if (session.nextStepTitle != null && !isBreak) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '${l10n.focusNextStep}: ${session.nextStepTitle}',
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.smallSize,
              color: palette.mute,
            ),
          ),
        ],
      ],
    );

    final Widget controls = session.status == FocusStatus.idle
        ? KButton(
            label: l10n.todayStartFocus,
            expand: true,
            onPressed: () {
              haptics.selection();
              controller.start(
                plannedSeconds: 25 * 60,
                taskTitle: l10n.navFocus,
              );
            },
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _PremiumFocusButton(
                      icon: session.isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      label: session.isPaused
                          ? l10n.focusResume
                          : l10n.focusPause,
                      color: palette.tx,
                      onPressed: () {
                        haptics.selection();
                        if (session.isPaused) {
                          controller.resume();
                        } else {
                          controller.pause();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PremiumFocusButton(
                      icon: Icons.stop_rounded,
                      label: l10n.focusEnd,
                      color: palette.redtx,
                      onPressed: () {
                        haptics.selection();
                        if (isBreak) {
                          controller.skipBreak();
                        } else {
                          controller.endSession();
                        }
                      },
                    ),
                  ),
                ],
              ),
              if (controller.hasNextStep && !isBreak) ...<Widget>[
                const SizedBox(height: 12),
                _PremiumFocusButton(
                  icon: Icons.skip_next_rounded,
                  label: l10n.focusSkip,
                  color: palette.mute,
                  expand: true,
                  onPressed: () {
                    haptics.selection();
                    controller.skipStep();
                  },
                ),
              ],
              if (isBreak) ...<Widget>[
                const SizedBox(height: 12),
                _PremiumFocusButton(
                  icon: Icons.skip_next_rounded,
                  label: l10n.focusSkipBreak,
                  color: palette.mute,
                  expand: true,
                  onPressed: () {
                    haptics.selection();
                    controller.skipBreak();
                  },
                ),
              ],
            ],
          );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            ambient.withValues(alpha: 0.20),
            palette.bg,
            palette.bg,
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KMetrics.appPaddingX,
            ),
            child: landscape
                ? Row(
                    children: <Widget>[
                      Expanded(child: Center(child: ring)),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                phaseLabel,
                                style: TextStyle(
                                  fontFamily: KTypography.displayFamily,
                                  fontSize: KTypography.h1Size,
                                  fontWeight: FontWeight.w700,
                                  color: palette.tx,
                                ),
                              ),
                              const SizedBox(height: 8),
                              details,
                              const SizedBox(height: 24),
                              controls,
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            isBreak ? l10n.focusBreak : l10n.navFocus,
                            style: TextStyle(
                              fontFamily: KTypography.displayFamily,
                              fontSize: KTypography.h1Size,
                              fontWeight: FontWeight.w700,
                              color: palette.tx,
                            ),
                          ),
                          IconButton(
                            tooltip: _immersive
                                ? l10n.focusExitImmersive
                                : l10n.focusExitImmersive,
                            icon: Icon(
                              _immersive
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              color: palette.mute,
                            ),
                            onPressed: _toggleImmersive,
                          ),
                        ],
                      ),
                      if (_immersive)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton.icon(
                            onPressed: _toggleImmersive,
                            icon: const Icon(Icons.fullscreen_exit_rounded),
                            label: Text(l10n.focusExitImmersive),
                          ),
                        ),
                      const Spacer(),
                      ring,
                      const SizedBox(height: 16),
                      details,
                      const Spacer(),
                      controls,
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  void _showCompletionPrompt(
    BuildContext context,
    FocusController controller,
    AppLocalizations l10n,
    FocusSessionState session,
  ) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l10n.focusSessionComplete),
        content: Text(l10n.focusMarkCompletePrompt),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              controller.dismissCompletion();
              _completionPromptShown = false;
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.focusCancel),
          ),
          if (session.nextStepPlannedSeconds != null)
            TextButton(
              onPressed: () async {
                await controller.markTaskCompleted();
                await controller.startNextStep();
                _completionPromptShown = false;
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text(l10n.focusStartNextStep),
            ),
          TextButton(
            onPressed: () async {
              await controller.markTaskCompleted();
              _completionPromptShown = false;
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(l10n.focusConfirm),
          ),
        ],
      ),
    );
  }

  void _showResumePrompt(
    BuildContext context,
    FocusController controller,
    AppLocalizations l10n,
  ) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l10n.focusBreakEnded),
        content: Text(l10n.focusResumePrompt),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              controller.dismissResume();
              _resumePromptShown = false;
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.focusCancel),
          ),
          TextButton(
            onPressed: () {
              controller.dismissResume();
              _resumePromptShown = false;
              controller.resumeFromBreak();
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.focusResume),
          ),
        ],
      ),
    );
  }
}

class _PremiumFocusButton extends StatelessWidget {
  const _PremiumFocusButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.expand = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: KTypography.bodySize,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
          child: Container(
            constraints: const BoxConstraints(minHeight: KMetrics.buttonMinHeight),
            padding: const EdgeInsets.symmetric(
              horizontal: KMetrics.buttonPaddingX,
              vertical: KMetrics.buttonPaddingY,
            ),
            decoration: BoxDecoration(
              color: palette.card.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
              border: Border.all(color: palette.line),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            width: expand ? double.infinity : null,
            child: content,
          ),
        ),
      ),
    );
  }
}
