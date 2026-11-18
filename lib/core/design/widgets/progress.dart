import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../svg_path.dart';
import '../palette.dart';
import '../tokens.dart';

/// The focus ring: 240x240, r=104, 10px stroke, round cap, starting at -90°.
///
/// [progress] is the *visible* fraction of the circle, matching the prototype's
/// `stroke-dashoffset = 653 * (1 - rest/dur)` — a full ring means "no time
/// elapsed yet" and the arc shrinks as the session runs.
class KProgressRing extends StatelessWidget {
  const KProgressRing({
    required this.progress,
    required this.numeral,
    this.caption,
    this.color,
    this.size = KMetrics.ringSize,
    this.arcDegrees = 360,
    this.glow = false,
    super.key,
  });

  final double progress;
  final String numeral;
  final String? caption;
  final Color? color;
  final double size;
  /// Sweep of the open arc. 360 draws a full circle; ~270 draws the premium
  /// focus arc with a gap at the bottom.
  final double arcDegrees;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final double scale = size / KArtwork.ringViewSize;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0).toDouble()),
            duration: Duration(milliseconds: KMotion.ecgMs),
            curve: Curves.easeOutCubic,
            builder: (BuildContext context, double value, Widget? child) {
              return CustomPaint(
                size: Size.square(size),
                painter: _RingPainter(
                  progress: value,
                  trackColor: palette.line,
                  valueColor: color ?? palette.redtx,
                  arcDegrees: arcDegrees,
                  glow: glow,
                ),
              );
            },
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                numeral,
                style: TextStyle(
                  fontFamily: KTypography.displayFamily,
                  fontSize: KArtwork.ringNumeralSize * scale,
                  fontWeight: FontWeight.w700,
                  color: palette.tx,
                  height: 1.1,
                ),
              ),
              if (caption != null)
                SizedBox(
                  width: size * 0.72,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: KArtwork.ringCaptionSize * scale,
                        color: palette.mute,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.valueColor,
    this.arcDegrees = 360,
    this.glow = false,
  });

  final double progress;
  final Color trackColor;
  final Color valueColor;
  final double arcDegrees;
  final bool glow;

  double get _startAngle {
    if (arcDegrees >= 359.9) return -math.pi / 2;
    final double arc = arcDegrees * math.pi / 180.0;
    return 3 * math.pi / 2 - arc / 2;
  }

  double get _sweepAngle =>
      (arcDegrees >= 359.9 ? 2 * math.pi : arcDegrees * math.pi / 180.0);

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / KArtwork.ringViewSize;
    final double radius = KArtwork.ringRadius * scale;
    final double stroke = KArtwork.ringStrokeWidth * scale;
    final Rect rect = Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
    final double start = _startAngle;
    final double sweep = _sweepAngle;

    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor.withValues(alpha: 0.55);
    canvas.drawArc(rect, start, sweep, false, track);

    if (progress <= 0) return;

    final double valueSweep = sweep * progress.clamp(0.0, 1.0);
    if (glow) {
      final Paint glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 1.9
        ..strokeCap = StrokeCap.round
        ..color = valueColor.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawArc(rect, start, valueSweep, false, glowPaint);
    }
    final Paint value = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: start,
        endAngle: start + sweep,
        colors: <Color>[
          valueColor.withValues(alpha: 0.55),
          valueColor,
          Colors.white.withValues(alpha: 0.95),
          valueColor,
        ],
        stops: const <double>[0.0, 0.45, 0.7, 1.0],
      ).createShader(rect);
    canvas.drawArc(rect, start, valueSweep, false, value);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.valueColor != valueColor;
  }
}

/// The daily-progress ECG trace from the Today screen.
///
/// The path is the prototype's own `d` attribute; [progress] (0..1) reveals it
/// progressively, mirroring `stroke-dashoffset: 100 -> 0` over 600ms. The whole
/// trace is mirrored horizontally, as `transform: scaleX(-1)` does in the HTML.
class KEcgLine extends StatelessWidget {
  const KEcgLine({
    required this.progress,
    this.color,
    this.height = KMetrics.ecgHeight,
    super.key,
  });

  final double progress;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0).toDouble()),
      duration: Duration(milliseconds: KMotion.ecgMs),
      curve: Curves.ease,
      builder: (BuildContext context, double value, Widget? child) {
        return Transform.flip(
          flipX: true,
          child: SizedBox(
            width: double.infinity,
            height: height,
            child: CustomPaint(
              painter: _EcgPainter(
                progress: value,
                trackColor: palette.line,
                valueColor: color ?? palette.redtx,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EcgPainter extends CustomPainter {
  const _EcgPainter({
    required this.progress,
    required this.trackColor,
    required this.valueColor,
  });

  final double progress;
  final Color trackColor;
  final Color valueColor;

  static final Path _path = parseSvgPath(KArtwork.ecgPath);

  @override
  void paint(Canvas canvas, Size size) {
    // The SVG uses preserveAspectRatio="xMidYMid meet": uniform scale, centred.
    final double scale = math.min(
      size.width / KArtwork.ecgViewWidth,
      size.height / KArtwork.ecgViewHeight,
    );
    final double dx = (size.width - KArtwork.ecgViewWidth * scale) / 2;
    final double dy = (size.height - KArtwork.ecgViewHeight * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = KArtwork.ecgStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = trackColor;
    canvas.drawPath(_path, base);

    if (progress > 0) {
      final Paint reveal = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = KArtwork.ecgStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = valueColor;

      for (final PathMetric metric in _path.computeMetrics()) {
        final double length = metric.length * progress;
        if (length <= 0) continue;
        canvas.drawPath(metric.extractPath(0, length), reveal);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EcgPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.valueColor != valueColor;
  }
}
