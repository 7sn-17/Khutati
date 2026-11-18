import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'onboarding_art.dart';

/// Slide 2 — one study day: a live clock and three task rows ticking over.
///
/// Timings are the prototype's: the twelve ticks pop 0.1 s apart, the arc draws
/// over 4.4 s from 1.0 s, the rows slide in at 1.0/1.5/2.0 and the halo starts
/// at 5.2.
class DayArt extends StatelessWidget {
  const DayArt({required this.enter, required this.ambient, super.key});

  final Animation<double> enter;
  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const RepaintBoundary(child: CustomPaint(painter: _DayHills())),
        RepaintBoundary(
          child: CustomPaint(painter: _DayPainter(enter, ambient)),
        ),
      ],
    );
  }
}

class _DayHills extends CustomPainter {
  const _DayHills();

  @override
  void paint(Canvas canvas, Size size) {
    HillsPainter(
      backPath: _back,
      frontPath: _front,
      glow: KOnboarding.teal,
      glowCenter: const Offset(195, 150),
      glowRadius: 280,
    ).paint(canvas, size);
  }

  static final Path _back = Path()
    ..moveTo(-400, -3000)
    ..lineTo(790, -3000)
    ..lineTo(790, 540)
    ..lineTo(390, 540)
    ..cubicTo(330, 560, 270, 510, 200, 480)
    ..cubicTo(130, 450, 60, 470, 0, 430)
    ..lineTo(-400, 430)
    ..close();

  static final Path _front = Path()
    ..moveTo(-400, -3000)
    ..lineTo(790, -3000)
    ..lineTo(790, 510)
    ..lineTo(390, 510)
    ..cubicTo(330, 530, 270, 480, 200, 450)
    ..cubicTo(130, 420, 60, 440, 0, 400)
    ..lineTo(-400, 400)
    ..close();

  @override
  bool shouldRepaint(covariant _DayHills oldDelegate) => false;
}

class _DayPainter extends CustomPainter {
  _DayPainter(this.enter, this.ambient)
    : super(repaint: Listenable.merge(<Listenable>[enter, ambient]));

  final Animation<double> enter;
  final Animation<double> ambient;

  static const List<_TaskRow> _rows = <_TaskRow>[
    _TaskRow(250, KOnboarding.blue, 'حضور الفيديو', '13 د', true, 1.0),
    _TaskRow(296, KOnboarding.blue, 'دراسة الفيديو', '13 د', true, 1.5),
    _TaskRow(342, KOnboarding.teal, 'حل أسئلة الفصل', 'ساعة', false, 2.0),
  ];

  static const List<(Offset, double, Color, double)> _sparks =
      <(Offset, double, Color, double)>[
        (Offset(52, 90), 0.8, KOnboarding.gold, 0),
        (Offset(340, 70), 1, KOnboarding.teal, 2),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    enterDesignSpace(canvas, size);
    final double t = enter.value * kEnterSeconds;
    final double a = ambient.value * kAmbientSeconds;

    _paintClock(canvas, t, a);
    for (final _TaskRow row in _rows) {
      _paintRow(canvas, row, t, a);
    }
    _paintSparks(canvas, t, a);
    canvas.restore();
  }

