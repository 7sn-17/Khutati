import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../svg_path.dart';
import '../palette.dart';
import '../tokens.dart';

/// The focus ring / arc timer.
///
/// With the defaults it is the prototype's full 240dp circle (r=104, 10px
/// stroke, round caps). The focus screen asks for [arcDegrees] 270 so the ring
/// opens at the bottom, and for [gradientColors] so the stroke is one seamless
/// gold → deep-orange sweep instead of a flat colour.
///
/// [progress] is the *visible* fraction of the arc: 1 means "no time elapsed
/// yet" and the arc shrinks as the session runs, matching the prototype's
/// `stroke-dashoffset` behaviour.
class KProgressRing extends StatelessWidget {
  const KProgressRing({
    required this.progress,
    required this.numeral,
    this.caption,
    this.color,
    this.size = KMetrics.ringSize,
    this.arcDegrees = 360,
    this.glow = false,
    this.gradientColors,
    this.strokeWidth,
    super.key,
  });

  final double progress;
  final String numeral;
  final String? caption;
  final Color? color;
  final double size;

  /// Sweep of the open arc. 360 draws a full circle; ~270 leaves a gap at the
  /// bottom, which is the premium focus shape.
  final double arcDegrees;

  /// Adds the soft halo and the glowing head at the tip of the arc.
  final bool glow;

  /// When provided (two or more colours) the stroke is painted with a smooth
  /// sweep gradient. Without it the stroke stays a solid [color].
  final List<Color>? gradientColors;

  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final double scale = size / KArtwork.ringViewSize;
    final Color valueColor = color ?? palette.redtx;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 0,
              end: progress.clamp(0.0, 1.0).toDouble(),
            ),
            duration: reduceMotion
                ? Duration.zero
                : Duration(milliseconds: KMotion.ecgMs),
            curve: Curves.easeOutCubic,
            builder: (BuildContext context, double value, Widget? child) {
              return CustomPaint(
                size: Size.square(size),
                painter: _ArcPainter(
                  progress: value,
                  trackColor: palette.line,
                  valueColor: valueColor,
                  arcDegrees: arcDegrees,
                  glow: glow && !reduceMotion,
                  gradientColors: gradientColors,
                  strokeWidth: strokeWidth,
                ),
              );
            },
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                numeral,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontFamily: KTypography.displayFamily,
                  fontSize: KArtwork.ringNumeralSize * scale,
                  fontWeight: FontWeight.w700,
                  color: palette.tx,
                  height: 1.1,
                ),
              ),
              if (caption != null && caption!.isNotEmpty)
                SizedBox(
                  width: size * 0.62,
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

class _ArcPainter extends CustomPainter {
  const _ArcPainter({
    required this.progress,
    required this.trackColor,
    required this.valueColor,
    required this.arcDegrees,
    required this.glow,
    this.gradientColors,
    this.strokeWidth,
  });

  final double progress;
  final Color trackColor;
  final Color valueColor;
  final double arcDegrees;
  final bool glow;
  final List<Color>? gradientColors;
  final double? strokeWidth;

  static const double _twoPi = math.pi * 2;

  bool get _isFullCircle => arcDegrees >= 359.9;

  double get _sweep =>
      _isFullCircle ? _twoPi : (arcDegrees.clamp(0.0, 360.0) * math.pi) / 180.0;

  /// Full circles start at the top; open arcs are centred on the top so the
  /// gap sits at the bottom.
  double get _start => _isFullCircle ? -math.pi / 2 : -math.pi / 2 - _sweep / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / KArtwork.ringViewSize;
    final double radius = KArtwork.ringRadius * scale;
    final double stroke = (strokeWidth ?? KArtwork.ringStrokeWidth) * scale;
    final Rect rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );

    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor.withValues(alpha: 0.55);
    canvas.drawArc(rect, _start, _sweep, false, track);

    final double visible = progress.clamp(0.0, 1.0);
    if (visible <= 0) return;
    final double valueSweep = _sweep * visible;

    final Shader? shader = _shader(rect);

    if (glow) {
      final Paint halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 1.9
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8)
        ..color = valueColor.withValues(alpha: 0.22);
      if (shader != null) {
        halo.shader = _shader(rect, alpha: 0.24);
      }
      canvas.drawArc(rect, _start, valueSweep, false, halo);
    }

    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = valueColor;
    if (shader != null) arc.shader = shader;
    canvas.drawArc(rect, _start, valueSweep, false, arc);

    if (!glow) return;

    // A small, soft head at the tip: it reads as light rather than a hard dot.
    final double tipAngle = _start + valueSweep;
    final Offset tip =
        rect.center +
        Offset(math.cos(tipAngle), math.sin(tipAngle)) * radius;
    final Color tipColor = _gradientColorAt(visible);
    canvas.drawCircle(
      tip,
      stroke * 0.85,
      Paint()
        ..color = tipColor.withValues(alpha: 0.85)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(
      tip,
      stroke * 0.42,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
  }

  /// Samples the same gradient the stroke uses, so the glowing head always
  /// matches the colour of the arc at its tip.
  Color _gradientColorAt(double t) {
    final List<Color>? colors = gradientColors;
    if (colors == null || colors.isEmpty) return valueColor;
    if (colors.length == 1) return colors.first;
    final double position = t.clamp(0.0, 1.0) * (colors.length - 1);
    final int index = position.floor().clamp(0, colors.length - 2);
    return Color.lerp(colors[index], colors[index + 1], position - index) ??
        colors[index];
  }

  /// Sweep gradient laid over the whole arc (not the visible part), so the
  /// colours stay anchored while the arc shrinks.
  Shader? _shader(Rect rect, {double alpha = 1}) {
    final List<Color>? colors = gradientColors;
    if (colors == null || colors.length < 2) return null;
    return SweepGradient(
      center: Alignment.center,
      startAngle: _start,
      endAngle: _start + _sweep,
      colors: <Color>[
        for (final Color color in colors)
          color.withValues(alpha: color.a * alpha),
      ],
      stops: _stops(colors.length),
    ).createShader(rect);
  }

  static List<double> _stops(int count) {
    if (count == 2) return const <double>[0.0, 1.0];
    return <double>[
      for (int i = 0; i < count; i++) i / (count - 1),
    ];
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.valueColor != valueColor ||
        oldDelegate.arcDegrees != arcDegrees ||
        oldDelegate.glow != glow ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gradientColors != gradientColors;
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
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0).toDouble()),
      duration: reduceMotion
          ? Duration.zero
          : Duration(milliseconds: KMotion.ecgMs),
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
