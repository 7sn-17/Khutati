import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The four navigation glyphs, copied verbatim from the HTML prototype.
///
/// The bodies are kept as raw strings (not `IconData`) so a test can diff them
/// against the prototype source and fail if anyone redraws them by hand.
/// Presentation attributes come from the prototype's `nav svg` rule:
/// 22x22, fill none, stroke currentColor, stroke-width 1.8, round caps/joins.
abstract final class KhutatiIcons {
  static const String todayBody =
      '<path d="M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10"/>';

  static const String planBody =
      '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/>';

  static const String focusBody =
      '<circle cx="12" cy="13" r="8"/><path d="M12 9v4l3 2M9 2h6"/>';

  static const String achievementsBody =
      '<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z"/>';

  /// Bodies in the prototype's DOM order: اليوم، الخطة، التركيز، إنجازاتي.
  static const List<String> navBodies = <String>[
    todayBody,
    planBody,
    focusBody,
    achievementsBody,
  ];

  static String svg(String body) {
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="currentColor" stroke-width="1.8" '
        'stroke-linecap="round" stroke-linejoin="round">$body</svg>';
  }
}

/// Renders a prototype glyph at the navigation size, tinted to the current
/// colour the same way `stroke: currentColor` does in the prototype.
class KNavIcon extends StatelessWidget {
  const KNavIcon({
    required this.body,
    required this.color,
    this.size = 22,
    super.key,
  });

  final String body;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      KhutatiIcons.svg(body),
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
