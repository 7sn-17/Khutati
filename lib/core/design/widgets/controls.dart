import 'package:flutter/material.dart';

import '../palette.dart';
import '../tokens.dart';

/// `.chip` — a step toggle. Two-line: bold title over a muted time range.
///
/// Pressed state inverts to `--ok` with dark text, exactly like the prototype.
class KChip extends StatelessWidget {
  const KChip({
    required this.title,
    required this.subtitle,
    required this.selected,
    this.wide = false,
    this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;

  /// `.chip.one` — spans the full width and carries the red border used for
  /// single "solved the questions" steps.
  final bool wide;
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

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KMetrics.chipRadius),
        child: AnimatedContainer(
          duration: Duration(milliseconds: KMotion.navMs),
          constraints: const BoxConstraints(minHeight: KMetrics.chipMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: KMetrics.chipPaddingX,
            vertical: KMetrics.chipPaddingY,
          ),
          decoration: BoxDecoration(
            color: selected ? palette.ok : Colors.transparent,
            borderRadius: BorderRadius.circular(KMetrics.chipRadius),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.quoteSize,
                  fontWeight: FontWeight.w500,
                  color: titleColor,
                  height: KTypography.chipHeight,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: KTypography.chipSize,
                  color: textColor,
                  height: KTypography.chipHeight,
                ),
              ),
            ],
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
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final KButtonVariant variant;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final bool primary = variant == KButtonVariant.primary;

    final Widget content = Text(
      label,
      style: TextStyle(
        fontFamily: KTypography.bodyFamily,
        fontSize: KTypography.bodySize,
        fontWeight: FontWeight.w500,
        color: primary ? Colors.white : palette.tx,
      ),
    );

    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: KMetrics.buttonMinHeight),
          padding: EdgeInsets.symmetric(
            horizontal: primary ? KMetrics.buttonPaddingX : 18,
            vertical: KMetrics.buttonPaddingY,
          ),
          decoration: BoxDecoration(
            color: primary ? palette.red : Colors.transparent,
            borderRadius: BorderRadius.circular(KMetrics.buttonRadius),
            border: primary ? null : Border.all(color: palette.line),
          ),
          alignment: Alignment.center,
          width: expand ? double.infinity : null,
          child: content,
        ),
      ),
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
