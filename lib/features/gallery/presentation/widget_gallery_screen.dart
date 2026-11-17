import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/settings/theme_mode_controller.dart';
import '../../../l10n/l10n.dart';

/// Debug-only gallery that renders every design primitive in the live theme.
/// Reachable from Today in debug builds; not part of the shipped navigation.
class WidgetGalleryScreen extends ConsumerWidget {
  const WidgetGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final KhutatiPalette palette = context.palette;
    final AppLocalizations l10n = context.l10n;
    final ThemeMode mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.galleryTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.galleryTheme,
            onPressed: () => ref.read(themeModeProvider.notifier).cycle(),
            icon: Icon(switch (mode) {
              ThemeMode.system => Icons.brightness_auto,
              ThemeMode.dark => Icons.dark_mode,
              ThemeMode.light => Icons.light_mode,
            }),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          KMetrics.appPaddingX,
          KMetrics.appPaddingTop,
          KMetrics.appPaddingX,
          KMetrics.appPaddingBottom,
        ),
        children: <Widget>[
          Row(
            children: <Widget>[
              KPill(label: l10n.galleryPillStreak, value: '9'),
              const SizedBox(width: 8),
              KPill(label: l10n.galleryPillPoints, value: '260'),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final SubjectAccent subject in KColors.subjects.values)
                KTag(label: subject.label, color: subject.accent),
            ],
          ),
          const SizedBox(height: 16),
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.galleryDemoTask,
                  style: TextStyle(
                    fontFamily: KTypography.displayFamily,
                    fontSize: KTypography.heroTitleSize,
                    fontWeight: FontWeight.w700,
                    color: palette.tx,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.galleryDemoRange,
                  style: TextStyle(
                    fontFamily: KTypography.bodyFamily,
                    fontSize: KTypography.smallSize,
                    color: palette.mute,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          KCard(
            accentColor: KColors.subject('ch').accent,
            child: Text(
              l10n.galleryDemoRange,
              style: TextStyle(fontFamily: KTypography.bodyFamily, color: palette.tx),
            ),
          ),
          KSectionHeader(title: l10n.galleryEcg),
          const KEcgLine(progress: 0.62),
          KSectionHeader(title: l10n.galleryBar),
          const KProgressBar(value: 0.38),
          const SizedBox(height: 12),
          const KProgressBar(value: 0.72, color: Color(0xFF6AA6FF)),
          KSectionHeader(title: l10n.galleryRing),
          Center(
            child: KProgressRing(
              progress: 0.68,
              numeral: '25:00',
              caption: l10n.galleryFocusCaption,
              color: KColors.subject('ph').accent,
            ),
          ),
          KSectionHeader(title: l10n.gallerySteps),
          Row(
            children: <Widget>[
              Expanded(
                child: KChip(
                  title: l10n.galleryAttend,
                  subtitle: l10n.galleryDemoRange,
                  selected: false,
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KChip(
                  title: l10n.galleryStudy,
                  subtitle: l10n.galleryDemoRange,
                  selected: true,
                  onTap: () {},
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          KChip(
            title: l10n.gallerySolve,
            subtitle: l10n.galleryDemoRange,
            selected: false,
            wide: true,
            onTap: () {},
          ),
          KSectionHeader(title: l10n.galleryButtons),
          Row(
            children: <Widget>[
              KButton(label: l10n.galleryStart, onPressed: () {}),
              const SizedBox(width: 8),
              KButton(
                label: l10n.gallerySkip,
                variant: KButtonVariant.secondary,
                onPressed: () {},
              ),
            ],
          ),
          KSectionHeader(title: l10n.galleryBreaks),
          KBreakDivider(label: l10n.galleryBreakLabel),
          KSectionHeader(title: l10n.galleryFeedback),
          KButton(
            label: l10n.galleryToastAction,
            variant: KButtonVariant.secondary,
            onPressed: () => showKToast(context, l10n.galleryToast),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: const KConfetti(play: true),
          ),
        ],
      ),
    );
  }
}
