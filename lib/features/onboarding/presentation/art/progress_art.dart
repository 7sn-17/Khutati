import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'onboarding_art.dart';

/// Slide 3 — visible progress: a growing bar chart, a rising trend line and a
/// star that keeps sparkling.
///
/// The bars are the entrance (0.3 s apart, 1.6 s each). The trend line, the
/// star and the particles are a 12 s loop, exactly as in the prototype: the line
/// draws for 6 s, holds, then fades; the star bursts at 48 % and fades at 88 %.
class ProgressArt extends StatelessWidget {
  const ProgressArt({required this.enter, required this.ambient, super.key});

  final Animation<double> enter;
  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const RepaintBoundary(child: CustomPaint(painter: _ProgressHills())),
        RepaintBoundary(
          child: CustomPaint(painter: _ProgressPainter(enter, ambient)),
        ),
      ],
    );
  }
}

class _ProgressHills extends CustomPainter {
  const _ProgressHills();

  @override
  void paint(Canvas canvas, Size size) {
    HillsPainter(
      backPath: _back,
      frontPath: _front,
      glow: KOnboarding.gold,
      glowCenter: const Offset(70, 130),
      glowRadius: 280,
    ).paint(canvas, size);
  }

  static final Path _back = Path()
    ..moveTo(-400, -3000)
    ..lineTo(790, -3000)
    ..lineTo(790, 515)
    ..lineTo(390, 515)
    ..quadraticBezierTo(367, 465, 335, 515)
    ..quadraticBezierTo(303, 565, 270, 515)
    ..quadraticBezierTo(237, 465, 205, 515)
    ..quadraticBezierTo(173, 565, 140, 515)
    ..quadraticBezierTo(107, 465, 75, 515)
    ..quadraticBezierTo(43, 565, 10, 515)
    ..lineTo(-400, 515)
    ..close();

  static final Path _front = Path()
    ..moveTo(-400, -3000)
    ..lineTo(790, -3000)
    ..lineTo(790, 480)
    ..lineTo(390, 480)
    ..quadraticBezierTo(357, 430, 325, 480)
    ..quadraticBezierTo(293, 530, 260, 480)
    ..quadraticBezierTo(227, 430, 195, 480)
    ..quadraticBezierTo(163, 530, 130, 480)
    ..quadraticBezierTo(97, 430, 65, 480)
    ..quadraticBezierTo(33, 530, 0, 480)
    ..lineTo(-400, 480)
    ..close();

  @override
  bool shouldRepaint(covariant _ProgressHills oldDelegate) => false;
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter(this.enter, this.ambient)
    : super(repaint: Listenable.merge(<Listenable>[enter, ambient]));

  final Animation<double> enter;
  final Animation<double> ambient;

  static final Path _trend = Path()
    ..moveTo(356, 352)
    ..cubicTo(340.7, 345.3, 290, 325.3, 264, 312)
    ..cubicTo(238, 298.7, 221.3, 286.3, 200, 272)
    ..cubicTo(178.7, 257.7, 154, 243, 136, 226)
    ..cubicTo(118, 209, 99.3, 179.3, 92, 170);

  static final Path _arrow = Path()
    ..moveTo(17, 0)
    ..lineTo(-8, -13)
    ..lineTo(-2, 0)
    ..lineTo(-8, 13)
    ..close();

  static const List<_Bar> _bars = <_Bar>[
    _Bar(300, 50, KOnboarding.blue, 0.30),
    _Bar(236, 90, KOnboarding.teal, 0.66),
    _Bar(172, 130, KOnboarding.pink, 1.02),
    _Bar(108, 170, KOnboarding.redSoft, 1.38),
    _Bar(44, 210, KOnboarding.gold, 1.74),
  ];

  /// The eight particles around the star, as `--x`/`--y` in the prototype.
  static const List<Offset> _particles = <Offset>[
    Offset(0, -58),
    Offset(40, -40),
    Offset(58, 0),
    Offset(40, 40),
    Offset(0, 58),
    Offset(-40, 40),
    Offset(-58, 0),
    Offset(-40, -40),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    enterDesignSpace(canvas, size);
    final double t = enter.value * kEnterSeconds;
    final double a = ambient.value * kAmbientSeconds;

    _paintGrid(canvas, t);
    for (final _Bar bar in _bars) {
      _paintBar(canvas, bar, t);
    }
    _paintTrend(canvas, a);
    _paintEndpoint(canvas, t);
    _paintStar(canvas, a);
    canvas.restore();
  }

  void _paintGrid(Canvas canvas, double t) {
    final double alpha = Curves.easeOut.transform(
      stage(t, delay: 0, duration: 0.6),
    );
    if (alpha <= 0) return;
    final Paint paint = Paint()
      ..strokeWidth = 1
      ..color = KOnboarding.line.withValues(alpha: 0.5 * alpha);
    for (final double y in <double>[200, 260, 320, 380]) {
      canvas.drawPath(
        dashPath(
          Path()
            ..moveTo(-400, y)
            ..lineTo(790, y),
          dash: 3,
          gap: 8,
        ),
        paint,
      );
    }
  }

