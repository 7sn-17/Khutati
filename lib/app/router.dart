import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import '../features/achievements/presentation/achievements_screen.dart';
import '../features/auth/application/guest_mode.dart';
import '../features/auth/data/supabase_auth.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/focus/presentation/focus_screen.dart';
import '../features/gallery/presentation/widget_gallery_screen.dart';
import '../features/plan/presentation/plan_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/today/presentation/past_tasks_screen.dart';
import '../features/today/presentation/today_screen.dart';
import 'router_transitions.dart';
import 'shell/app_shell.dart';

/// Root navigator, also used by app-level surfaces such as the update dialog
/// that live above the routed screen tree.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Application routes. The five sections live in a stateful shell so each tab
/// keeps its own stack, matching the prototype's persistent bottom navigation.
///
/// Authentication is a hard gate: a persisted Supabase session or a persisted
/// guest choice starts the app on Today (fully offline), and the login route is
/// the only way in without one. Signing in or out emits an auth event which
/// re-runs [GoRouter.redirect], clearing the navigation stack in both
/// directions.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final _AuthRefresh refresh = _AuthRefresh();
  final bool guestAtLaunch = ref.read(guestModeProvider);
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: SupabaseAuth.currentSession == null && !guestAtLaunch
        ? '/login'
        : '/today',
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      final bool signedIn = SupabaseAuth.currentSession != null;
      final bool guest = ref.read(guestModeProvider);
      final bool onLogin = state.matchedLocation == '/login';
      if (!signedIn && !guest) return onLogin ? null : '/login';
      if (onLogin) return '/today';
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (BuildContext context, GoRouterState state) =>
            const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell navigationShell,
        ) => AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/today',
                name: 'today',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    authEntryPage(state, const TodayScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/plan',
                name: 'plan',
                builder: (BuildContext context, GoRouterState state) =>
                    const PlanScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/focus',
                name: 'focus',
                builder: (BuildContext context, GoRouterState state) =>
                    const FocusScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/achievements',
                name: 'achievements',
                builder: (BuildContext context, GoRouterState state) =>
                    const AchievementsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                name: 'settings',
                builder: (BuildContext context, GoRouterState state) =>
                    const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      // Debug-only design gallery, opened from Today in debug builds.
      GoRoute(
        path: '/past-tasks',
        name: 'past-tasks',
        builder: (BuildContext context, GoRouterState state) {
          final int? day = int.tryParse(state.uri.queryParameters['day'] ?? '');
          return PastTasksScreen(dayNumber: day);
        },
      ),
      GoRoute(
        path: '/gallery',
        name: 'gallery',
        pageBuilder: (BuildContext context, GoRouterState state) =>
            khutatiPage(state, const WidgetGalleryScreen()),
      ),
    ],
  );
});

/// Bridges Supabase's auth stream to GoRouter's [Listenable] contract.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    _subscription = SupabaseAuth.authStateChanges.listen(
      (AuthState _) => notifyListeners(),
      onError: (Object _) {},
    );
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
