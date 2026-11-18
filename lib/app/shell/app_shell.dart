import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/khutati_icons.dart';
import '../../features/focus/application/focus_controller.dart';
import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/motion/haptics.dart';
import '../../core/motion/press_scale.dart';
import '../../core/typography/khutati_fonts.dart';
import '../../l10n/l10n.dart';

/// The app shell: five primary sections in a floating, blurred navigation bar.
///
/// Geometry, colour and the four prototype glyphs come from the HTML. The
/// settings glyph is a Material outline icon because the prototype predates the
/// fifth tab; it is drawn at the same 22dp / 1.8 stroke rhythm.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final KhutatiPalette palette = context.palette;
    final AppLocalizations l10n = context.l10n;
    final FocusSessionState focusSession = ref.watch(focusControllerProvider);
    final bool focusActive = focusSession.isRunning || focusSession.isPaused;

    final List<_NavItem> items = <_NavItem>[
      _NavItem(label: l10n.navToday, svgBody: KhutatiIcons.todayBody),
      _NavItem(label: l10n.navPlan, svgBody: KhutatiIcons.planBody),
      _NavItem(label: l10n.navFocus, svgBody: KhutatiIcons.focusBody),
      _NavItem(
        label: l10n.navAchievements,
        svgBody: KhutatiIcons.achievementsBody,
      ),
      _NavItem(
        label: l10n.navSettings,
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: SafeArea(bottom: false, child: navigationShell),
      bottomNavigationBar: focusActive
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KMetrics.navInset,
                ),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: KMetrics.navMaxWidth,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(
                        bottom: KMetrics.navBottom,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(KMetrics.navRadius),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            padding: const EdgeInsets.all(KMetrics.navPadding),
                            decoration: BoxDecoration(
                              color: palette.card.withValues(alpha: 0.84),
                              borderRadius: BorderRadius.circular(
                                KMetrics.navRadius,
                              ),
                              border: Border.all(color: palette.line),
                            ),
                            child: LayoutBuilder(
                              builder:
                                  (
                                    BuildContext context,
                                    BoxConstraints constraints,
                                  ) {
                                    final int count = items.length;
                                    final double slotWidth =
                                        constraints.maxWidth / count;
                                    final int index =
                                        navigationShell.currentIndex;
                                    return Stack(
                                      children: <Widget>[
                                        // Springy sliding selection pill behind the tabs. Uses the
                                        // directional variant so the highlight follows the tapped tab
                                        // exactly under RTL (Arabic) layouts.
                                        AnimatedPositionedDirectional(
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          curve: Curves.easeOutBack,
                                          start: index * slotWidth,
                                          top: 0,
                                          bottom: 0,
                                          width: slotWidth,
                                          child: Padding(
                                            padding: const EdgeInsets.all(2),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: palette.tx,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      KMetrics.navItemRadius,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Row(
                                          children: <Widget>[
                                            for (
                                              int i = 0;
                                              i < items.length;
                                              i++
                                            )
                                              Expanded(
                                                child: _NavButton(
                                                  item: items[i],
                                                  selected:
                                                      navigationShell
                                                          .currentIndex ==
                                                      i,
                                                  palette: palette,
                                                  onTap: () {
                                                    ref
                                                        .read(hapticsProvider)
                                                        .selection();
                                                    navigationShell.goBranch(
                                                      i,
                                                      initialLocation:
                                                          i ==
                                                          navigationShell
                                                              .currentIndex,
                                                    );
                                                  },
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    );
                                  },
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
  const _NavItem({
    required this.label,
    this.svgBody,
    this.icon,
    this.activeIcon,
  }) : assert(svgBody != null || icon != null, 'a nav item needs a glyph');

  final String label;
  final String? svgBody;
  final IconData? icon;
  final IconData? activeIcon;
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

    final Widget glyph = item.svgBody != null
        ? KNavIcon(
            body: item.svgBody!,
            color: foreground,
            size: KMetrics.navIconSize,
          )
        : Icon(
            selected ? (item.activeIcon ?? item.icon) : item.icon,
            size: KMetrics.navIconSize,
            color: foreground,
          );

    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: PressScale(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KMetrics.navItemRadius),
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(KMetrics.navItemRadius),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                glyph,
                const SizedBox(height: 2),
                // Five labels in 360dp is tight: scale down instead of
                // truncating Arabic words.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedDefaultTextStyle(
                    duration: duration,
                    curve: Curves.easeOut,
                    style: KhutatiFonts.body(
                      size: KTypography.navLabelSize,
                      weight: selected ? FontWeight.w500 : FontWeight.w400,
                      color: foreground,
                      height: 1.2,
                    ),
                    child: Text(item.label, maxLines: 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
