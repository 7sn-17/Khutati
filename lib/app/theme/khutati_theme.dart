import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/palette.dart' as design;
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

  /// Exposes the palette for widgets that need a token colour directly.
  static KhutatiPalette paletteOf(BuildContext context) => design.paletteOf(context);

  static ThemeData _build(KhutatiPalette palette, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

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
        height: KTypography.heroTitleHeight,
      ),
      titleMedium: KhutatiFonts.body(
        size: KTypography.quoteSize,
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
      dividerTheme: DividerThemeData(color: palette.line, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.bg,
        foregroundColor: palette.tx,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: palette.bg,
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}
