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
    duration: const Duration(milliseconds: 5000),
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
    // Strict bounds: the waveform must never escape its container.
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final double scale = math.min(
      size.width / KArtwork.ecgViewWidth,
      size.height / KArtwork.ecgViewHeight,
    );
    final double tileWidth = KArtwork.ecgViewWidth * scale;
    final double tileHeight = KArtwork.ecgViewHeight * scale;
    final double dy = (size.height - tileHeight) / 2;

    // Sweep head travels left-to-right over the full duration.
    final double headX = pulse * size.width;
    // Trail length behind the head (the part still visible).
    final double trail = size.width * 0.34;

    // Faint phosphor track across the whole width (static structure).
    final Paint trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = KArtwork.ecgStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = trackColor.withValues(alpha: 0.18);

    canvas.save();
    canvas.translate(0, dy);
    canvas.scale(scale);
    final int trackTiles = (size.width / tileWidth).ceil() + 2;
    for (int i = -1; i < trackTiles; i++) {
      canvas.save();
      canvas.translate(i * KArtwork.ecgViewWidth, 0);
      canvas.drawPath(_path, trackPaint);
      canvas.restore();
    }
    canvas.restore();

    // Sweep: draw the waveform only within the trail behind the head, with a
    // smooth fade from the head backwards (comet tail). Distance behind head
    // wraps around the container so the loop is seamless.
    final Paint valuePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = KArtwork.ecgStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = valueColor;

    final int tileCount = (size.width / tileWidth).ceil() + 2;
    const double chunk = 6.0; // view units per segment
    for (int t = -1; t < tileCount; t++) {
      canvas.save();
      canvas.translate(t * tileWidth, dy);
      canvas.scale(scale);
      for (final PathMetric metric in _path.computeMetrics()) {
        double s = 0;
        while (s < metric.length) {
          final double e = (s + chunk).clamp(0.0, metric.length);
          final double midView = (s + e) / 2;
          final double midCanvas = t * tileWidth + midView * scale;
          // Distance behind the head, wrapped.
          double d = headX - midCanvas;
          if (d < 0) d += size.width;
          if (d <= trail) {
            final double tt = (d / trail).clamp(0.0, 1.0);
            // smoothstep fade: full at the head, zero at the trail end.
            final double fade = 1.0 - (tt * tt * (3 - 2 * tt));
            valuePaint.color = valueColor.withValues(alpha: fade);
            canvas.drawPath(metric.extractPath(s, e), valuePaint);
          }
          s = e;
        }
      }
      canvas.restore();
    }

    // Premium glowing sweep head (vertical line + soft glow).
    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = KArtwork.ecgStrokeWidth * 4
      ..strokeCap = StrokeCap.round
      ..color = valueColor.withValues(alpha: 0.22);
    final Paint headPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = KArtwork.ecgStrokeWidth * 1.6
      ..strokeCap = StrokeCap.round
      ..color = valueColor;
    canvas.drawLine(
      Offset(headX, dy),
      Offset(headX, dy + tileHeight),
      glowPaint,
    );
    canvas.drawLine(
      Offset(headX, dy),
      Offset(headX, dy + tileHeight),
      headPaint,
    );

    canvas.restore(); // bounds clip
  }

  @override
  bool shouldRepaint(covariant _EcgPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulse != pulse ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.valueColor != valueColor;
  }
}
