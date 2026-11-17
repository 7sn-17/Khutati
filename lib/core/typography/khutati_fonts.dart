import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Typography entry points.
///
/// The prototype pairs IBM Plex Sans Arabic for body copy with Reem Kufi for
/// headings and every numeral. Both families are declared in `pubspec.yaml`
/// under `flutter: fonts:`, so Flutter registers them before the first frame
/// and `fontFamily` resolves synchronously — offline, with no runtime font
/// fetching and no flash of the platform default.
abstract final class KhutatiFonts {
  static TextStyle body({
    double size = KTypography.bodySize,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = KTypography.bodyHeight,
  }) {
    return TextStyle(
      fontFamily: KTypography.bodyFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  static TextStyle display({
    double size = KTypography.heroTitleSize,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double height = 1.3,
  }) {
    return TextStyle(
      fontFamily: KTypography.displayFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  /// Numerals in the prototype always use the display face (`.num`).
  static TextStyle numeral({
    double size = KTypography.statNumSize,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: KTypography.displayFamily,
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: color,
      height: 1.2,
    );
  }
}
