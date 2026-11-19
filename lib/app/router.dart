import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import '../features/achievements/presentation/achievements_screen.dart';
import '../features/auth/application/guest_mode.dart';
import '../features/auth/data/supabase_auth.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/focus/presentation/focus_log_screen.dart';
import '../features/focus/presentation/focus_screen.dart';
import '../features/gallery/presentation/widget_gallery_screen.dart';
import '../features/onboarding/application/onboarding_controller.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/onboarding/presentation/splash_screen.dart';
import '../features/plan/presentation/plan_screen.dart';
import '../features/settings/presentation/practical_days_screen.dart';
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
/// Every launch starts on `/splash`. From there the gate order is fixed:
/// welcome screens on a first run, then authentication (a persisted Supabase
/// session or a persisted guest choice opens Today fully offline), then the
/// shell. Signing in or out emits an auth event which re-runs
/// [GoRouter.redirect], clearing the navigation stack in both directions.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final _AuthRefresh refresh = _AuthRefresh();
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    // Every cold start begins on the splash; it decides where to go once the
    // wordmark has landed, so the launch sequence is never skipped by a
    // restored location.
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      // The splash is the one route that is always reachable: it is the thing
      // that reads the persisted state.
      if (state.matchedLocation == '/splash') return null;
      final bool onOnboarding = state.matchedLocation == '/onboarding';
      // First launch is a hard gate: nothing else is reachable until the user
      // has been through the welcome screens.
      if (!ref.read(onboardingSeenProvider)) {
        return onOnboarding ? null : '/onboarding';
      }
      if (onOnboarding) {
        // Completing the flow lands on the same destination a normal launch
        // would have used.
        return SupabaseAuth.currentSession != null ||
                ref.read(guestModeProvider)
            ? '/today'
            : '/login';
      }
      final bool signedIn = SupabaseAuth.currentSession != null;
      final bool guest = ref.read(guestModeProvider);
      final bool onLogin = state.matchedLocation == '/login';
      if (!signedIn && !guest) return onLogin ? null : '/login';
      if (onLogin) return '/today';
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (BuildContext context, GoRouterState state) =>
            const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (BuildContext context, GoRouterState state) =>
            const OnboardingScreen(),
      ),
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
                routes: <RouteBase>[
                  GoRoute(
                    path: 'log',
                    name: 'focusLog',
                    builder: (BuildContext context, GoRouterState state) =>
                        const FocusLogScreen(),
                  ),
                ],
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
                routes: <RouteBase>[
                  GoRoute(
                    path: 'practical-days',
                    name: 'practicalDays',
                    builder: (BuildContext context, GoRouterState state) =>
                        const PracticalDaysScreen(),
                  ),
                ],
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
