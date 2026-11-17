import 'package:flutter/material.dart';

import '../../../app/shell/section_placeholder.dart';
import '../../../core/l10n/app_strings.dart';

/// Phase 0 scaffold for the Achievements section (إنجازاتي).
/// The full screen is built in Phase 6.3.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: AppStrings.achievements,
      message: AppStrings.achievementsPlaceholder,
    );
  }
}
