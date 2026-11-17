import 'package:flutter/material.dart';

import '../../../app/shell/section_placeholder.dart';
import '../../../core/l10n/app_strings.dart';

/// Phase 0 scaffold for the Today section (اليوم).
/// The full screen is built in Phase 3.1 on top of the plan engine.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: AppStrings.appName,
      message: AppStrings.foundationSubtitle,
      footer: AppStrings.foundationProof,
    );
  }
}
