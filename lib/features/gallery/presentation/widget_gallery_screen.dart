import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/settings/theme_mode_controller.dart';

/// Debug-only gallery that renders every design primitive in the live theme.
/// Reachable from Today in debug builds; not part of the shipped navigation.
class WidgetGalleryScreen extends ConsumerWidget {
  const WidgetGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final KhutatiPalette palette = context.palette;
    final ThemeMode mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.galleryTitle),
        actions: <Widget>[
          IconButton(
            tooltip: AppStrings.galleryTheme,
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
              const KPill(label: 'سلسلة', value: '9'),
              const SizedBox(width: 8),
              const KPill(label: 'نقاط', value: '260'),
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
                  AppStrings.galleryDemoTask,
                  style: TextStyle(
                    fontFamily: KTypography.displayFamily,
                    fontSize: KTypography.heroTitleSize,
                    fontWeight: FontWeight.w700,
                    color: palette.tx,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.galleryDemoRange,
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
              AppStrings.galleryDemoRange,
              style: TextStyle(fontFamily: KTypography.bodyFamily, color: palette.tx),
            ),
          ),
          const KSectionHeader(title: 'الخط الكهربائي'),
          const KEcgLine(progress: 0.62),
          const KSectionHeader(title: 'شريط التقدم'),
          const KProgressBar(value: 0.38),
          const SizedBox(height: 12),
          const KProgressBar(value: 0.72, color: Color(0xFF6AA6FF)),
          const KSectionHeader(title: 'حلقة التركيز'),
          Center(
            child: KProgressRing(
              progress: 0.68,
              numeral: '25:00',
              caption: AppStrings.galleryFocusCaption,
              color: KColors.subject('ph').accent,
            ),
          ),
          const KSectionHeader(title: 'الخطوات'),
          Row(
            children: <Widget>[
              Expanded(
                child: KChip(
                  title: 'حضور',
                  subtitle: AppStrings.galleryDemoRange,
                  selected: false,
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KChip(
                  title: 'دراسة',
                  subtitle: AppStrings.galleryDemoRange,
                  selected: true,
                  onTap: () {},
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          KChip(
            title: 'تم حل الأسئلة',
            subtitle: AppStrings.galleryDemoRange,
            selected: false,
            wide: true,
            onTap: () {},
          ),
          const KSectionHeader(title: 'الأزرار'),
          Row(
            children: <Widget>[
              KButton(label: 'ابدأ التركيز', onPressed: () {}),
              const SizedBox(width: 8),
              KButton(
                label: 'تخطَّ',
                variant: KButtonVariant.secondary,
                onPressed: () {},
              ),
            ],
          ),
          const KSectionHeader(title: 'الاستراحات'),
          const KBreakDivider(label: 'استراحة 15 د، 9:14 – 9:30'),
          const KSectionHeader(title: 'التنبيهات'),
          KButton(
            label: AppStrings.galleryToastAction,
            variant: KButtonVariant.secondary,
            onPressed: () => showKToast(context, AppStrings.galleryToast),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: KConfetti(play: true),
          ),
        ],
      ),
    );
  }
}