  void _paintClock(Canvas canvas, double t, double a) {
    canvas.save();
    canvas.translate(195, 150);

    // Twelve ticks, 0.1 s apart; the first eight are "spent" hours.
    for (int i = 0; i < 12; i++) {
      final double pop = kPopCurve.transform(
        stage(t, delay: i * 0.1, duration: 1.2),
      );
      if (pop <= 0) continue;
      canvas.save();
      canvas.rotate(i * math.pi / 6);
      canvas.scale(pop);
      canvas.drawLine(
        const Offset(0, -86),
        const Offset(0, -95),
        Paint()
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..color = i < 8 ? KOnboarding.redSoft : KOnboarding.line,
      );
      canvas.restore();
    }

    canvas.drawCircle(
      Offset.zero,
      64,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = KOnboarding.line,
    );

    // `.ar` draws 0 → 300 of a 402-long dash over 4.4 s, starting at 1 s.
    final double arc = Curves.easeOut.transform(
      stage(t, delay: 1.0, duration: 4.4),
    );
    if (arc > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: 64),
        -math.pi / 2,
        math.pi * 2 * 0.75 * arc,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round
          ..color = KOnboarding.redSoft,
      );
    }

    // `.pl` — a 5 s halo that begins at 5.2 s and never repeats its phase.
    if (a >= 5.2) {
      final double pulse = Curves.easeOut.transform(
        cycle(a, period: 5, delay: 5.2),
      );
      canvas.drawCircle(
        Offset.zero,
        64 * (1 + 0.35 * pulse),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = KOnboarding.redSoft.withValues(alpha: 0.5 * (1 - pulse)),
      );
    }

    final double textIn = Curves.easeOut.transform(
      stage(t, delay: 0.9, duration: 0.8),
    );
    if (textIn > 0) {
      paintText(
        canvas,
        '13:00',
        at: const Offset(0, -22),
        size: 40,
        color: KOnboarding.ink.withValues(alpha: textIn),
        weight: FontWeight.w700,
        family: 'Reem Kufi',
        ltr: true,
      );
      paintText(
        canvas,
        'دراسة الفيديو',
        at: const Offset(0, 18),
        size: 13,
        color: KOnboarding.dim.withValues(alpha: textIn),
      );
    }
    canvas.restore();
  }

  void _paintRow(Canvas canvas, _TaskRow row, double t, double a) {
    // `.slx` — 1.4 s from +70 px with a fade.
    final double slide = kSlideCurve.transform(
      stage(t, delay: row.delay, duration: 1.4),
    );
    if (slide <= 0) return;

    canvas.save();
    // Enters from the start edge (+x in this RTL scene) and settles. Every
    // paint is faded by the same value instead of using a saveLayer, which
    // would allocate a layer for each row on every frame.
    canvas.translate(70 * (1 - slide), 0);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(45, row.y, 300, 40),
        const Radius.circular(12),
      ),
      Paint()..color = KOnboarding.hillBack.withValues(alpha: slide),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(341, row.y + 8, 4, 24),
        const Radius.circular(2),
      ),
      Paint()..color = row.accent.withValues(alpha: slide),
    );

    final Offset center = Offset(318, row.y + 20);
    if (row.done) {
      canvas.drawCircle(
        center,
        10,
        Paint()..color = KOnboarding.ok.withValues(alpha: slide),
      );
      _paintCheck(canvas, center, t, row.delay, slide);
    } else {
      canvas.drawCircle(
        center,
        10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = KOnboarding.dim.withValues(alpha: slide),
      );
      // `.pl` on the pending row starts at 4 s.
      if (a >= 4) {
        final double pulse = Curves.easeOut.transform(
          cycle(a, period: 5, delay: 4),
        );
        canvas.drawCircle(
          center,
          10 * (1 + 0.9 * pulse),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = KOnboarding.teal.withValues(
              alpha: 0.6 * (1 - pulse) * slide,
            ),
        );
      }
    }

    paintText(
      canvas,
      row.label,
      at: Offset(296, row.y + 11),
      size: 15,
      color: KOnboarding.ink.withValues(alpha: slide),
      weight: FontWeight.w500,
      align: TextAlign.right,
    );
    paintText(
      canvas,
      row.duration,
      at: Offset(63, row.y + 12),
      size: 13,
      color: KOnboarding.dim.withValues(alpha: slide),
      align: TextAlign.left,
    );

    canvas.restore();
  }

  void _paintCheck(
    Canvas canvas,
    Offset center,
    double t,
    double rowDelay,
    double alpha,
  ) {
    // `.dr` — the check draws 0.4 s after its row starts, over 1 s.
    final double reveal = Curves.easeOut.transform(
      stage(t, delay: rowDelay + 0.4, duration: 1.0),
    );
    if (reveal <= 0) return;
    final Path check = Path()
      ..moveTo(center.dx - 5, center.dy)
      ..lineTo(center.dx - 1, center.dy + 4)
      ..lineTo(center.dx + 7, center.dy - 5);
    final ui.PathMetric metric = check.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * reveal),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = KOnboarding.bg.withValues(alpha: alpha),
    );
  }

  void _paintSparks(Canvas canvas, double t, double a) {
    final double alpha = Curves.easeOut.transform(
      stage(t, delay: 0.1, duration: 1.2),
    );
    if (alpha <= 0) return;
    for (final (Offset position, double scale, Color color, double delay)
        in _sparks) {
      final double p = delayedCycle(a, period: 7, delay: delay);
      final double bob = -8 * (1 - math.cos(p * math.pi * 2)) / 2 * scale;
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
  bool shouldRepaint(covariant _DayPainter oldDelegate) =>
      oldDelegate.enter != enter || oldDelegate.ambient != ambient;
}

class _TaskRow {
  const _TaskRow(
    this.y,
    this.accent,
    this.label,
    this.duration,
    this.done,
    this.delay,
  );

  final double y;
  final Color accent;
  final String label;
  final String duration;
  final bool done;

  /// Seconds before the row slides in.
  final double delay;
}
