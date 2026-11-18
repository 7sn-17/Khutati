import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:khutati/app/launch_gate.dart';
import 'package:khutati/core/settings/theme_mode_controller.dart';
import 'package:khutati/features/onboarding/application/onboarding_controller.dart';
import 'package:khutati/features/onboarding/presentation/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The splash is the only entry point: it must hold for its window and then
/// hand over to the welcome flow or to Today, depending on persisted state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> pumpSplash(
    WidgetTester tester, {
    required bool onboardingSeen,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (onboardingSeen) OnboardingController.storageKey: true,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
    );

    final GoRouter router = GoRouter(
      initialLocation: '/splash',
      routes: <RouteBase>[
        GoRoute(
          path: '/splash',
          builder: (BuildContext context, GoRouterState state) =>
              const SplashScreen(),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('ONBOARDING')),
        ),
        GoRoute(
          path: '/today',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('TODAY')),
        ),
      ],
    );

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      container.dispose();
    });
  }

  testWidgets('shows the wordmark and the quote', (WidgetTester tester) async {
    await pumpSplash(tester, onboardingSeen: false);

    expect(find.text('خطتي'), findsOneWidget);
    expect(find.textContaining('العلم يُبنى'), findsOneWidget);
  });

  testWidgets('holds the launch screen before navigating', (
    WidgetTester tester,
  ) async {
    await pumpSplash(tester, onboardingSeen: true);

    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('TODAY'), findsNothing);
    expect(find.text('خطتي'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('TODAY'), findsOneWidget);
  });

  testWidgets('a first run continues into onboarding', (
    WidgetTester tester,
  ) async {
    await pumpSplash(tester, onboardingSeen: false);

    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump();

    expect(find.text('ONBOARDING'), findsOneWidget);
    expect(container.read(launchReadyProvider), isTrue);
  });

  testWidgets('a returning user unlocks the launch gate', (
    WidgetTester tester,
  ) async {
    await pumpSplash(tester, onboardingSeen: true);

    expect(container.read(launchReadyProvider), isFalse);
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump();

    expect(container.read(launchReadyProvider), isTrue);
    expect(find.text('TODAY'), findsOneWidget);
  });
}
