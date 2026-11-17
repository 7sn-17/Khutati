import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/tokens.dart';

/// Typography entry points.
///
/// The prototype pairs IBM Plex Sans Arabic for body copy with Reem Kufi for
/// headings and every numeral. Both families are bundled under
/// `assets/google_fonts/`, so `google_fonts` resolves them from the asset
/// bundle and never needs the network on first launch.
abstract final class KhutatiFonts {
  static TextStyle body({
    double size = KTypography.bodySize,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = KTypography.bodyHeight,
  }) {
    return GoogleFonts.ibmPlexSansArabic(
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
    return GoogleFonts.reemKufi(
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
    return GoogleFonts.reemKufi(
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: color,
      height: 1.2,
    );
  }
}
