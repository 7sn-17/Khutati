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
    super.key,
  });

  final double progress;
  final String numeral;
  final String? caption;
  final Color? color;
  final double size;

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
                Text(
                  caption!,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KArtwork.ringCaptionSize * scale,
                    color: palette.mute,
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
  });

  final double progress;
  final Color trackColor;
  final Color valueColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / KArtwork.ringViewSize;
    final double radius = KArtwork.ringRadius * scale;
    final double stroke = KArtwork.ringStrokeWidth * scale;
    final Rect rect = Rect.fromCircle(center: size.center(Offset.zero), radius: radius);

    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawCircle(rect.center, radius, track);

    if (progress <= 0) return;

    final Paint value = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = valueColor;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, value);
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
class KEcgLine extends StatefulWidget {
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
  State<KEcgLine> createState() => _KEcgLineState();
}

class _KEcgLineState extends State<KEcgLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: 0,
        end: widget.progress.clamp(0.0, 1.0).toDouble(),
      ),
      duration: Duration(milliseconds: KMotion.ecgMs),
      curve: Curves.ease,
      builder: (BuildContext context, double value, Widget? child) {
        return Transform.flip(
          flipX: true,
          child: SizedBox(
            width: double.infinity,
            height: widget.height,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (BuildContext context, Widget? child) {
                return CustomPaint(
                  painter: _EcgPainter(
                    progress: value,
                    pulse: _pulse.value,
                    trackColor: palette.line,
                    valueColor: widget.color ?? palette.redtx,
                  ),
                );
              },
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
    required this.pulse,
    required this.trackColor,
    required this.valueColor,
  });

  final double progress;
  final double pulse;
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

      double totalLength = 0;
      final List<PathMetric> metrics = _path.computeMetrics().toList();
      for (final PathMetric metric in metrics) {
        totalLength += metric.length;
      }
      final double revealed = totalLength * progress;

      double drawn = 0;
      for (final PathMetric metric in metrics) {
        if (drawn >= revealed) break;
        final double take = (revealed - drawn).clamp(0.0, metric.length);
        if (take > 0) {
          canvas.drawPath(metric.extractPath(0, take), reveal);
        }
        drawn += metric.length;
      }

      // Lightweight moving pulse along the revealed portion.
      if (revealed > 0) {
        final double pulsePos = revealed * pulse;
        double acc = 0;
        for (final PathMetric metric in metrics) {
          if (acc + metric.length < pulsePos) {
            acc += metric.length;
            continue;
          }
          final double local = (pulsePos - acc).clamp(0.0, metric.length);
          final Paint glow = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = KArtwork.ecgStrokeWidth * 2.2
            ..strokeCap = StrokeCap.round
            ..color = valueColor.withValues(alpha: 0.55);
          final double start = (local - 12).clamp(0.0, metric.length);
          final double end = (local + 12).clamp(0.0, metric.length);
          if (end > start) {
            canvas.drawPath(metric.extractPath(start, end), glow);
          }
          break;
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EcgPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulse != pulse ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.valueColor != valueColor;
  }
}
