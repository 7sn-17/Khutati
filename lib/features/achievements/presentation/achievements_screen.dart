import 'package:flutter/material.dart';

import '../../../app/shell/section_placeholder.dart';
import '../../../l10n/l10n.dart';

/// Phase 0 scaffold for the Achievements section (إنجازاتي).
/// The full screen is built in Phase 6.3.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionPlaceholder(
      title: context.l10n.navAchievements,
      message: context.l10n.achievementsPlaceholder,
    );
  }
}
