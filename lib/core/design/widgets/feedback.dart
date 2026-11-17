import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../palette.dart';
import '../tokens.dart';

enum KToastKind { success, error, info }

/// A top-anchored confirmation card. It uses the app's own surface, accent and
/// type tokens rather than the Material SnackBar, so feedback reads as part of
/// the product in both light and dark themes.
void showKToast(
  BuildContext context,
  String message, {
  KToastKind kind = KToastKind.success,
}) {
  final OverlayState overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (BuildContext context) => _KToastOverlay(
      message: message,
      kind: kind,
      onDismissed: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _KToastOverlay extends StatefulWidget {
  const _KToastOverlay({
    required this.message,
    required this.kind,
    required this.onDismissed,
  });

  final String message;
  final KToastKind kind;
  final VoidCallback onDismissed;

  @override
  State<_KToastOverlay> createState() => _KToastOverlayState();
}

class _KToastOverlayState extends State<_KToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: KMotion.toastMs),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide =
      Tween<Offset>(begin: const Offset(0, -0.35), end: Offset.zero).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    Future<void>.delayed(const Duration(milliseconds: 2800), () async {
      if (!mounted) return;
      await _controller.reverse();
      widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;
    final (Color accent, IconData icon) = switch (widget.kind) {
      KToastKind.success => (palette.ok, Icons.check_rounded),
      KToastKind.error => (palette.redtx, Icons.error_outline_rounded),
      KToastKind.info => (palette.gold, Icons.info_outline_rounded),
    };

    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: KMetrics.appPaddingX,
      right: KMetrics.appPaddingX,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Center(
              child: Semantics(
                liveRegion: true,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(KMetrics.cardRadius),
                    border: Border.all(color: accent.withValues(alpha: 0.55)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: palette.bg.withValues(alpha: 0.28),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 19, color: accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.message,
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontFamily: KTypography.bodyFamily,
                            fontSize: KTypography.muteSize,
                            fontWeight: FontWeight.w500,
                            color: palette.tx,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.cf` — the completion burst: 26 small rectangles falling and spinning for
/// 1.8s, in the prototype's four accent colours.
class KConfetti extends StatefulWidget {
  const KConfetti({this.play = true, super.key});

  final bool play;

  @override
  State<KConfetti> createState() => _KConfettiState();
}

class _KConfettiState extends State<KConfetti> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: KMotion.confettiMs),
  );

  late final List<_ConfettiPiece> _pieces = _buildPieces();

  @override
  void initState() {
    super.initState();
    if (widget.play) _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant KConfetti oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.play && !oldWidget.play) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            return CustomPaint(
              size: Size.infinite,
              painter: _ConfettiPainter(
                pieces: _pieces,
                progress: _controller.value,
              ),
            );
          },
        ),
      ),
    );
  }

  List<_ConfettiPiece> _buildPieces() {
    final math.Random random = math.Random(7);
    final List<Color> palette = <Color>[
      KColors.dark.gold,
      KColors.dark.ok,
      KColors.dark.redtx,
      const Color(0xFF6AA6FF),
    ];
    return List<_ConfettiPiece>.generate(26, (int i) {
      return _ConfettiPiece(
        x: random.nextDouble(),
        color: palette[i % palette.length],
        delay: random.nextDouble() * 0.3,
        spin: 360 + random.nextDouble() * 360,
        drift: (random.nextDouble() - 0.5) * 40,
      );
    });
  }
}

class _ConfettiPiece {
  const _ConfettiPiece({
    required this.x,
    required this.color,
    required this.delay,
    required this.spin,
    required this.drift,
  });

  final double x;
  final Color color;
  final double delay;
  final double spin;
  final double drift;
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.pieces, required this.progress});

  final List<_ConfettiPiece> pieces;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    for (final _ConfettiPiece piece in pieces) {
      final double t = ((progress - piece.delay) / (1 - piece.delay)).clamp(0.0, 1.0).toDouble();
      if (t <= 0) continue;

      final double y = -14 + t * (size.height + 40);
      final double x = piece.x * size.width + math.sin(t * 6) * piece.drift;
      final double opacity = t > 0.8 ? (1 - t) * 5 : 1.0;

      paint.color = piece.color.withValues(alpha: opacity.clamp(0.0, 1.0).toDouble());

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * piece.spin * math.pi / 180);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-4.5, -7, 9, 14),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.progress != progress;
}
