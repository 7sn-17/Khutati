import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/feedback.dart';
import 'google_sign_in_button.dart';

/// Login — a direct Flutter translation of `design/login_reference.html`.
///
/// The screen intentionally owns its colour table instead of reading the app
/// palette: the reference defines a distinct sky/mountain scale that must stay
/// byte-for-byte comparable to the CSS variables in both themes.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  // One master clock for the staggered scene:
  // back starts at 0ms, middle at 150ms, front at 300ms; every layer rises for
  // exactly 1600ms, so the whole scene settles at 1900ms.
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..forward();

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final _LoginColors colors = dark ? _LoginColors.dark : _LoginColors.light;
    final MediaQueryData media = MediaQuery.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: colors.bg,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: colors.page,
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // The reference frames the screen at 440px on desktop and lets it
            // fill the viewport on phones.
            final bool framed = constraints.maxWidth >= 700;
            final double width = framed ? 440 : constraints.maxWidth;
            final double mountainHeight = (media.size.height * 0.42).clamp(
              220.0,
              400.0,
            );

            return Center(
              child: Container(
                width: width,
                height: constraints.maxHeight,
                decoration: framed
                    ? const BoxDecoration(
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: Color(0x33000000), blurRadius: 60),
                        ],
                      )
                    : null,
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Positioned.fill(child: _Sky(colors: colors)),
                      Positioned(
                        top: media.padding.top + 40,
                        right: 24,
                        child: _Wordmark(colors: colors),
                      ),
                      Positioned(
                        top: media.padding.top + 12,
                        left: 20,
                        child: _GuestChip(colors: colors),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: mountainHeight,
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _rise,
                            builder: (BuildContext context, Widget? child) {
                              final bool reduce =
                                  MediaQuery.maybeDisableAnimationsOf(
                                    context,
                                  ) ??
                                  false;
                              final double elapsed = reduce ? 1 : _rise.value;
                              return CustomPaint(
                                painter: _MountainsPainter(
                                  // cubic-bezier(.2,.8,.2,1), 1.6s each,
                                  // delayed by 0 / 0.15 / 0.3 seconds.
                                  back: reduce ? 1 : _layer(elapsed, 0),
                                  middle: reduce ? 1 : _layer(elapsed, 150),
                                  front: reduce ? 1 : _layer(elapsed, 300),
                                  mt1: colors.mt1,
                                  mt2: colors.mt2,
                                  mt3: colors.mt3,
                                  mast: colors.tx,
                                  flag: _LoginColors.flag,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: _Sheet(colors: colors, dark: dark),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static const Curve _riseCurve = Cubic(0.2, 0.8, 0.2, 1.0);

  /// Progress of one layer, in ref pixels. Delays are in milliseconds.
  double _layer(double master, double delayMs) {
    final double elapsed = master * 1900 - delayMs;
    final double t = (elapsed / 1600).clamp(0.0, 1.0);
    return _riseCurve.transform(t);
  }
}

class _Sky extends StatelessWidget {
  const _Sky({required this.colors});

  final _LoginColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const <double>[0.10, 1.0],
          colors: <Color>[
            colors.bg,
            Color.lerp(colors.bg, colors.skyEnd, 0.8)!,
          ],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.colors});

  final _LoginColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          'خطتي',
          style: TextStyle(
            fontFamily: KTypography.displayFamily,
            fontSize: 54,
            fontWeight: FontWeight.w700,
            height: 1,
            color: colors.tx,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'دراسة أهدأ، ويوم أوضح',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 15,
            color: colors.mute,
          ),
        ),
      ],
    );
  }
}

class _GuestChip extends StatelessWidget {
  const _GuestChip({required this.colors});

  final _LoginColors colors;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: colors.bg.withValues(alpha: 0.60),
          child: InkWell(
            onTap: () => showKToast(
              context,
              'سجّل الدخول بحساب Google لتبقى خطتك معك على كل هاتف.',
              kind: KToastKind.info,
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colors.line),
              ),
              child: Text(
                'المتابعة كزائر',
                style: TextStyle(
                  fontFamily: KTypography.bodyFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.tx,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.colors, required this.dark});

  final _LoginColors colors;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final double safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 28, 24, 64 + safeBottom),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'ابدأ يومك بخطة واضحة',
            style: TextStyle(
              fontFamily: KTypography.displayFamily,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: colors.tx,
            ),
          ),
          const SizedBox(height: 18),
          GoogleSignInButton(
            backgroundColor: colors.btnBg,
            foregroundColor: colors.btnTx,
            borderColor: colors.btnBd,
            showShadow: dark,
          ),
          const SizedBox(height: 18),
          Text(
            'بحساب Google تبقى خطتك معك حتى لو غيّرت هاتفك',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KTypography.bodyFamily,
              fontSize: 13,
              height: 1.6,
              color: colors.mute,
            ),
          ),
        ],
      ),
    );
  }
}

