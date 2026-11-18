import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/launch_gate.dart';
import '../../../core/design/tokens.dart';
import '../application/onboarding_controller.dart';
import 'art/onboarding_art.dart';

/// The first Flutter frame: the wordmark over a drawing wave.
///
/// The native launch theme already paints #0D1A2D (see `values-v31/styles.xml`),
/// so this screen starts on exactly the same colour and the hand-off is
/// invisible. It holds for [hold] and then hands over to the welcome flow or to
/// the app, whichever the persisted state calls for.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// Long enough for the wordmark to land, short enough not to feel like a
  /// toll booth on every launch.
  static const Duration hold = Duration(milliseconds: 2500);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  Timer? _exit;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _exit = Timer(SplashScreen.hold, _finish);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read once: a mid-splash change of the accessibility setting must not
    // restart the drawing.
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduceMotion && _controller.value < 1) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _exit?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    if (!mounted) return;
    // Unlocks the update dialog and the notification prompt: both belong on
    // Today, never on top of the launch sequence.
    ref.read(launchReadyProvider.notifier).complete();
    final bool seen = ref.read(onboardingSeenProvider);
    context.go(seen ? '/today' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: KOnboarding.bg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: KOnboarding.bg,
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _WavePainter(_controller)),
                ),
              ),
              SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _Reveal(
                        animation: _controller,
                        start: 0.06,
                        end: 0.62,
                        scaleFrom: 0.92,
                        child: Text(
                          'خطتي',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontFamily: KTypography.displayFamily,
                            fontSize: 72,
                            fontWeight: FontWeight.w700,
                            height: 1.32,
                            color: KOnboarding.ink,
                          ),
                        ),
                      ),
                      _Reveal(
                        animation: _controller,
                        start: 0.28,
                        end: 0.78,
                        child: _Hairline(animation: _controller),
                      ),
                      const SizedBox(height: 20),
                      _Reveal(
                        animation: _controller,
                        start: 0.42,
                        end: 0.96,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(
                            'العلم يُبنى يوماً بعد يوم… لا في ليلة.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: KTypography.bodyFamily,
                              fontSize: 15,
                              height: 1.7,
                              color: KOnboarding.mute,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade + scale with `Curves.easeOutExpo`, over a window of the master timeline.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.animation,
    required this.start,
    required this.end,
    required this.child,
    this.scaleFrom = 1,
  });

  final Animation<double> animation;
  final double start;
  final double end;
  final double scaleFrom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      // The child is built once; only the opacity and transform are rebuilt.
      child: child,
      builder: (BuildContext context, Widget? child) {
        final double raw = ((animation.value - start) / (end - start))
            .clamp(0.0, 1.0)
            .toDouble();
        final double t = Curves.easeOutExpo.transform(raw);
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: scaleFrom + (1 - scaleFrom) * t,
            child: child,
          ),
        );
      },
    );
  }
}

/// A gold rule that draws outward from the centre under the wordmark.
class _Hairline extends StatelessWidget {
  const _Hairline({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, _) {
        final double t = Curves.easeOutExpo.transform(
          ((animation.value - 0.28) / 0.5).clamp(0.0, 1.0).toDouble(),
        );
        return Container(
          width: 64 * t,
          height: 2,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            gradient: LinearGradient(
              colors: <Color>[
                KOnboarding.gold.withValues(alpha: 0),
                KOnboarding.gold,
                KOnboarding.gold.withValues(alpha: 0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Three glowing waves that draw in from the inline-start edge, behind the text.
class _WavePainter extends CustomPainter {
  _WavePainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = Curves.easeOutExpo.transform(
      animation.value.clamp(0.0, 1.0).toDouble(),
    );
    if (t <= 0) return;

    final Offset center = Offset(size.width / 2, size.height * 0.52);

    // A warm halo behind the wordmark, wide enough to read as light rather
    // than a spotlight.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          size.shortestSide * (0.34 + 0.20 * t),
          <Color>[
            KOnboarding.gold.withValues(alpha: 0.10 * t),
            KOnboarding.gold.withValues(alpha: 0),
          ],
        ),
    );

    final double reveal = size.width * t;
    for (int i = 0; i < 3; i++) {
      final double baseY = center.dy + size.height * (0.07 + i * 0.032);
      final double amplitude = size.height * (0.020 - i * 0.004);
      final Path path = Path();
      bool started = false;
      // Drawn from the right edge leftwards: the app is RTL, so the wave
      // travels the same way the reader does.
      for (double x = size.width; x >= size.width - reveal; x -= 3) {
        final double p = x / size.width;
        final double y =
            baseY +
            math.sin(p * math.pi * 2.6 + i * 1.1) * amplitude * (0.5 + 0.5 * t);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      if (!started) continue;

      final double fade = (1 - i * 0.26) * t;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(
            Offset(size.width, 0),
            Offset(0, 0),
            <Color>[
              KOnboarding.gold.withValues(alpha: 0),
              KOnboarding.gold.withValues(alpha: 0.40 * fade),
              KOnboarding.redSoft.withValues(alpha: 0.26 * fade),
              KOnboarding.gold.withValues(alpha: 0),
            ],
            <double>[0, 0.32, 0.68, 1],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.animation != animation;
}
