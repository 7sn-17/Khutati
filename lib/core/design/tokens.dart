// GENERATED FILE - DO NOT EDIT BY HAND.
// Source: خطتي اليومية، الإصدار 3.html (sha256 a2822e82314e)
// Regenerate with: node tools/extract_tokens.mjs
//
// Every colour, radius, size and duration in the app comes from here so the
// Flutter UI cannot drift from the approved HTML prototype.

import 'dart:ui' show Color;

/// Semantic colour tokens for one theme.
class KhutatiPalette {
  const KhutatiPalette({
    required this.bg,
    required this.card,
    required this.card2,
    required this.line,
    required this.tx,
    required this.mute,
    required this.red,
    required this.redtx,
    required this.ok,
    required this.gold,
  });

  final Color bg;
  final Color card;
  final Color card2;
  final Color line;
  final Color tx;
  final Color mute;
  final Color red;
  final Color redtx;
  final Color ok;
  final Color gold;
}

/// Subject identity colour, taken from the prototype's subject palette.
class SubjectAccent {
  const SubjectAccent({required this.key, required this.label, required this.accent});

  final String key;
  final String label;
  final Color accent;
}

abstract final class KColors {
  static const KhutatiPalette dark = KhutatiPalette(
    bg: Color(0xFF0D1A2D),
    card: Color(0xFF15263F),
    card2: Color(0xFF1C3150),
    line: Color(0xFF26395A),
    tx: Color(0xFFEAE5DA),
    mute: Color(0xFF93A1B8),
    red: Color(0xFFB52A20),
    redtx: Color(0xFFF0766B),
    ok: Color(0xFF7CCBB0),
    gold: Color(0xFFE8B65A),
  );

  static const KhutatiPalette light = KhutatiPalette(
    bg: Color(0xFFF3EEE5),
    card: Color(0xFFFFFCF6),
    card2: Color(0xFFF8F2E7),
    line: Color(0xFFE2D9C8),
    tx: Color(0xFF16233A),
    mute: Color(0xFF55637A),
    red: Color(0xFFB52A20),
    redtx: Color(0xFFA8241B),
    ok: Color(0xFF1F7A5F),
    gold: Color(0xFF8F6210),
  );

  static const Map<String, SubjectAccent> subjects = <String, SubjectAccent>{
    'ch': SubjectAccent(key: 'ch', label: 'الكيمياء الطبية', accent: Color(0xFF6AA6FF)),
    'ph': SubjectAccent(key: 'ph', label: 'الفيزياء', accent: Color(0xFF5DD6C0)),
    'en': SubjectAccent(key: 'en', label: 'الانكليزي', accent: Color(0xFFF0A8C8)),
    'hi': SubjectAccent(key: 'hi', label: 'تاريخ الطب', accent: Color(0xFFE8B65A)),
    'bi': SubjectAccent(key: 'bi', label: 'البيولوجيا', accent: Color(0xFFF0766B)),
  };

  static SubjectAccent subject(String key) => subjects[key] ?? subjects['ch']!;
}

abstract final class KTypography {
  static const String bodyFamily = 'IBM Plex Sans Arabic';
  static const String displayFamily = 'Reem Kufi';
  static const double bodySize = 16.0;
  static const double bodyHeight = 1.6;
  static const double h1Size = 46.0;
  static const double h1Height = 1.1;
  static const double h2Size = 20.0;
  static const double heroTitleSize = 24.0;
  static const double heroTitleHeight = 1.3;
  static const double chipSize = 13.0;
  static const double chipHeight = 1.4;
  static const double quoteSize = 15.0;
  static const double ringNumeralSize = 58.0;
  static const double statNumSize = 24.0;
  static const double timelineNumSize = 26.0;
  static const double levelNumSize = 38.0;
  static const double navLabelSize = 12.0;
  static const double pillSize = 13.0;
  static const double smallSize = 13.0;
  static const double muteSize = 14.0;
  static const double tagSize = 12.0;
  static const double counterSize = 13.0;
}

