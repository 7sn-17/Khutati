import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'onboarding_art.dart';

/// Slide 3 — visible progress: a growing bar chart, a rising trend line and a
/// star that keeps sparkling.
class ProgressArt extends StatelessWidget {
  const ProgressArt({required this.enter, required this.loop, super.key});

  final Animation<double> enter;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const RepaintBoundary(child: CustomPaint(painter: _ProgressHills())),
        RepaintBoundary(
          child: CustomPaint(painter: _ProgressPainter(enter, loop)),
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
  _ProgressPainter(this.enter, this.loop)
    : super(repaint: Listenable.merge(<Listenable>[enter, loop]));

  final Animation<double> enter;
  final Animation<double> loop;

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

  static final List<_Bar> _bars = <_Bar>[
    _Bar(300, 50, KOnboarding.blue, 0.10),
    _Bar(236, 90, KOnboarding.teal, 0.18),
    _Bar(172, 130, KOnboarding.pink, 0.26),
    _Bar(108, 170, KOnboarding.redSoft, 0.34),
    _Bar(44, 210, KOnboarding.gold, 0.42),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    enterDesignSpace(canvas, size);
    final double t = enter.value;
    final double l = loop.value;

    _paintGrid(canvas, t);
    for (final _Bar bar in _bars) {
      _paintBar(canvas, bar, t);
    }
    _paintTrend(canvas, t, l);
    _paintStar(canvas, t, l);
    _paintSparks(canvas, t, l);
    canvas.restore();
  }

  void _paintGrid(Canvas canvas, double t) {
    final double alpha = segment(t, 0, 0.3);
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
    final double grow = Curves.easeOutCubic.transform(
      segment(t, bar.delay, bar.delay + 0.26),
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

  void _paintTrend(Canvas canvas, double t, double l) {
    final double reveal = Curves.easeOutCubic.transform(segment(t, 0.45, 0.95));
    if (reveal <= 0) return;
    final ui.PathMetric metric = _trend.computeMetrics().first;
    final Path visible = metric.extractPath(0, metric.length * reveal);

    canvas.drawPath(
      visible,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = KOnboarding.redSoft.withValues(alpha: 0.22),
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
          <Color>[KOnboarding.redSoft, KOnboarding.gold],
        ),
    );

    if (reveal < 1) return;

    // A light that runs the line forever, like a live sparkline.
    final ui.Tangent? tangent = metric.getTangentForOffset(metric.length * l);
    if (tangent == null) return;
    final double fade = (1 - segment(l, 0.88, 1)).clamp(0.0, 1.0).toDouble();
    canvas.save();
    canvas.translate(tangent.position.dx, tangent.position.dy);
    canvas.rotate(tangent.angle);
    canvas.drawPath(
      _arrow,
      Paint()..color = KOnboarding.gold.withValues(alpha: fade),
    );
    canvas.restore();
  }

  void _paintStar(Canvas canvas, double t, double l) {
    final double pop = elastic(segment(t, 0.5, 0.78));
    if (pop <= 0) return;

    canvas.save();
    canvas.translate(62, 128);
    canvas.drawCircle(
      Offset.zero,
      46,
      Paint()..color = KOnboarding.gold.withValues(alpha: 0.14 * pop),
    );

    // Eight particles drift outward and fade, on a continuous loop.
    for (int i = 0; i < 8; i++) {
      final double phase = (l * 2 + i / 8) % 1;
      final double angle = i * math.pi / 4;
      final double radius = 46 + 14 * phase;
      canvas.drawCircle(
        Offset(math.cos(angle) * radius, math.sin(angle) * radius),
        4,
        Paint()
          ..color = (i.isEven ? KOnboarding.gold : KOnboarding.ink).withValues(
            alpha: (1 - phase) * 0.8 * pop,
          ),
      );
    }

    canvas.scale(pop);
    canvas.drawPath(starPath(), Paint()..color = KOnboarding.gold);
    canvas.restore();
  }

  static const List<(Offset, double, Color, double)> _sparks =
      <(Offset, double, Color, double)>[
        (Offset(340, 150), 0.8, KOnboarding.ink, 0.2),
        (Offset(200, 110), 0.6, KOnboarding.blue, 0.7),
      ];

  void _paintSparks(Canvas canvas, double t, double l) {
    final double alpha = segment(t, 0.1, 0.4);
    if (alpha <= 0) return;
    for (final (Offset position, double scale, Color color, double phase)
        in _sparks) {
      final double bob = math.sin((l + phase) * math.pi * 2) * 8 * scale;
      canvas.save();
      canvas.translate(position.dx, position.dy + bob);
      canvas.scale(scale);
      canvas.drawPath(
        sparklePath(12),
        Paint()..color = color.withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressPainter oldDelegate) =>
      oldDelegate.enter != enter || oldDelegate.loop != loop;
}

class _Bar {
  const _Bar(this.x, this.height, this.color, this.delay);

  final double x;
  final double height;
  final Color color;
  final double delay;
}
