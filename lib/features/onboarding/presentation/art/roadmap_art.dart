import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'onboarding_art.dart';

/// Slide 1 — the 68-day roadmap: a winding road rising to a red flag.
class RoadmapArt extends StatelessWidget {
  const RoadmapArt({required this.enter, required this.loop, super.key});

  final Animation<double> enter;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const RepaintBoundary(child: CustomPaint(painter: _RoadmapHills())),
        RepaintBoundary(
          child: CustomPaint(painter: _RoadmapPainter(enter, loop)),
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
  _RoadmapPainter(this.enter, this.loop)
    : super(repaint: Listenable.merge(<Listenable>[enter, loop]));

  final Animation<double> enter;
  final Animation<double> loop;

  /// The road exactly as drawn in the prototype's SVG.
  static final Path _road = Path()
    ..moveTo(70, 430)
    ..cubicTo(200, 430, 250, 370, 200, 330)
    ..cubicTo(150, 292, 80, 285, 100, 240)
    ..cubicTo(118, 192, 250, 215, 265, 165)
    ..cubicTo(275, 132, 285, 118, 300, 100);

  static final List<_Node> _nodes = <_Node>[
    _Node(const Offset(133, 424), KOnboarding.blue, 0.50),
    _Node(const Offset(217, 351), KOnboarding.teal, 0.60),
    _Node(const Offset(114, 281), KOnboarding.pink, 0.68),
    _Node(const Offset(165, 207), KOnboarding.gold, 0.76),
    _Node(const Offset(265, 165), KOnboarding.redSoft, 0.84),
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
    final double t = enter.value;
    final double l = loop.value;

    final ui.PathMetric metric = _road.computeMetrics().first;
    final double reveal = Curves.easeOutCubic.transform(segment(t, 0, 0.62));
    final Path visible = metric.extractPath(0, metric.length * reveal);

    // The road itself: a thick rounded stroke, revealed from the start.
    canvas.drawPath(
      visible,
      Paint()
        ..color = KOnboarding.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 32
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dashed centre line, drawn once the road is mostly there.
    final double dashAlpha = segment(t, 0.5, 0.72);
    if (dashAlpha > 0) {
      canvas.drawPath(
        dashPath(
          metric.extractPath(0, metric.length * reveal),
          dash: 1,
          gap: 11,
        ),
        Paint()
          ..color = KOnboarding.ink.withValues(alpha: 0.3 * dashAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    for (final _Node node in _nodes) {
      final double pop = elastic(segment(t, node.delay, node.delay + 0.14));
      if (pop <= 0) continue;
      _paintNode(canvas, node, pop, l);
    }

    _paintFlag(canvas, t, l);

    // The travelling light follows the road forever.
    final double orbit = segment(t, 0.7, 0.85) * l;
    if (t > 0.7) {
      final ui.Tangent? tangent = metric.getTangentForOffset(
        metric.length * orbit,
      );
      if (tangent != null) {
        final double fade = (math.sin(math.pi * orbit) * 1.6)
            .clamp(0.0, 1.0)
            .toDouble();
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
    }

    _paintSparks(canvas, t, l);
    canvas.restore();
  }

  void _paintNode(Canvas canvas, _Node node, double pop, double loopValue) {
    canvas.save();
    canvas.translate(node.position.dx, node.position.dy);

    // Expanding halo, phase-shifted per node so they never pulse in unison.
    final double pulse = (loopValue * 1.6 + node.delay) % 1;
    canvas.drawCircle(
      Offset.zero,
      17 * (1 + 0.9 * pulse),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = node.color.withValues(alpha: 0.55 * (1 - pulse) * pop),
    );

    canvas.scale(pop);
    canvas.drawCircle(Offset.zero, 17, Paint()..color = KOnboarding.bg);
    canvas.drawCircle(
      Offset.zero,
      17,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = node.color,
    );
    canvas.drawCircle(Offset.zero, 6.5, Paint()..color = node.color);
    canvas.restore();
  }

  void _paintFlag(Canvas canvas, double t, double loopValue) {
    final double pole = Curves.easeOutCubic.transform(segment(t, 0.74, 0.9));
    if (pole > 0) {
      final double bottom = 102;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(298, bottom - 62 * pole, 4, 62 * pole),
          const Radius.circular(2),
        ),
        Paint()..color = KOnboarding.ink,
      );
    }

    final double banner = elastic(segment(t, 0.8, 0.96));
    if (banner <= 0) return;
    canvas.save();
    canvas.translate(302, 58);
    // A slow horizontal "wave" so the flag reads as cloth, not a sticker.
    canvas.scale(0.92 + 0.08 * math.sin(loopValue * math.pi * 2), banner);
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

  static const List<_Spark> _sparks = <_Spark>[
    _Spark(Offset(60, 110), 1, KOnboarding.gold, 0),
    _Spark(Offset(340, 230), 0.7, KOnboarding.blue, 0.33),
    _Spark(Offset(46, 330), 0.6, KOnboarding.ink, 0.66),
  ];

  void _paintSparks(Canvas canvas, double t, double l) {
    final double alpha = segment(t, 0.1, 0.4);
    if (alpha <= 0) return;

    for (final _Spark spark in _sparks) {
      final double bob =
          math.sin((l + spark.phase) * math.pi * 2) * 8 * spark.scale;
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
      oldDelegate.enter != enter || oldDelegate.loop != loop;
}

class _Node {
  const _Node(this.position, this.color, this.delay);

  final Offset position;
  final Color color;
  final double delay;
}

class _Spark {
  const _Spark(this.position, this.scale, this.color, this.phase);

  final Offset position;
  final double scale;
  final Color color;
  final double phase;
}
