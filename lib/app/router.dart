import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/achievements/presentation/achievements_screen.dart';
import '../features/focus/presentation/focus_screen.dart';
import '../features/gallery/presentation/widget_gallery_screen.dart';
import '../features/plan/presentation/plan_screen.dart';
import '../features/today/presentation/today_screen.dart';
import 'shell/app_shell.dart';

/// Application routes. Sections live in a stateful shell so each tab keeps its
/// own stack, matching the prototype's persistent bottom navigation.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  return GoRouter(
    initialLocation: '/today',
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell navigationShell,
        ) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/today',
                name: 'today',
                builder: (BuildContext context, GoRouterState state) => const TodayScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/plan',
                name: 'plan',
                builder: (BuildContext context, GoRouterState state) => const PlanScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/focus',
                name: 'focus',
                builder: (BuildContext context, GoRouterState state) => const FocusScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/achievements',
                name: 'achievements',
                builder: (BuildContext context, GoRouterState state) => const AchievementsScreen(),
              ),
            ],
          ),
        ],
      ),
      // Debug-only design gallery, opened from Today in debug builds.
      GoRoute(
        path: '/gallery',
        name: 'gallery',
        builder: (BuildContext context, GoRouterState state) => const WidgetGalleryScreen(),
      ),
    ],
  );
});
