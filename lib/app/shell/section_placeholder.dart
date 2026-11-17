import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/typography/khutati_fonts.dart';

/// Temporary section body used until each screen is built in its own phase.
///
/// It exists to prove the foundation end to end: Arabic display and body faces,
/// RTL layout, theme tokens, and the 48dp-safe spacing.
class SectionPlaceholder extends StatelessWidget {
  const SectionPlaceholder({
    required this.title,
    required this.message,
    this.footer,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final String? footer;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KhutatiPalette palette =
        theme.brightness == Brightness.dark ? KColors.dark : KColors.light;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KMetrics.appPaddingX,
        KMetrics.appPaddingTop,
        KMetrics.appPaddingX,
        KMetrics.appPaddingBottom,
      ),
      children: <Widget>[
        Text(title, style: theme.textTheme.displayLarge),
        const SizedBox(height: 8),
        Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: palette.mute)),
        if (footer != null) ...<Widget>[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(KMetrics.cardRadius),
              border: Border.all(color: palette.line),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.check_circle_outline, size: 20, color: palette.ok),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    footer!,
                    style: KhutatiFonts.body(size: KTypography.muteSize, color: palette.tx),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (action != null) ...<Widget>[
          const SizedBox(height: 16),
          action!,
        ],
      ],
    );
  }
}
