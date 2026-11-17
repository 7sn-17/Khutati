import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/settings/theme_mode_controller.dart';
import '../l10n/l10n.dart';
import 'router.dart';
import 'theme/khutati_theme.dart';

/// Root widget. Arabic-only, RTL-first, with light and dark themes built from
/// the prototype tokens (PRD sections 7 and 8).
class KhutatiApp extends ConsumerWidget {
  const KhutatiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);
    final ThemeMode themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      onGenerateTitle: (BuildContext context) => context.l10n.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: KhutatiTheme.light,
      darkTheme: KhutatiTheme.dark,
      themeMode: themeMode,
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // Force RTL even if the device locale is not Arabic: the product is
      // Arabic-first and the layout must never mirror by accident.
      builder: (BuildContext context, Widget? child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
