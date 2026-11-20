import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/pressable.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/sound/sound_effects.dart';
import '../application/onboarding_controller.dart';
import 'art/day_art.dart';
import 'art/onboarding_art.dart';
import 'art/progress_art.dart';
import 'art/roadmap_art.dart';

/// First-launch welcome — a native rebuild of `khutati-onboarding.html`.
///
/// The prototype moves whole slides with a CSS transform. Here the slides stay
/// in a [PageView] and every page additionally applies parallax, fade and
/// scale, so the outgoing page drifts slower than the incoming one and the
/// scene reads as depth rather than a flat carousel.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const int _pageCount = 3;

  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    ref.read(hapticsProvider).selection();
  }

  void _next() {
    if (_index >= _pageCount - 1) {
      _start();
      return;
    }
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _controller.nextPage(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  /// Skip means skip: the flow is marked complete and the router decides
  /// between login and Today.
  Future<void> _skip() => _start();

  Future<void> _start() async {
    await ref.read(onboardingSeenProvider.notifier).complete();
    if (mounted) context.go('/today');
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final double width = MediaQuery.sizeOf(context).width;
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final bool last = _index == _pageCount - 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: KOnboarding.bg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: KOnboarding.bg,
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pageCount,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (BuildContext context, int index) {
                    return _ParallaxPage(
                      controller: _controller,
                      index: index,
                      child: _Slide(
                        index: index,
                        active: index == _index,
                        reduceMotion: reduceMotion,
                        width: width,
                        bottomInset: safe.bottom,
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                // Matches the CSS `calc(14px + env(safe-area-inset-top))`.
                top: 14 + safe.top,
                // The prototype places the pill on the inline-end edge; in RTL
                // that is the visual left, which also keeps it clear of the
                // red flag in the first illustration.
                left: 16,
                child: AnimatedOpacity(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  opacity: last ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: last,
                    child: _SkipButton(
                      key: const ValueKey<String>('onboarding-skip'),
                      onTap: _skip,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 24 + safe.bottom,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _Dots(
                      count: _pageCount,
                      index: _index,
                      onSelected: (int i) => _controller.animateToPage(
                        i,
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PrimaryButton(
                      key: const ValueKey<String>('onboarding-primary'),
                      label: last ? 'ابدأ' : 'التالي',
                      onPressed: _next,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Depth wrapper: the page lags the scroll by 18%, fades and scales down as it
/// leaves the viewport.
class _ParallaxPage extends StatelessWidget {
  const _ParallaxPage({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      // `child` is passed through so the slide itself is never rebuilt while
      // the user drags; only this transform wrapper is.
      child: child,
      builder: (BuildContext context, Widget? child) {
        final double page = controller.hasClients
            ? (controller.page ?? index.toDouble())
            : index.toDouble();
        final double delta = index - page;
        final double distance = delta.abs().clamp(0.0, 1.0).toDouble();
        // The depth cue is eased, the tracking is not: the page must still
        // follow the finger one-to-one horizontally.
        final double eased = Curves.easeOutCubic.transform(distance);

        // The slot already travels one full width with the scroll. A counter
        // translation of 18% makes the outgoing page trail the finger (net 0.82
        // of a width) while the incoming page leads it (1.18), so the layers
        // separate in depth instead of sliding as one sheet.
        return Transform.translate(
          offset: Offset(-0.18 * delta * MediaQuery.sizeOf(context).width, 0),
          child: Opacity(
            opacity: 1 - 0.75 * eased,
            child: Transform.scale(scale: 1 - 0.10 * eased, child: child),
          ),
        );
      },
    );
  }
}

class _Slide extends StatefulWidget {
  const _Slide({
    required this.index,
    required this.active,
    required this.reduceMotion,
    required this.width,
    required this.bottomInset,
  });

  final int index;
  final bool active;
  final bool reduceMotion;
  final double width;
  final double bottomInset;

  @override
  State<_Slide> createState() => _SlideState();
}

class _SlideState extends State<_Slide> with TickerProviderStateMixin {
  static const List<_SlideCopy> _copy = <_SlideCopy>[
    _SlideCopy(
      title: 'منهاجك كله في 68 يوماً',
      body: 'خطة جاهزة مرتبة بالتاريخ والمواد، فلا تسأل نفسك بعد اليوم: ماذا أدرس؟',
    ),
    _SlideCopy(
      title: 'يوم واحد في كل مرة',
      body: 'افتح التطبيق وستجد مهام يومك بمواعيدها، ومؤقتاً يرافقك حتى تنتهي كل خطوة.',
    ),
    _SlideCopy(
      title: 'شاهد نفسك تتقدم',
      body: 'ساعاتك وسلسلتك وإنجازاتك تُحسب من دراستك الفعلية، وكل يوم يقرّبك من النهاية.',
    ),
  ];

  /// Entrance timeline, in real seconds: the painters read
  /// `value * kEnterSeconds` and each element applies its own CSS delay and
  /// duration. It is deliberately linear — curving the master would warp every
  /// ported timing at once.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 7000),
  );

  /// Ambient clock. Two hours, played once: long enough that no infinite
  /// animation ever has to share a period with another one.
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(hours: 2),
  );

  @override
  void initState() {
    super.initState();
    if (widget.reduceMotion) {
      // A composed still, not an empty one: 7 s into the ambient cycle the line
      // is drawn, the star has burst and the flag is up.
      _enter.value = 1;
      _ambient.value = 7 / kAmbientSeconds;
    } else if (widget.active) {
      _play();
    }
  }

  @override
  void didUpdateWidget(covariant _Slide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _enter.value = 1;
      _ambient.value = 7 / kAmbientSeconds;
      return;
    }
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      // Replaying on arrival is what makes a swipe feel like a scene change.
      _play();
    } else {
      // An inactive scene must not keep a ticker awake.
      _enter.stop();
      _ambient.stop();
    }
  }

  void _play() {
    _enter.forward(from: 0);
    _ambient.forward(from: 0);
  }

  @override
  void dispose() {
    _enter.dispose();
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _SlideCopy copy = _copy[widget.index];
    final double titleSize = (widget.width * 0.088).clamp(28.0, 36.0);

    return Padding(
      // Room for the footer (dots + button + margins) plus the system inset.
      // Without the inset the body text collides with the dots on phones with
      // a gesture bar — the footer is positioned from the safe area, the page
      // was not.
      padding: EdgeInsets.only(bottom: 148 + widget.bottomInset),
      child: Column(
        children: <Widget>[
          Expanded(child: _art()),
          // Clamped so a 2x system text scale cannot push the illustration off
          // screen; 1.4 still honours the user's preference.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: <Widget>[
                  Text(
                    copy.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: KTypography.displayFamily,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: KOnboarding.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 330),
                    child: Text(
                      copy.body,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: KTypography.bodyFamily,
                        fontSize: (widget.width * 0.042).clamp(15.0, 17.0),
                        height: 1.65,
                        color: KOnboarding.mute,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _art() {
    return switch (widget.index) {
      0 => RoadmapArt(enter: _enter, ambient: _ambient),
      1 => DayArt(enter: _enter, ambient: _ambient),
      _ => ProgressArt(enter: _enter, ambient: _ambient),
    };
  }
}

class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.index,
    required this.onSelected,
  });

  final int count;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < count; i++)
          Semantics(
            container: true,
            button: true,
            selected: i == index,
            label: 'الشاشة ${i + 1}',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelected(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 3,
                  vertical: 10,
                ),
                child: AnimatedContainer(
                  duration:
                      MediaQuery.maybeDisableAnimationsOf(context) ?? false
                      ? Duration.zero
                      : const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  width: i == index ? 28 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == index ? KOnboarding.redSoft : KOnboarding.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      color: KOnboarding.ink.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      minHeight: 44,
      sound: KSound.tap,
      child: Center(
        child: Text(
          'تخطَّ',
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: KOnboarding.ink,
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: reduceMotion
            ? const <BoxShadow>[]
            : <BoxShadow>[
                BoxShadow(
                  color: KOnboarding.red.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
                const BoxShadow(
                  color: KOnboarding.shade,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: KPressable(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        color: KOnboarding.red,
        padding: const EdgeInsets.symmetric(vertical: 17),
        minHeight: 56,
        expand: true,
        sound: KSound.tap,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: KTypography.bodyFamily,
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _SlideCopy {
  const _SlideCopy({required this.title, required this.body});

  final String title;
  final String body;
}
