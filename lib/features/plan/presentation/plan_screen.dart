import 'package:flutter/material.dart';

import '../../../app/shell/section_placeholder.dart';
import '../../../core/l10n/app_strings.dart';

/// Phase 0 scaffold for the Plan section (الخطة).
/// The full screen is built in Phase 3.2.
class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: AppStrings.plan,
      message: AppStrings.planPlaceholder,
    );
  }
}
