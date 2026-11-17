import 'package:flutter/material.dart';

import '../../../app/shell/section_placeholder.dart';
import '../../../l10n/l10n.dart';

/// Phase 0 scaffold for the Focus section (التركيز).
/// The timer UI is built in Phase 4.3, the native service in Phase 4.1.
class FocusScreen extends StatelessWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionPlaceholder(
      title: context.l10n.navFocus,
      message: context.l10n.focusPlaceholder,
    );
  }
}
