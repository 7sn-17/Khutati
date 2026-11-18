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

/// Opens a [KDialog] with a dimmed scrim and a fast fade+scale entry.
///
/// Performance notes (this route is opened dozens of times per session):
///
/// * The backdrop is a **flat tint**, not a `BackdropFilter`. Blurring the whole
///   screen costs a GPU pass over the full window on every animation frame, and
///   the dialog content sits on top of that same layer — on mid-range phones
///   this was the single cause of the "freeze" while a modal opened. A flat
///   tint gives the same perceived depth for a fraction of the cost.
/// * Only the card animates (fade + 0.95→1.0 scale, 200 ms, `easeOut`). The
///   scrim is painted once by the route barrier and then merely composited, so
///   opening never re-rasterises the screen behind the dialog.
/// * The card is wrapped in a [RepaintBoundary]; a repaint inside the dialog
///   (typing a name, a button switching to its loading state) cannot dirty the
///   page underneath.
Future<T?> showKDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  final KhutatiPalette palette = context.palette;
  // A scrim has to *darken* in both themes. `bg` is navy in dark mode but cream
  // in light mode, so using it everywhere would wash the light theme out; the
  // ink colour (`tx`) is the correct veil there.
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  final Color scrim = (isDark ? palette.bg : palette.tx).withValues(
    alpha: isDark ? 0.66 : 0.30,
  );
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: scrim,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) {
          return SafeArea(
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
          );
        },
    transitionBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          final CurvedAnimation curved = CurvedAnimation(
            parent: animation,
            // A short, decelerating curve reads as "instant" without a visible pop.
            curve: Curves.easeOut,
            reverseCurve: Curves.easeIn,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
              child: child,
            ),
          );
        },
  );
}

/// The dialog card itself. Public so the update dialog can reuse the exact same
/// surface without nesting a second route.
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
    // Deliberately opaque-ish: the card no longer sits behind a blurred
    // backdrop, so its own fill has to carry the contrast. 0.97 keeps the
    // scrim from bleeding through text while still reading as a surface.
    final Color fill = palette.card.withValues(alpha: 0.97);
    final BorderRadius radius = BorderRadius.circular(28);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(color: palette.gold.withValues(alpha: 0.26)),
        // A tighter shadow than before: the old 40 px radius was rasterised on
        // every scale frame, which is pure cost during the entry animation.
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.bg.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: RepaintBoundary(
        // The boundary sits *inside* the decorated box on purpose: the shadow
        // and border are painted in the route's own layer (a cached boundary
        // would clip them at the card edge), while any repaint caused by the
        // dialog's content stays inside this boundary.
        child: ClipRRect(
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Material(
              // A dialog route is not wrapped in a Material by default. Without
              // this, every InkWell (the close button and each KButton) throws
              // "No Material widget found" the first time it is tapped.
              type: MaterialType.transparency,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
