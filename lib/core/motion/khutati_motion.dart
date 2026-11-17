import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../design/tokens.dart';

/// The motion language of the app.
///
/// Durations and curves come from the prototype's CSS transitions, but the
/// implementation is native Flutter: implicit animations for state changes,
/// `flutter_animate` for staggered entrances, and platform haptics for touch
/// feedback. A web page cannot do the last one.
abstract final class KhutatiMotion {
  static Duration get fast => Duration(milliseconds: KMotion.navMs);
  static Duration get standard => Duration(milliseconds: KMotion.cardEntranceMs);
  static Duration get slow => Duration(milliseconds: KMotion.ecgMs);
  static Duration get stagger => Duration(milliseconds: KMotion.staggerMs);
  static const Curve entranceCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;

  /// Honours the system "remove animations" accessibility setting.
  static bool reduced(BuildContext context) {
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }
}

/// Staggered card entrance: fade + a short rise, offset by index.
///
/// Use on list children: `child.khutatiEntrance(index: i)`. When reduced motion
/// is on, the widget is returned untouched so nothing moves.
extension KhutatiEntrance on Widget {
  Widget khutatiEntrance({int index = 0, BuildContext? context, bool enabled = true}) {
    final bool shouldAnimate = enabled && (context == null || !KhutatiMotion.reduced(context));
    if (!shouldAnimate) return this;

    final Duration delay = KhutatiMotion.stagger * index;
    return animate()
        .fadeIn(
          duration: KhutatiMotion.standard,
          delay: delay,
          curve: KhutatiMotion.entranceCurve,
        )
        .slideY(
          begin: 0.06,
          end: 0,
          duration: KhutatiMotion.standard,
          delay: delay,
          curve: KhutatiMotion.entranceCurve,
        );
  }
}
