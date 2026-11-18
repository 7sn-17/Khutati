import 'package:flutter/material.dart';

import '../../motion/press_scale.dart';
import '../../sound/sound_effects.dart';
import '../palette.dart';
import '../tokens.dart';
import 'pressable.dart';

/// `.chip` — a step toggle. Two-line: bold title over a muted time range.
///
/// It sits on a filled card rather than a bare outline so it reads as a control
/// you can press, and it carries a thin progress bar while a step is partially
/// done (first tap of the two-tap flow).
class KChip extends StatelessWidget {
  const KChip({
    required this.title,
    required this.subtitle,
    required this.selected,
    this.fraction = 0.0,
    this.wide = false,
    this.icon,
    this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final double fraction;
  final bool selected;

  /// `.chip.one` — spans the full width and carries the red border used for
  /// single "solved the questions" steps.
  final bool wide;

  /// Step-kind glyph so the three chips are distinguishable at a glance.
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final Color borderColor = selected
        ? palette.ok
        : wide
        ? palette.red
        : palette.line;
    final Color textColor = selected ? KColors.dark.bg : palette.mute;
    final Color titleColor = selected ? KColors.dark.bg : palette.tx;
    final Color accentColor = selected ? KColors.dark.bg : palette.redtx;
    final List<BoxShadow>? shadow = selected
        ? null
        : <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ];

    return Semantics(
      button: true,
      selected: selected,
      child: PressScale(
        scale: 0.96,
        enabled: onTap != null,
        duration: const Duration(milliseconds: 100),
        releaseDuration: const Duration(milliseconds: 140),
        child: AnimatedContainer(
          duration: Duration(milliseconds: KMotion.navMs),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: KMetrics.chipMinHeight),
          decoration: BoxDecoration(
            color: selected ? palette.ok : palette.card,
            borderRadius: BorderRadius.circular(KMetrics.chipRadius),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.0 : 0.75,
            ),
            boxShadow: shadow,
          ),
          // The ink surface sits *inside* the decoration so the splash paints
          // above the chip's fill instead of being hidden by it.
          child: KInkSurface(
            onTap: onTap,
            borderRadius: BorderRadius.circular(KMetrics.chipRadius),
            padding: const EdgeInsets.symmetric(
              horizontal: KMetrics.chipPaddingX,
              vertical: KMetrics.chipPaddingY,
            ),
            sound: KSound.toggle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, size: 14, color: titleColor),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KTypography.bodyFamily,
                          fontSize: KTypography.quoteSize,
                          fontWeight: FontWeight.w500,
                          color: titleColor,
                          height: KTypography.chipHeight,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.chipSize,
                    color: textColor,
                    height: KTypography.chipHeight,
                  ),
                ),
                if (fraction > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: fraction.clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: selected
                            ? KColors.dark.bg.withOpacity(0.3)
                            : palette.line,
                        valueColor: AlwaysStoppedAnimation<Color>(accentColor),
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

enum KButtonVariant { primary, secondary }

/// `.btn` / `.btn2` — 44dp tall, 12px radius, red fill or hairline outline.
class KButton extends StatelessWidget {
  const KButton({
    required this.label,
    this.onPressed,
    this.variant = KButtonVariant.primary,
    this.expand = false,
    this.loading = false,
    this.icon,
    this.sound = KSound.tap,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final KButtonVariant variant;
  final bool expand;

  /// Shows an in-button spinner and blocks taps without changing the button's
  /// height, so an async save or update check never jumps the layout.
  final bool loading;

  final IconData? icon;

  /// Override for buttons that start or stop the timer.
  final KSound sound;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final bool primary = variant == KButtonVariant.primary;
    final Color foreground = primary ? Colors.white : palette.tx;

    final Widget content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: loading
          ? SizedBox(
              key: const ValueKey<String>('kbutton-loading'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(foreground),
              ),
            )
          : Row(
              key: const ValueKey<String>('kbutton-label'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: KTypography.bodySize,
                      fontWeight: FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
    );

    return KPressable(
      onTap: onPressed,
      enabled: !loading && onPressed != null,
      borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
      color: primary ? palette.red : Colors.transparent,
      border: primary ? null : BorderSide(color: palette.line),
      padding: EdgeInsets.symmetric(
        horizontal: primary ? KMetrics.buttonPaddingX : 18,
        vertical: KMetrics.buttonPaddingY,
      ),
      minHeight: KMetrics.buttonMinHeight,
      expand: expand,
      sound: sound,
      child: content,
    );
  }
}

/// `.bar` — 8dp track with a rounded `--redtx` fill.
class KProgressBar extends StatelessWidget {
  const KProgressBar({required this.value, this.color, super.key});

  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final double clamped = value.clamp(0.0, 1.0).toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(KMetrics.barRadius),
      child: SizedBox(
        height: KMetrics.barHeight,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: ColoredBox(color: palette.line)),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: clamped,
                child: ColoredBox(color: color ?? palette.redtx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
