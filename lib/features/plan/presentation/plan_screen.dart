import 'package:flutter/material.dart';

import '../../../app/shell/section_placeholder.dart';
import '../../../l10n/l10n.dart';

/// Phase 0 scaffold for the Plan section (الخطة).
/// The full screen is built in Phase 3.2.
class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionPlaceholder(
      title: context.l10n.navPlan,
      message: context.l10n.planPlaceholder,
    );
  }
}
