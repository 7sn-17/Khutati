import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/typography/khutati_fonts.dart';

/// Theme built exclusively from the tokens extracted out of the HTML prototype.
///
/// No colour, radius or type size is declared here by hand: if the prototype
/// changes, `node tools/extract_tokens.mjs` regenerates the tokens and both
/// themes follow.
abstract final class KhutatiTheme {
  static final ThemeData dark = _build(KColors.dark, Brightness.dark);
  static final ThemeData light = _build(KColors.light, Brightness.light);

  static ThemeData _build(KhutatiPalette palette, Brightness brightness) {
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: palette.red,
      onPrimary: Colors.white,
      secondary: palette.ok,
      onSecondary: palette.bg,
      tertiary: palette.gold,
      onTertiary: palette.bg,
      error: palette.redtx,
      onError: palette.bg,
      surface: palette.card,
      onSurface: palette.tx,
      outline: palette.line,
      surfaceContainerHighest: palette.card2,
      onSurfaceVariant: palette.mute,
    );

    final TextTheme text = TextTheme(
      displayLarge: KhutatiFonts.display(
        size: KTypography.h1Size,
        color: palette.tx,
        height: KTypography.h1Height,
      ),
      headlineSmall: KhutatiFonts.display(
        size: KTypography.h2Size,
        color: palette.tx,
      ),
      titleLarge: KhutatiFonts.display(
        size: KTypography.heroTitleSize,
        color: palette.tx,
      ),
      titleMedium: KhutatiFonts.body(
        size: 15,
        weight: FontWeight.w500,
        color: palette.tx,
      ),
      bodyLarge: KhutatiFonts.body(
        size: KTypography.bodySize,
        color: palette.tx,
      ),
      bodyMedium: KhutatiFonts.body(
        size: KTypography.bodySize,
        color: palette.tx,
      ),
      bodySmall: KhutatiFonts.body(
        size: KTypography.smallSize,
        color: palette.mute,
      ),
      labelSmall: KhutatiFonts.body(
        size: KTypography.tagSize,
        weight: FontWeight.w500,
        color: palette.mute,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.bg,
      canvasColor: palette.bg,
      dividerColor: palette.line,
      textTheme: text,
      iconTheme: IconThemeData(color: palette.mute),
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      // 48dp minimum tap target (PRD section 8, accessibility).
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}
