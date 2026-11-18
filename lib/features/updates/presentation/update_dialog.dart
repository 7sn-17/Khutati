import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/feedback.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../application/update_controller.dart';
import '../domain/app_release.dart';

/// Presents the available release as the same premium modal shell used by every
/// other dialog: blurred backdrop, 28px radius, product typography and
/// full-width [KButton] actions.
Future<void> showUpdateDialog(
  BuildContext context, {
  required UpdateManifest manifest,
  UpdateSource? source,
}) {
  return showKDialog<void>(
    context: context,
    builder: (BuildContext ctx) =>
        _UpdateDialog(manifest: manifest, source: source),
  );
}

class _UpdateDialog extends ConsumerStatefulWidget {
  const _UpdateDialog({required this.manifest, this.source});

  final UpdateManifest manifest;
  final UpdateSource? source;

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    final bool opened = await ref
        .read(updateControllerProvider.notifier)
        .openDownload(widget.manifest);
    if (!mounted) return;
    setState(() => _opening = false);
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

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final KhutatiPalette palette = context.palette;
    final String? notes = widget.manifest.notes?.trim();

    return KDialog(
      eyebrow: l10n.updateDialogEyebrow,
      title: l10n.updateDialogTitle,
      icon: Icons.system_update_alt_rounded,
      message: l10n.updateAvailable(widget.manifest.versionName),
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.source != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.source == UpdateSource.supabase
                    ? l10n.updateSourceSupabase
                    : l10n.updateSourceGithub,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.tagSize,
                  color: palette.mute,
                ),
              ),
            ),
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
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.updateWhatsNew,
                        style: TextStyle(
                          fontFamily: KTypography.bodyFamily,
                          fontSize: KTypography.smallSize,
                          fontWeight: FontWeight.w600,
                          color: palette.tx,
                        ),
                      ),
                    ),
                    // The version belongs to the notes it describes, and the
                    // gold echoes the dialog's accent without a new badge.
                    Text(
                      'v${widget.manifest.versionName}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.smallSize,
                        fontWeight: FontWeight.w600,
                        color: palette.gold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 190),
                  child: SingleChildScrollView(
                    child: Text(
                      notes == null || notes.isEmpty
                          ? l10n.updateNoNotes
                          : notes,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.muteSize,
                        height: 1.65,
                        color: palette.mute,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: <KDialogAction>[
        KDialogAction(
          label: l10n.updateNow,
          icon: Icons.download_rounded,
          loading: _opening,
          onPressed: _opening ? null : () => unawaited(_open()),
        ),
      ],
      // The two ways out sit side by side under the update button: they are
      // the same kind of decision, and stacking them made the dialog taller
      // than the notes it was showing.
      secondaryActions: <KDialogAction>[
        KDialogAction(
          label: l10n.updateLater,
          variant: KButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        KDialogAction(
          label: l10n.updateSkipVersion,
          variant: KButtonVariant.secondary,
          onPressed: () async {
            await ref.read(updateControllerProvider.notifier).skip();
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
