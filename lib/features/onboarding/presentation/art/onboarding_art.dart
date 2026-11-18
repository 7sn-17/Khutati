import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/design/svg_path.dart';
import '../../../../core/design/tokens.dart';

/// The onboarding scene palette, copied from `khutati-onboarding.html`.
///
/// The screen is always dark, independent of the app theme: the prototype
/// defines a single night-sky scene, and the first launch should feel the same
/// whether the user later picks light or dark.
abstract final class KOnboarding {
  static const Color bg = Color(0xFF0D1A2D);
  static const Color hillBack = Color(0xFF1C3150);
  static const Color hillFront = Color(0xFF15263F);
  static const Color line = Color(0xFF26395A);
  static const Color ink = Color(0xFFEAE5DA);
  static const Color mute = Color(0xFFA9B4C6);
  static const Color dim = Color(0xFF93A1B8);
  static const Color red = Color(0xFFB52A20);
  static const Color redSoft = Color(0xFFF0766B);
  static const Color gold = Color(0xFFE8B65A);
  static const Color blue = Color(0xFF6AA6FF);
  static const Color teal = Color(0xFF5DD6C0);
  static const Color pink = Color(0xFFF0A8C8);
  static const Color ok = Color(0xFF7CCBB0);
  static const Color shade = Color(0xFF741B16);

  /// Design canvas used by the HTML's `viewBox="0 0 390 540"`.
  static const double designWidth = 390;
  static const double designHeight = 540;
}

/// Scales the canvas into the 390x540 design space, anchored bottom-centre
/// (`preserveAspectRatio="xMidYMax meet"`).
///
/// Foreground art uses this; the background hills use a full-bleed stretch so
/// no device aspect ratio can expose an unpainted edge.
void enterDesignSpace(Canvas canvas, Size size) {
  final double scale = math.min(
    size.width / KOnboarding.designWidth,
    size.height / KOnboarding.designHeight,
  );
  canvas.translate(
    (size.width - KOnboarding.designWidth * scale) / 2,
    size.height - KOnboarding.designHeight * scale,
  );
  canvas.scale(scale);
}

/// The two curved hills, the glow and the hexagon texture behind every slide.
///
/// Static by design: it sits in its own [RepaintBoundary] and never repaints
/// while the foreground animates.
class HillsPainter extends CustomPainter {
  const HillsPainter({
    required this.backPath,
    required this.frontPath,
    required this.glow,
    required this.glowCenter,
    required this.glowRadius,
  });

  final Path backPath;
  final Path frontPath;
  final Color glow;
  final Offset glowCenter;
  final double glowRadius;

  static final Path _hexTile = parseSvgPath(KArtwork.hexPatternPath);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Stretch to the box: the hills are a backdrop, not an illustration, and
    // must reach every edge.
    canvas.scale(
      size.width / KOnboarding.designWidth,
      size.height / KOnboarding.designHeight,
    );

    canvas.drawPath(backPath, Paint()..color = KOnboarding.hillBack);
    canvas.drawPath(frontPath, Paint()..color = KOnboarding.hillFront);

    canvas.save();
    canvas.clipPath(frontPath);
    canvas.drawPath(
      frontPath,
      Paint()
        ..shader = ui.Gradient.radial(glowCenter, glowRadius, <Color>[
          glow.withValues(alpha: 0.32),
          glow.withValues(alpha: 0),
        ]),
    );

    // The prototype's `#fff` hexagon tile at 6% — lighter than the card
    // texture, which is grey at 20%.
    final Paint hexPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.06);
    for (
      double y = 0;
      y < KOnboarding.designHeight + KArtwork.hexTileHeight;
      y += KArtwork.hexTileHeight
    ) {
      for (
        double x = 0;
        x < KOnboarding.designWidth + KArtwork.hexTileWidth;
        x += KArtwork.hexTileWidth
      ) {
        canvas.save();
        canvas.translate(x, y);
        canvas.drawPath(_hexTile, hexPaint);
        canvas.restore();
      }
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  // One painter instance per slide, and the hills never change, so the
  // backdrop is rasterised once and left alone while the scene animates.
  bool shouldRepaint(covariant HillsPainter oldDelegate) => false;
}

/// A four-point sparkle: `M0-12Q1-1 12 0Q1 1 0 12Q-1 1-12 0Q-1-1 0-12z`.
Path sparklePath(double size) {
  final double s = size / 12;
  return Path()
    ..moveTo(0, -12 * s)
    ..quadraticBezierTo(1 * s, -1 * s, 12 * s, 0)
    ..quadraticBezierTo(1 * s, 1 * s, 0, 12 * s)
    ..quadraticBezierTo(-1 * s, 1 * s, -12 * s, 0)
    ..quadraticBezierTo(-1 * s, -1 * s, 0, -12 * s)
    ..close();
}

/// The ten-point star used on the last slide.
Path starPath({double outer = 30, double inner = 20}) {
  final Path path = Path();
  for (int i = 0; i < 10; i++) {
    final double radius = i.isEven ? outer : inner;
    final double angle = -math.pi / 2 + i * math.pi / 5;
    final Offset point = Offset(
      math.cos(angle) * radius,
      math.sin(angle) * radius,
    );
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  return path..close();
}

/// `Curves.elasticOut` overshoots below zero, which `Transform.scale` and
/// opacity cannot take; clamp it once so every caller stays safe.
double elastic(double t) =>
    Curves.elasticOut.transform(t.clamp(0.0, 1.0).toDouble());

/// Local progress of a sub-animation that starts at [start] and ends at [end]
/// of the master entrance timeline.
double segment(double t, double start, double end) {
  if (end <= start) return t >= end ? 1 : 0;
  return ((t - start) / (end - start)).clamp(0.0, 1.0).toDouble();
}

/// Dashes a path by sampling its metrics — Flutter has no dash pattern.
Path dashPath(Path source, {required double dash, required double gap}) {
  final Path result = Path();
  for (final ui.PathMetric metric in source.computeMetrics()) {
    double distance = 0;
    while (distance < metric.length) {
      final double next = math.min(distance + dash, metric.length);
      result.addPath(metric.extractPath(distance, next), Offset.zero);
      distance = next + gap;
    }
  }
  return result;
}

/// Paints Arabic (or numeric) text inside a canvas in the design space.
void paintText(
  Canvas canvas,
  String text, {
  required Offset at,
  required double size,
  required Color color,
  FontWeight weight = FontWeight.w400,
  String family = KTypography.bodyFamily,
  double? maxWidth,
  TextAlign align = TextAlign.center,
  bool ltr = false,
}) {
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.2,
      ),
    ),
    textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
    textAlign: align,
    maxLines: 1,
  )..layout(maxWidth: maxWidth ?? 300);

  final Offset origin = switch (align) {
    // `painter.width` is the layout constraint, not the ink width, so the
    // anchors use the longest line's intrinsic width instead.
    TextAlign.right => Offset(at.dx - painter.maxIntrinsicWidth, at.dy),
    TextAlign.left => at,
    _ => Offset(at.dx - painter.maxIntrinsicWidth / 2, at.dy),
  };
  painter.paint(canvas, origin);
}
