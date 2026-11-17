import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/khutati_icons.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/typography/khutati_fonts.dart';
import '../../core/design/palette.dart';

/// The app shell: four primary sections in a floating, blurred navigation bar,
/// replicating `nav` from the prototype exactly (inset 16, radius 30, padding 6,
/// 84% card tint, 18px backdrop blur, 22px stroke icons).
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const List<_NavItem> _items = <_NavItem>[
    _NavItem(label: AppStrings.today, body: KhutatiIcons.todayBody),
    _NavItem(label: AppStrings.plan, body: KhutatiIcons.planBody),
    _NavItem(label: AppStrings.focus, body: KhutatiIcons.focusBody),
    _NavItem(label: AppStrings.achievements, body: KhutatiIcons.achievementsBody),
  ];

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = context.palette;

    return Scaffold(
      extendBody: true,
      body: SafeArea(bottom: false, child: navigationShell),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KMetrics.navInset),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: KMetrics.navMaxWidth),
              child: Padding(
                padding: const EdgeInsets.only(bottom: KMetrics.navBottom),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(KMetrics.navRadius),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(KMetrics.navPadding),
                      decoration: BoxDecoration(
                        color: palette.card.withValues(alpha: 0.84),
                        borderRadius: BorderRadius.circular(KMetrics.navRadius),
                        border: Border.all(color: palette.line),
                      ),
                      child: Row(
                        children: <Widget>[
                          for (int i = 0; i < _items.length; i++)
                            Expanded(
                              child: _NavButton(
                                item: _items[i],
                                selected: navigationShell.currentIndex == i,
                                palette: palette,
                                onTap: () => navigationShell.goBranch(
                                  i,
                                  initialLocation: i == navigationShell.currentIndex,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.label, required this.body});

  final String label;
  final String body;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final KhutatiPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected ? palette.bg : palette.mute;
    final Duration duration = Duration(milliseconds: KMotion.navMs);

    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KMetrics.navItemRadius),
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? palette.tx : Colors.transparent,
            borderRadius: BorderRadius.circular(KMetrics.navItemRadius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              KNavIcon(body: item.body, color: foreground, size: KMetrics.navIconSize),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: duration,
                curve: Curves.easeOut,
                style: KhutatiFonts.body(
                  size: KTypography.navLabelSize,
                  weight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: foreground,
                  height: 1.2,
                ),
                child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
