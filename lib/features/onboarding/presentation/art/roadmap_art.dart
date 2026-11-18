import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'onboarding_art.dart';

/// Slide 1 — the 68-day roadmap: a winding road rising to a red flag.
///
/// Timings are the prototype's, in seconds: the road draws over 3.2 s starting
/// at 0.4 s, the five nodes pop at 2.0/2.6/3.2/3.8/4.4, the pole grows at 3.8,
/// the banner lands at 4.6 and the travelling light joins at 5.6.
class RoadmapArt extends StatelessWidget {
  const RoadmapArt({required this.enter, required this.ambient, super.key});

  final Animation<double> enter;
  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const RepaintBoundary(child: CustomPaint(painter: _RoadmapHills())),
        RepaintBoundary(
          child: CustomPaint(painter: _RoadmapPainter(enter, ambient)),
        ),
      ],
    );
  }
}

class _RoadmapHills extends CustomPainter {
  const _RoadmapHills();

  @override
  void paint(Canvas canvas, Size size) {
    HillsPainter(
      backPath: _back,
      frontPath: _front,
      glow: KOnboarding.blue,
      glowCenter: const Offset(300, 120),
      glowRadius: 280,
    ).paint(canvas, size);
  }

  static final Path _back = Path()
    ..moveTo(-400, -3000)
    ..lineTo(790, -3000)
    ..lineTo(790, 470)
    ..lineTo(390, 470)
    ..quadraticBezierTo(195, 585, 0, 470)
    ..lineTo(-400, 470)
    ..close();

  static final Path _front = Path()
    ..moveTo(-400, -3000)
    ..lineTo(790, -3000)
    ..lineTo(790, 430)
    ..lineTo(390, 430)
    ..quadraticBezierTo(195, 545, 0, 430)
    ..lineTo(-400, 430)
    ..close();

  @override
  bool shouldRepaint(covariant _RoadmapHills oldDelegate) => false;
}

class _RoadmapPainter extends CustomPainter {
  _RoadmapPainter(this.enter, this.ambient)
    : super(repaint: Listenable.merge(<Listenable>[enter, ambient]));

  final Animation<double> enter;
  final Animation<double> ambient;

  /// The road exactly as drawn in the prototype's SVG.
  static final Path _road = Path()
    ..moveTo(70, 430)
    ..cubicTo(200, 430, 250, 370, 200, 330)
    ..cubicTo(150, 292, 80, 285, 100, 240)
    ..cubicTo(118, 192, 250, 215, 265, 165)
    ..cubicTo(275, 132, 285, 118, 300, 100);

  static const List<_Node> _nodes = <_Node>[
    _Node(Offset(133, 424), KOnboarding.blue, 2.0, 4.8),
    _Node(Offset(217, 351), KOnboarding.teal, 2.6, 5.8),
    _Node(Offset(114, 281), KOnboarding.pink, 3.2, 6.8),
    _Node(Offset(165, 207), KOnboarding.gold, 3.8, 7.8),
    _Node(Offset(265, 165), KOnboarding.redSoft, 4.4, 8.8),
  ];

  static const List<_Spark> _sparks = <_Spark>[
    _Spark(Offset(60, 110), 1, KOnboarding.gold, 0),
    _Spark(Offset(340, 230), 0.7, KOnboarding.blue, 2.6),
    _Spark(Offset(46, 330), 0.6, KOnboarding.ink, 4),
  ];

  static final Path _banner = Path()
    ..moveTo(302, 42)
    ..lineTo(348, 42)
    ..lineTo(337, 58)
    ..lineTo(348, 74)
    ..lineTo(302, 74)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    enterDesignSpace(canvas, size);
    final double t = enter.value * kEnterSeconds;
    final double a = ambient.value * kAmbientSeconds;

    final ui.PathMetric metric = _road.computeMetrics().first;
    final double draw = Curves.easeOut.transform(
      stage(t, delay: 0.4, duration: 3.2),
    );
    final Path visible = metric.extractPath(0, metric.length * draw);

