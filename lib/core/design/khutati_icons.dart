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

/// Official brand glyphs (Simple Icons, CC0) for the developer contact tiles.
/// They are single-path logos, so they render crisply at any size without
/// bundling bitmap assets.
abstract final class KhutatiBrandIcons {
  static const String telegramPath =
      'M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 '
      '12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 '
      '.171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 '
      '1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78'
      '-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174'
      '-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252'
      '-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 '
      '5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z';

  static const String whatsappPath =
      'M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966'
      '-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48'
      '-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198'
      '-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487'
      '-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 '
      '2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 '
      '1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173'
      '-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214'
      '-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 '
      '2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 '
      '9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 '
      '4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 '
      '11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413Z';

  /// Brand colours, as published by each service.
  static const Color telegram = Color(0xFF26A5E4);
  static const Color whatsapp = Color(0xFF25D366);
}

/// A filled brand mark inside a soft rounded square, used for contact rows.
class KBrandMark extends StatelessWidget {
  const KBrandMark({
    required this.path,
    required this.color,
    this.size = 40,
    super.key,
  });

  final String path;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: SvgPicture.string(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="#FFFFFF"><path d="$path"/></svg>',
        width: size * 0.58,
        height: size * 0.58,
      ),
    );
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
