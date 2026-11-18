import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/notifications/focus_notifications.dart';
import '../core/settings/theme_mode_controller.dart';
import '../features/updates/presentation/update_bootstrap.dart';
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
      // Smooth, eased transition between light and dark instead of an instant
      // snap when the user flips the theme in Settings.
      themeAnimationDuration: const Duration(milliseconds: 360),
      themeAnimationCurve: Curves.easeInOutCubic,
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // Force RTL even if the device locale is not Arabic: the product is
      // Arabic-first and the layout must never mirror by accident.
      builder: (BuildContext context, Widget? child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: UpdateBootstrap(
            child: _NotificationPermissionBootstrap(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}

class _NotificationPermissionBootstrap extends StatefulWidget {
  const _NotificationPermissionBootstrap({required this.child});

  final Widget child;

  @override
  State<_NotificationPermissionBootstrap> createState() =>
      _NotificationPermissionBootstrapState();
}

class _NotificationPermissionBootstrapState
    extends State<_NotificationPermissionBootstrap> {
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _request());
  }

  Future<void> _request() async {
    if (_requested) return;
    _requested = true;
    // Ask immediately on every cold start until the permission is granted, so
    // a user who declined once is not left with a silently dead timer.
    final bool granted = await FocusNotifications.requestPermission();
    // On Android 12 and below the request returns null; the channel state is
    // what actually decides whether the alert can be posted, so trust it too
    // instead of showing the rationale on every single launch.
    if (granted || await FocusNotifications.areEnabled()) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('إذن الإشعارات'),
        content: const Text(
          'نحتاج إلى إذن الإشعارات لتشغيل مؤقت التركيز في الخلفية '
          'وتنبيهك عند انتهاء الجلسة. بدونه قد لا يعمل المؤقت بشكل موثوق.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('لاحقاً'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await FocusNotifications.requestPermission();
            },
            child: const Text('السماح'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
