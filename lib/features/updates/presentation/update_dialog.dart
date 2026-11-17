import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/feedback.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../application/update_controller.dart';
import '../domain/app_release.dart';

/// Presents the available release as a focused, branded dialog. The same
/// surface is used by the silent launch/resume check and by Settings, so there
/// is only one update experience in the app.
Future<void> showUpdateDialog(
  BuildContext context, {
  required UpdateManifest manifest,
  UpdateSource? source,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: context.palette.bg.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) {
          return _UpdateDialog(manifest: manifest, source: source);
        },
    transitionBuilder:
        (BuildContext context, Animation<double> animation, _, Widget child) {
          final CurvedAnimation curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
              child: child,
            ),
          );
        },
  );
}

class _UpdateDialog extends ConsumerWidget {
  const _UpdateDialog({required this.manifest, this.source});

  final UpdateManifest manifest;
  final UpdateSource? source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final String? notes = manifest.notes?.trim();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.gold.withValues(alpha: 0.42)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: palette.bg.withValues(alpha: 0.45),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: palette.gold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      color: palette.gold,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.updateDialogEyebrow,
                          style: TextStyle(
                            fontFamily: KTypography.bodyFamily,
                            fontSize: KTypography.tagSize,
                            color: palette.gold,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.updateDialogTitle,
                          style: TextStyle(
                            fontFamily: KTypography.displayFamily,
                            fontSize: 24,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            color: palette.tx,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.close, color: palette.mute, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: palette.card2,
                      borderRadius: BorderRadius.circular(KMetrics.pillRadius),
                      border: Border.all(color: palette.line),
                    ),
                    child: Text(
                      l10n.updateAvailable(manifest.versionName),
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.smallSize,
                        fontWeight: FontWeight.w500,
                        color: palette.tx,
                      ),
                    ),
                  ),
                  if (source != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Text(
                      source == UpdateSource.supabase
                          ? l10n.updateSourceSupabase
                          : l10n.updateSourceGithub,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.tagSize,
                        color: palette.mute,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.card2,
                  borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
                  border: Border.all(color: palette.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.updateWhatsNew,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.smallSize,
                        fontWeight: FontWeight.w600,
                        color: palette.tx,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notes == null || notes.isEmpty
                          ? l10n.updateNoNotes
                          : notes,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.muteSize,
                        height: 1.6,
                        color: palette.mute,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              KButton(
                label: l10n.updateNow,
                expand: true,
                onPressed: () => unawaited(_open(context, ref)),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.mute,
                      textStyle: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.smallSize,
                      ),
                    ),
                    child: Text(l10n.updateLater),
                  ),
                  Container(width: 1, height: 14, color: palette.line),
                  TextButton(
                    onPressed: () async {
                      await ref.read(updateControllerProvider.notifier).skip();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: palette.mute,
                      textStyle: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.smallSize,
                      ),
                    ),
                    child: Text(l10n.updateSkipVersion),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final bool opened = await ref
        .read(updateControllerProvider.notifier)
        .openDownload(manifest);
    if (!context.mounted) return;
    if (opened) {
      Navigator.of(context).pop();
      return;
    }
    showKToast(
      context,
      context.l10n.updateLaunchFailed,
      kind: KToastKind.error,
    );
  }
}