abstract final class KMetrics {
  static const double appPaddingX = 18.0;
  static const double appPaddingTop = 16.0;
  static const double appPaddingBottom = 130.0;
  static const double cardRadius = 16.0;
  static const double heroRadius = 18.0;
  static const double navRadius = 30.0;
  static const double navInset = 16.0;
  static const double navBottom = 12.0;
  static const double navPadding = 6.0;
  static const double navItemRadius = 24.0;
  static const double navIconSize = 22.0;
  static const double pillRadius = 999.0;
  static const double pillPaddingX = 12.0;
  static const double pillPaddingY = 4.0;
  static const double pillMinHeight = 32.0;
  static const double buttonRadius = 12.0;
  static const double buttonMinHeight = 44.0;
  static const double buttonPaddingX = 16.0;
  static const double buttonPaddingY = 10.0;
  static const double chipRadius = 12.0;
  static const double chipMinHeight = 52.0;
  static const double statRadius = 14.0;
  static const double levelRadius = 18.0;
  static const double timelineAccentWidth = 4.0;
  static const double timelineRowMinHeight = 56.0;
  static const double ringSize = 240.0;
  static const double ringRadius = 104.0;
  static const double ringStroke = 10.0;
  static const double ecgHeight = 52.0;
  static const double ecgStroke = 2.5;
  static const double barHeight = 8.0;
  static const double barRadius = 4.0;
  static const double mapColumns = 17.0;
  static const double mapGap = 4.0;
  static const double toastRadius = 999.0;
  static const double toastBottom = 92.0;
  static const double tapTarget = 48.0;
  static const double gridGap = 8.0;
  static const double sectionGap = 12.0;
  static const double cardGap = 10.0;
  static const double tagPaddingX = 10.0;
  static const double tagPaddingY = 1.0;
  static const double heroPadding = 16.0;
  static const double statPaddingX = 14.0;
  static const double statPaddingY = 12.0;
  static const double timelinePaddingX = 14.0;
  static const double timelinePaddingY = 12.0;
  static const double chipPaddingX = 10.0;
  static const double chipPaddingY = 8.0;
  static const double quoteRadius = 14.0;
  static const double quotePaddingX = 14.0;
  static const double quotePaddingY = 12.0;
  static const double levelPadding = 16.0;
  static const double navMaxWidth = 408.0;
  static const double weekChartHeight = 110.0;
  static const double appMaxWidth = 440.0;
}

abstract final class KMotion {
  static const int ecgMs = 600;
  static const int navMs = 250;
  static const int toastMs = 300;
  static const int confettiMs = 1800;
  static const int cardEntranceMs = 420;
  static const int staggerMs = 70;
  static const double pressScale = 0.97;
  static const String standardCurve = 'easeInOutCubic';
  static const String emphasizedCurve = 'easeOutCubic';
}

/// Vector artwork lifted verbatim from the prototype's SVG markup.
abstract final class KArtwork {
  // ECG trace: same path data, same 300x40 viewBox, same 2.5 stroke.
  static const String ecgPath =
      'M0 20H40l6-3 6 3H80l5 3 7-22 7 30 5-11h26l8-5 10 5h50l5 3 7-22 7 30 5-11h50H300';
  static const double ecgViewWidth = 300.0;
  static const double ecgViewHeight = 40.0;
  static const double ecgStrokeWidth = 2.5;
  static const double ecgRenderedHeight = 52.0;

  // Focus ring: 240 viewBox, r=104, stroke 10, dasharray 653.
  static const double ringViewSize = 240.0;
  static const double ringRadius = 104.0;
  static const double ringStrokeWidth = 10.0;
  static const double ringCircumference = 653.0;
  static const double ringNumeralSize = 58.0;
  static const double ringCaptionSize = 16.0;

  // Hexagon card texture: 56x64 tile, stroke #888 at 20% opacity.
  static const String hexPatternPath = 'M28 2l24 14v32L28 62 4 48V16z';
  static const double hexTileWidth = 56.0;
  static const double hexTileHeight = 64.0;
  static const Color hexStroke = Color(0xFF888888);
  static const double hexOpacity = 0.2;
}
