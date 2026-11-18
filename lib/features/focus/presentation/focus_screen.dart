import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/motion/haptics.dart';
import '../../../l10n/l10n.dart';
import '../application/focus_controller.dart';

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
  void dispose() {
    if (_immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _toggleImmersive() {
    setState(() => _immersive = !_immersive);
    if (_immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
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
    final String stepLabel = session.stepId == null
        ? ''
        : (session.isBreak ? '' : '${session.taskTitle ?? ''}');

    final Widget ring = KProgressRing(
      progress: session.plannedSeconds > 0
          ? session.remainingSeconds / session.plannedSeconds
          : 0,
      numeral: _format(session.remainingSeconds),
      caption: isBreak
          ? l10n.focusBreak
          : (session.taskTitle ?? l10n.focusPlaceholder),
      color: ambient,
      size: ringSize,
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
                taskTitle: l10n.focusPlaceholder,
              );
            },
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: KButton(
                      label: session.isPaused
                          ? l10n.focusResume
                          : l10n.focusPause,
                      variant: KButtonVariant.secondary,
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
                    child: KButton(
                      label: l10n.focusEnd,
                      variant: KButtonVariant.secondary,
                      onPressed: () {
                        haptics.selection();
                        if (isBreak) {
                          controller.skipBreak();
                        } else {
                          controller.end();
                        }
                      },
                    ),
                  ),
                ],
              ),
              if (session.nextStepPlannedSeconds != null &&
                  !isBreak) ...<Widget>[
                const SizedBox(height: 12),
                KButton(
                  label: l10n.focusSkipNext,
                  variant: KButtonVariant.secondary,
                  expand: true,
                  onPressed: () {
                    haptics.selection();
                    controller.startNextStep();
                  },
                ),
              ],
              if (isBreak) ...<Widget>[
                const SizedBox(height: 12),
                KButton(
                  label: l10n.focusSkipBreak,
                  variant: KButtonVariant.secondary,
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
                      if (!_immersive)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              l10n.navFocus,
                              style: TextStyle(
                                fontFamily: KTypography.displayFamily,
                                fontSize: KTypography.h1Size,
                                fontWeight: FontWeight.w700,
                                color: palette.tx,
                              ),
                            ),
                            IconButton(
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
              controller.start(
                plannedSeconds: 25 * 60,
                taskTitle: l10n.focusPlaceholder,
              );
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.focusResume),
          ),
        ],
      ),
    );
  }
}
