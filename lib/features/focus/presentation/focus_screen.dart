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

    final bool isBreak = session.phase == 'break';
    final Color ambient = isBreak ? palette.ok : palette.redtx;

    // Completion prompt.
    if (session.awaitingCompletion && !_completionPromptShown) {
      _completionPromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCompletionPrompt(context, controller, l10n);
      });
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            ambient.withValues(alpha: 0.18),
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
            child: Column(
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
                KProgressRing(
                  progress: session.plannedSeconds > 0
                      ? session.remainingSeconds / session.plannedSeconds
                      : 0,
                  numeral: _format(session.remainingSeconds),
                  caption: session.taskTitle ?? l10n.focusPlaceholder,
                  color: ambient,
                  size: 260,
                ),
                const SizedBox(height: 16),
                if (session.subjectName != null)
                  Text(
                    session.subjectName!,
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: KTypography.muteSize,
                      color: palette.mute,
                    ),
                  ),
                const Spacer(),
                if (session.status == FocusStatus.idle) ...<Widget>[
                  KButton(
                    label: l10n.todayStartFocus,
                    expand: true,
                    onPressed: () => controller.start(
                      plannedSeconds: 25 * 60,
                      taskTitle: l10n.focusPlaceholder,
                    ),
                  ),
                ] else ...<Widget>[
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
                            controller.end();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
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
}
