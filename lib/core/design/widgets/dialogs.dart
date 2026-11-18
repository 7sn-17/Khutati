import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../palette.dart';
import '../tokens.dart';
import 'controls.dart';

/// One action rendered inside a [KDialog].
class KDialogAction {
  const KDialogAction({
    required this.label,
    this.onPressed,
    this.variant = KButtonVariant.primary,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final KButtonVariant variant;
  final bool loading;
  final IconData? icon;
}

/// Premium modal shell: blurred backdrop, 28px radius, product typography and
/// full-width [KButton] actions. No stock Material AlertDialog anywhere.
class KDialog extends StatelessWidget {
  const KDialog({
    required this.title,
    this.eyebrow,
    this.message,
    this.icon,
    this.accent,
    this.child,
    this.actions = const <KDialogAction>[],
    this.onClose,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final String? message;
  final IconData? icon;
  final Color? accent;
  final Widget? child;
  final List<KDialogAction> actions;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final Color tint = accent ?? palette.gold;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: tint.withValues(alpha: 0.28)),
                ),
                child: Icon(icon, size: 22, color: tint),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (eyebrow != null) ...<Widget>[
                    Text(
                      eyebrow!,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KTypography.tagSize,
                        fontWeight: FontWeight.w600,
                        color: tint,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: KTypography.displayFamily,
                      fontSize: 21,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: palette.tx,
                    ),
                  ),
                ],
              ),
            ),
            if (onClose != null)
              Semantics(
                button: true,
                label: 'إغلاق',
                child: InkWell(
                  onTap: onClose,
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: palette.mute,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (message != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            message!,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.muteSize,
              height: 1.7,
              color: palette.mute,
            ),
          ),
        ],
        if (child != null) ...<Widget>[
          const SizedBox(height: 14),
          child!,
        ],
        if (actions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          for (int i = 0; i < actions.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 8),
            KButton(
              label: actions[i].label,
              icon: actions[i].icon,
              variant: actions[i].variant,
              loading: actions[i].loading,
              expand: true,
              onPressed: actions[i].onPressed,
            ),
          ],
        ],
      ],
    );
  }
}

/// Opens a [KDialog] with a blurred, dimmed backdrop and a fade+scale entry.
Future<T?> showKDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  final KhutatiPalette palette = context.palette;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: palette.bg.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    ) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: const ColoredBox(color: Colors.transparent),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _DialogSurface(child: builder(context)),
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      final CurvedAnimation curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// The actual frosted card. Public so the update dialog can reuse the exact
/// same surface without nesting a second route.
class KDialogSurface extends StatelessWidget {
  const KDialogSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => _DialogSurface(child: child);
}

class _DialogSurface extends StatelessWidget {
  const _DialogSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          decoration: BoxDecoration(
            color: palette.card.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.gold.withValues(alpha: 0.26)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: palette.bg.withValues(alpha: 0.52),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Material(
            // A dialog route is not wrapped in a Material by default. Without
            // this, every InkWell (the close button and each KButton) throws
            // "No Material widget found" the first time it is tapped.
            type: MaterialType.transparency,
            child: child,
          ),
        ),
      ),
    );
  }
}
