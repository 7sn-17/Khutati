import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/section_placeholder.dart';
import '../../../core/design/widgets/widgets.dart';
import '../../../l10n/l10n.dart';

/// Phase 0 scaffold for the Today section (اليوم).
/// The full screen is built in Phase 3.1 on top of the plan engine.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionPlaceholder(
      title: context.l10n.appName,
      message: context.l10n.foundationSubtitle,
      footer: context.l10n.foundationProof,
      // The design gallery is a development aid, never shipped navigation.
      action: kDebugMode
          ? KButton(
              label: context.l10n.galleryOpen,
              variant: KButtonVariant.secondary,
              onPressed: () => context.push('/gallery'),
            )
          : null,
    );
  }
}
