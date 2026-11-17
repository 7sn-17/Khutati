import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/typography/khutati_fonts.dart';
import '../../features/achievements/presentation/achievements_screen.dart';
import '../../features/focus/presentation/focus_screen.dart';
import '../../features/plan/presentation/plan_screen.dart';
import '../../features/today/presentation/today_screen.dart';

/// The app shell: four primary sections in a floating, blurred navigation bar,
/// exactly as in the prototype. Each branch keeps its own navigation stack.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const List<_NavItem> _items = <_NavItem>[
    _NavItem(label: AppStrings.today, icon: Icons.home_outlined, activeIcon: Icons.home),
    _NavItem(label: AppStrings.plan, icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month),
    _NavItem(label: AppStrings.focus, icon: Icons.timer_outlined, activeIcon: Icons.timer),
    _NavItem(label: AppStrings.achievements, icon: Icons.workspace_premium_outlined, activeIcon: Icons.workspace_premium),
  ];

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = Theme.of(context).brightness == Brightness.dark ? KColors.dark : KColors.light;

    return Scaffold(
      extendBody: true,
      body: SafeArea(bottom: false, child: navigationShell),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          left: KMetrics.navInset,
          right: KMetrics.navInset,
          bottom: MediaQuery.of(context).padding.bottom + KMetrics.navBottom,
        ),
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
    );
  }
}

class _NavItem {
  const _NavItem({required this.label, required this.icon, required this.activeIcon});

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KhutatiPalette palette = Theme.of(context).brightness == Brightness.dark ? KColors.dark : KColors.light;
    final Color foreground = selected ? palette.bg : palette.mute;

    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KMetrics.navItemRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: KMotion.navMs),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? palette.tx : Colors.transparent,
            borderRadius: BorderRadius.circular(KMetrics.navItemRadius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(selected ? item.activeIcon : item.icon, size: KMetrics.navIconSize, color: foreground),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: KhutatiFonts.body(
                  size: KTypography.navLabelSize,
                  weight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: foreground,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