  void _paintBar(Canvas canvas, _Bar bar, double t) {
    // `.gr` — 1.6 s, scaleY from the baseline, staggered 0.36 s apart.
    final double grow = kGrowCurve.transform(
      stage(t, delay: bar.delay, duration: 1.6),
    );
    if (grow <= 0) return;

    final double height = bar.height * grow;
    final Rect body = Rect.fromLTWH(bar.x, 430 - height, 56, height);
    final RRect rounded = RRect.fromRectAndRadius(
      body,
      const Radius.circular(10),
    );

    canvas.drawRRect(rounded, Paint()..color = KOnboarding.hillBack);
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = KOnboarding.line,
    );

    // The coloured cap rides on top of the bar as it grows.
    canvas.save();
    canvas.clipRRect(rounded);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bar.x, 430 - height, 56, 12),
        const Radius.circular(6),
      ),
      Paint()..color = bar.color,
    );
    canvas.restore();
  }

  /// `.ln` — a 12 s cycle: draw over 6 s, hold to 88 %, fade out.
  void _paintTrend(Canvas canvas, double a) {
    final double p = cycle(a, period: 12);
    final double reveal = p < 0.5 ? p / 0.5 : 1.0;
    final double alpha = p < 0.88 ? 1.0 : ((1 - p) / 0.12).clamp(0.0, 1.0);
    if (reveal <= 0 || alpha <= 0) return;

    final ui.PathMetric metric = _trend.computeMetrics().first;
    final Path visible = metric.extractPath(0, metric.length * reveal);

    canvas.drawPath(
      visible,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = KOnboarding.redSoft.withValues(alpha: 0.22 * alpha),
    );
    canvas.drawPath(
      visible,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = ui.Gradient.linear(
          const Offset(356, 352),
          const Offset(92, 170),
          <Color>[
            KOnboarding.redSoft.withValues(alpha: alpha),
            KOnboarding.gold.withValues(alpha: alpha),
          ],
        ),
    );

    // The arrow only exists once the line has been drawn.
    if (p <= 0.52) return;
    final double travel = ((p - 0.52) / 0.4).clamp(0.0, 1.0);
    final ui.Tangent? tangent = metric.getTangentForOffset(
      metric.length * travel,
    );
    if (tangent == null) return;
    final double fade = math.min(1.0, (p - 0.52) * 14) * alpha;
    canvas.save();
    canvas.translate(tangent.position.dx, tangent.position.dy);
    canvas.rotate(tangent.angle);
    canvas.drawPath(
      _arrow,
      Paint()..color = KOnboarding.gold.withValues(alpha: fade),
    );
    canvas.restore();
  }

  /// `.pp` — the dot at the head of the line, at 5.2 s.
  void _paintEndpoint(Canvas canvas, double t) {
    final double pop = kPopCurve.transform(stage(t, delay: 5.2, duration: 1.2));
    if (pop <= 0) return;
    canvas.save();
    canvas.translate(356, 352);
    canvas.scale(pop);
    canvas.drawCircle(Offset.zero, 7, Paint()..color = KOnboarding.redSoft);
    canvas.restore();
  }

  /// `.st` and `.pt` — a 12 s burst: the star scales in at 48 %, overshoots to
  /// 1.3 at 58 %, settles by 66 % and fades out after 88 %; the particles fly
  /// outward between 56 % and 82 %.
  void _paintStar(Canvas canvas, double a) {
    final double p = cycle(a, period: 12);

    final double scale;
    if (p <= 0.48) {
      scale = 0;
    } else if (p <= 0.58) {
      scale = 1.3 * (p - 0.48) / 0.10;
    } else if (p <= 0.66) {
      scale = 1.3 - 0.3 * (p - 0.58) / 0.08;
    } else {
      scale = 1;
    }
    final double opacity = p <= 0.88 ? 1 : (1 - (p - 0.88) / 0.12);

    canvas.save();
    canvas.translate(62, 128);

    if (scale > 0) {
      canvas.drawCircle(
        Offset.zero,
        46,
        Paint()..color = KOnboarding.gold.withValues(alpha: 0.14 * opacity),
      );
      canvas.save();
      canvas.scale(scale);
      canvas.drawPath(
        starPath(),
        Paint()..color = KOnboarding.gold.withValues(alpha: opacity),
      );
      canvas.restore();
    }

    if (p > 0.50 && p < 0.82) {
      final double fly = ((p - 0.50) / 0.32).clamp(0.0, 1.0);
      final double dotScale = p < 0.56 ? (p - 0.50) / 0.06 : 1 - 0.5 * fly;
      final double dotAlpha = p < 0.56 ? 1.0 : 1 - fly;
      for (int i = 0; i < _particles.length; i++) {
        final Offset target = _particles[i];
        canvas.drawCircle(
          target * fly,
          4 * dotScale,
          Paint()
            ..color = (i.isEven ? KOnboarding.gold : KOnboarding.ink)
                .withValues(alpha: 0.8 * dotAlpha),
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ProgressPainter oldDelegate) =>
      oldDelegate.enter != enter || oldDelegate.ambient != ambient;
}

class _Bar {
  const _Bar(this.x, this.height, this.color, this.delay);

  final double x;
  final double height;
  final Color color;

  /// Seconds before the bar starts growing.
  final double delay;
}
