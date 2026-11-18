import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/design/widgets/controls.dart';
import '../core/design/widgets/dialogs.dart';
import '../core/device/exact_alarm_permission.dart';
import '../core/device/exact_alarm_prompt.dart';
import '../core/notifications/focus_notifications.dart';
import '../core/settings/theme_mode_controller.dart';
import '../data/sync/sync_bootstrap.dart';
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
          child: SyncBootstrap(
            child: UpdateBootstrap(
              child: _NotificationPermissionBootstrap(
                child: child ?? const SizedBox.shrink(),
              ),
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
    extends State<_NotificationPermissionBootstrap>
    with WidgetsBindingObserver {
  bool _requested = false;
  bool _exactPrompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _request());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The user may have just returned from the Alarms & reminders screen.
      if (_exactPrompted) {
        _exactPrompted = false;
        unawaited(_ensureExactAlarms());
      }
    }
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
    final bool enabled = granted || await FocusNotifications.areEnabled();
    if (enabled) {
      await _ensureExactAlarms();
      return;
    }
    if (!mounted) return;
    // This widget lives in MaterialApp.builder, above the Navigator. Showing a
    // route from here would fail with "No Navigator widget found", so every
    // dialog is anchored to the root navigator's own context.
    final BuildContext? dialogContext = rootNavigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) return;

    final bool? allow = await showKDialog<bool>(
      context: dialogContext,
      builder: (BuildContext ctx) => KDialog(
        eyebrow: 'إذن مطلوب',
        title: 'أذونات الإشعارات',
        icon: Icons.notifications_active_rounded,
        message:
            'نحتاج إلى إذن الإشعارات ليعمل مؤقت التركيز في الخلفية ويصلك '
            'تنبيه عند انتهاء الجلسة. بدونه قد يسكت المؤقت بصمت.',
        actions: <KDialogAction>[
          KDialogAction(
            label: 'السماح',
            icon: Icons.notifications_rounded,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          KDialogAction(
            label: 'لاحقاً',
            variant: KButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
        onClose: () => Navigator.of(ctx).pop(false),
      ),
    );
    if (allow != true) return;
    final bool nowGranted = await FocusNotifications.requestPermission();
    if (nowGranted || await FocusNotifications.areEnabled()) {
      await _ensureExactAlarms();
    }
  }

  /// The moment notifications are available, verify that Android will let us
  /// fire at an exact minute. This is deliberately immediate: a timer that is
  /// merely "roughly 25 minutes" is not a timer.
  Future<void> _ensureExactAlarms() async {
    if (!mounted || _exactPrompted) return;
    if (await ExactAlarmPermission.canSchedule()) return;
    if (!mounted) return;
    final BuildContext? dialogContext = rootNavigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) return;
    _exactPrompted = true;
    await showExactAlarmDialog(dialogContext);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