    // The road itself: a thick rounded stroke, revealed from the start.
    if (draw > 0) {
      canvas.drawPath(
        visible,
        Paint()
          ..color = KOnboarding.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 32
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      // Dashed centre line, riding the same reveal so it cannot appear before
      // the road it belongs to.
      canvas.drawPath(
        dashPath(visible, dash: 1, gap: 11),
        Paint()
          ..color = KOnboarding.ink.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    for (final _Node node in _nodes) {
      final double ring = kPopCurve.transform(
        stage(t, delay: node.delay, duration: 1.2),
      );
      final double dot = kPopCurve.transform(
        stage(t, delay: node.delay + 0.3, duration: 1.2),
      );
      _paintNode(canvas, node, ring, dot, a);
    }

    _paintFlag(canvas, t, a);
    _paintLight(canvas, metric, a);
    _paintSparks(canvas, t, a);
    canvas.restore();
  }

  void _paintNode(
    Canvas canvas,
    _Node node,
    double ring,
    double dot,
    double a,
  ) {
    canvas.save();
    canvas.translate(node.position.dx, node.position.dy);

    // A 5 s halo that starts only after this node's own delay, so the five
    // never pulse in unison.
    if (a >= node.pulse) {
      final double p = Curves.easeOut.transform(
        cycle(a, period: 5, delay: node.pulse),
      );
      canvas.drawCircle(
        Offset.zero,
        17 * (1 + 0.9 * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = node.color.withValues(alpha: 0.55 * (1 - p)),
      );
    }

    if (ring > 0) {
      canvas.save();
      canvas.scale(ring);
      canvas.drawCircle(Offset.zero, 17, Paint()..color = KOnboarding.bg);
      canvas.drawCircle(
        Offset.zero,
        17,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..color = node.color,
      );
      canvas.restore();
    }

    if (dot > 0) {
      canvas.save();
      canvas.scale(dot);
      canvas.drawCircle(Offset.zero, 6.5, Paint()..color = node.color);
      canvas.restore();
    }
    canvas.restore();
  }

  void _paintFlag(Canvas canvas, double t, double a) {
    final double pole = kGrowCurve.transform(
      stage(t, delay: 3.8, duration: 1.6),
    );
    if (pole > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(298, 102 - 62 * pole, 4, 62 * pole),
          const Radius.circular(2),
        ),
        Paint()..color = KOnboarding.ink,
      );
    }

    final double banner = kPopCurve.transform(
      stage(t, delay: 4.6, duration: 1.2),
    );
    if (banner <= 0) return;

    // `.wv` is a 4.6 s ease-in-out scaleX between 1 and 0.8, pivoting on the
    // banner's start edge.
    final double wave =
        1 -
        0.2 * (1 - math.cos(delayedCycle(a, period: 4.6) * math.pi * 2)) / 2;

    canvas.save();
    canvas.translate(302, 58);
    canvas.scale(wave, banner);
    canvas.translate(-302, -58);
    canvas.drawPath(_banner, Paint()..color = KOnboarding.red);
    paintText(
      canvas,
      '68',
      at: const Offset(323, 47),
      size: 19,
      color: Colors.white,
      weight: FontWeight.w700,
      family: 'Reem Kufi',
      ltr: true,
    );
    canvas.restore();
  }

  /// The gold light that runs the road forever, after a 5.6 s delay, on a 14 s
  /// cycle.
  void _paintLight(Canvas canvas, ui.PathMetric metric, double a) {
    const double begin = 5.6;
    if (a < begin) return;
    final double p = cycle(a, period: 14, delay: begin);
    final ui.Tangent? tangent = metric.getTangentForOffset(metric.length * p);
    if (tangent == null) return;

    // No hard cut-in at the start of the path: fade over the first and last
    // tenth of the lap.
    final double fade = math.min(1.0, math.min(p * 10, (1 - p) * 10));
    canvas.drawCircle(
      tangent.position,
      13,
      Paint()..color = KOnboarding.gold.withValues(alpha: 0.25 * fade),
    );
    canvas.drawCircle(
      tangent.position,
      5,
      Paint()..color = KOnboarding.ink.withValues(alpha: fade),
    );
  }

  void _paintSparks(Canvas canvas, double t, double a) {
    // The stars fade in with the road and then float on a 7 s cycle.
    final double alpha = Curves.easeOut.transform(
      stage(t, delay: 0.1, duration: 1.2),
    );
    if (alpha <= 0) return;

    for (final _Spark spark in _sparks) {
      final double p = delayedCycle(a, period: 7, delay: spark.delay);
      final double bob = -8 * (1 - math.cos(p * math.pi * 2)) / 2 * spark.scale;
      canvas.save();
      canvas.translate(spark.position.dx, spark.position.dy + bob);
      canvas.scale(spark.scale);
      canvas.drawPath(
        sparklePath(12),
        Paint()..color = spark.color.withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RoadmapPainter oldDelegate) =>
      oldDelegate.enter != enter || oldDelegate.ambient != ambient;
}

class _Node {
  const _Node(this.position, this.color, this.delay, this.pulse);

  final Offset position;
  final Color color;

  /// Seconds before the node pops.
  final double delay;

  /// Seconds before the halo starts pulsing.
  final double pulse;
}

class _Spark {
  const _Spark(this.position, this.scale, this.color, this.delay);

  final Offset position;
  final double scale;
  final Color color;
  final double delay;
}