/// Colours copied from the `:root` / `[data-theme=dark]` blocks of the HTML.
class _LoginColors {
  const _LoginColors({
    required this.page,
    required this.bg,
    required this.line,
    required this.tx,
    required this.mute,
    required this.skyEnd,
    required this.mt1,
    required this.mt2,
    required this.mt3,
    required this.btnBg,
    required this.btnTx,
    required this.btnBd,
  });

  final Color page;
  final Color bg;
  final Color line;
  final Color tx;
  final Color mute;
  final Color skyEnd;
  final Color mt1;
  final Color mt2;
  final Color mt3;
  final Color btnBg;
  final Color btnTx;
  final Color btnBd;

  static const Color flag = Color(0xFFB52A20);

  static const _LoginColors light = _LoginColors(
    page: Color(0xFFE4DED0),
    bg: Color(0xFFF1EDE4),
    line: Color(0xFFD9D2C3),
    tx: Color(0xFF0D1A2D),
    mute: Color(0xFF5B6A80),
    skyEnd: Color(0xFFB6E2D4),
    mt1: Color(0xFF9CC4BB),
    mt2: Color(0xFF5B9A94),
    mt3: Color(0xFF256A70),
    btnBg: Color(0xFF0D1A2D),
    btnTx: Color(0xFFF1EDE4),
    btnBd: Color(0xFF0D1A2D),
  );

  static const _LoginColors dark = _LoginColors(
    page: Color(0xFF07101D),
    bg: Color(0xFF0D1A2D),
    line: Color(0xFF26395A),
    tx: Color(0xFFEAE5DA),
    mute: Color(0xFF93A1B8),
    skyEnd: Color(0xFF12606F),
    mt1: Color(0xFF2A7C8A),
    mt2: Color(0xFF1B5668),
    mt3: Color(0xFF10334A),
    btnBg: Color(0xFF15263F),
    btnTx: Color(0xFFEAE5DA),
    btnBd: Color(0xFF26395A),
  );
}

/// Paints the three SVG mountain layers with the reference's rise animation.
class _MountainsPainter extends CustomPainter {
  const _MountainsPainter({
    required this.back,
    required this.middle,
    required this.front,
    required this.mt1,
    required this.mt2,
    required this.mt3,
    required this.mast,
    required this.flag,
  });

  final double back;
  final double middle;
  final double front;
  final Color mt1;
  final Color mt2;
  final Color mt3;
  final Color mast;
  final Color flag;

  static final Path _backPath = Path()
    ..moveTo(0, 200)
    ..lineTo(0, 110)
    ..lineTo(52, 56)
    ..lineTo(98, 104)
    ..lineTo(150, 40)
    ..lineTo(206, 108)
    ..lineTo(252, 70)
    ..lineTo(300, 118)
    ..lineTo(300, 200)
    ..close();

  static final Path _middlePath = Path()
    ..moveTo(0, 200)
    ..lineTo(0, 140)
    ..lineTo(70, 84)
    ..lineTo(120, 134)
    ..lineTo(176, 62)
    ..lineTo(232, 130)
    ..lineTo(300, 96)
    ..lineTo(300, 200)
    ..close();

  static final Path _mastPath = Path()
    ..moveTo(176, 62)
    ..lineTo(176, 30);

  static final Path _flagPath = Path()
    ..moveTo(176, 30)
    ..lineTo(202, 38)
    ..lineTo(176, 46)
    ..close();

  static final Path _frontPath = Path()
    ..moveTo(0, 200)
    ..lineTo(0, 164)
    ..lineTo(58, 122)
    ..lineTo(112, 168)
    ..lineTo(170, 128)
    ..lineTo(226, 172)
    ..lineTo(300, 136)
    ..lineTo(300, 200)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);

    // preserveAspectRatio="xMidYMax slice"
    final double scale = math.max(size.width / 300, size.height / 200);
    final double dx = (size.width - 300 * scale) / 2;
    final double dy = size.height - 200 * scale;

    void rise(Path path, double progress, Color color) {
      canvas.save();
      // The CSS animation translates each <g> by 120px from below.
      canvas.translate(dx, dy + 120 * (1 - progress));
      canvas.scale(scale);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color,
      );
      canvas.restore();
    }

    rise(_backPath, back, mt1);
    rise(_middlePath, middle, mt2);

    // Mast + flag belong to the middle <g>, so they rise with it.
    canvas.save();
    canvas.translate(dx, dy + 120 * (1 - middle));
    canvas.scale(scale);
    canvas.drawPath(
      _mastPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = mast,
    );
    canvas.drawPath(
      _flagPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = flag,
    );
    canvas.restore();

    rise(_frontPath, front, mt3);
  }

  @override
  bool shouldRepaint(_MountainsPainter old) {
    return old.back != back ||
        old.middle != middle ||
        old.front != front ||
        old.mt1 != mt1 ||
        old.mt2 != mt2 ||
        old.mt3 != mt3 ||
        old.mast != mast ||
        old.flag != flag;
  }
}
