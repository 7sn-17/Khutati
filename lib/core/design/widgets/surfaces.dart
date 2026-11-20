import 'package:flutter/material.dart';

import '../../motion/press_scale.dart';
import '../../sound/sound_effects.dart';
import '../palette.dart';
import '../svg_path.dart';
import '../tokens.dart';
import 'pressable.dart';

/// A soft lift for light mode, where warm cards sit on a warm page and need a
/// shadow to read as separate surfaces. Dark mode stays flat: the navy cards
/// already separate from the background.
List<BoxShadow> kCardShadow(BuildContext context) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
    return const <BoxShadow>[];
  }
  if (Theme.of(context).brightness == Brightness.dark) {
    return const <BoxShadow>[];
  }
  return <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF16233A).withValues(alpha: 0.05),
      blurRadius: 14,
      offset: const Offset(0, 4),
    ),
  ];
}

/// The prototype's card: `--card` background, 1px `--line` border, optional
/// subject accent on the inline-start edge, and the repeating hexagon texture
/// (`background: var(--card) var(--hx)`).
class KCard extends StatelessWidget {
  const KCard({
    required this.child,
    this.padding = const EdgeInsets.all(KMetrics.timelinePaddingX),
    this.radius,
    this.accentColor,
    this.showPattern = true,
    this.borderColor,
    this.onTap,
    this.sound = KSound.tap,
    this.pressScale = 0.98,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;
  final Color? accentColor;
  final bool showPattern;
  final Color? borderColor;

  /// Makes the whole card a button: clipped ripple, press squish and a sound.
  /// Leave null for cards that only display information.
  final VoidCallback? onTap;

  /// Played on a completed tap, never on press-down.
  final KSound sound;

  /// Full-width cards squish less than a chip or a button; 0.96 on a card that
  /// spans the screen reads as a layout jump rather than a press.
  final double pressScale;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final double r = radius ?? KMetrics.cardRadius;
    final BorderRadius borderRadius = BorderRadius.circular(r);

    Widget body = Stack(
      children: <Widget>[
        if (showPattern)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: HexagonPatternPainter()),
            ),
          ),
        Padding(padding: padding, child: child),
        if (accentColor != null)
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: KMetrics.timelineAccentWidth,
              color: accentColor,
            ),
          ),
      ],
    );

    // The ink surface goes *inside* the clipped stack so the splash paints
    // above the card fill instead of being hidden underneath it.
    if (onTap != null) {
      body = KInkSurface(
        onTap: onTap,
        borderRadius: borderRadius,
        sound: sound,
        child: body,
      );
    }

    final Widget card = Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? palette.line),
        boxShadow: kCardShadow(context),
      ),
      child: ClipRRect(borderRadius: borderRadius, child: body),
    );

    if (onTap == null) return card;

    return PressScale(
      scale: pressScale,
      duration: const Duration(milliseconds: 100),
      releaseDuration: const Duration(milliseconds: 140),
      child: card,
    );
  }
}

/// Paints the prototype's 56x64 hexagon tile, stroke #888 at 20% opacity.
class HexagonPatternPainter extends CustomPainter {
  HexagonPatternPainter();

  static final Path _tile = parseSvgPath(KArtwork.hexPatternPath);
  static final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = KArtwork.hexStroke.withValues(alpha: KArtwork.hexOpacity);

  @override
  void paint(Canvas canvas, Size size) {
    for (
      double y = 0;
      y < size.height + KArtwork.hexTileHeight;
      y += KArtwork.hexTileHeight
    ) {
      for (
        double x = 0;
        x < size.width + KArtwork.hexTileWidth;
        x += KArtwork.hexTileWidth
      ) {
        canvas.save();
        canvas.translate(x, y);
        canvas.drawPath(_tile, _paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant HexagonPatternPainter oldDelegate) => false;
}

/// `.pill` — rounded status chip with an optional gold value.
class KPill extends StatelessWidget {
  const KPill({required this.label, this.value, super.key});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Container(
      constraints: const BoxConstraints(minHeight: KMetrics.pillMinHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: KMetrics.pillPaddingX,
        vertical: KMetrics.pillPaddingY,
      ),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(KMetrics.pillRadius),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: KTypography.pillSize,
              color: palette.mute,
            ),
          ),
          if (value != null) ...<Widget>[
            const SizedBox(width: 6),
            Text(
              value!,
              style: TextStyle(
                fontFamily: KTypography.bodyFamily,
                fontSize: KTypography.pillSize,
                fontWeight: FontWeight.w500,
                color: palette.gold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.tag` — subject label on a solid accent colour.
class KTag extends StatelessWidget {
  const KTag({required this.label, required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KMetrics.tagPaddingX,
        vertical: KMetrics.tagPaddingY,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(KMetrics.pillRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KTypography.bodyFamily,
          fontSize: KTypography.tagSize,
          fontWeight: FontWeight.w500,
          // The prototype pins tag text to the dark background colour so it
          // reads on every accent, in both themes.
          color: KColors.dark.bg,
          height: 1.4,
        ),
      ),
    );
  }
}

/// `h2` — section heading with the prototype's 24/12 margins.
class KSectionHeader extends StatelessWidget {
  const KSectionHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: KTypography.displayFamily,
          fontSize: KTypography.h2Size,
          fontWeight: FontWeight.w700,
          color: palette.tx,
        ),
      ),
    );
  }
}

/// `.br` — break divider: label centred between two hairlines.
class KBreakDivider extends StatelessWidget {
  const KBreakDivider({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Container(height: 1, color: palette.line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: palette.card2,
                borderRadius: BorderRadius.circular(KMetrics.pillRadius),
                border: Border.all(color: palette.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.pause_circle_outline_rounded,
                    size: 14,
                    color: palette.gold,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: KTypography.bodyFamily,
                      fontSize: KTypography.smallSize,
                      fontWeight: FontWeight.w500,
                      color: palette.tx,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: palette.line)),
        ],
      ),
    );
  }
}
