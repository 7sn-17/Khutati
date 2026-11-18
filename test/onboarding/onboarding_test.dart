import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:khutati/core/settings/theme_mode_controller.dart';
import 'package:khutati/features/onboarding/application/onboarding_controller.dart';
import 'package:khutati/features/onboarding/presentation/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The welcome flow is shown exactly once, must be swipeable in both
/// directions, and must hand the user to the normal launch destination.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ValueKey<String> primary = ValueKey<String>('onboarding-primary');
  const ValueKey<String> skip = ValueKey<String>('onboarding-skip');

  late SharedPreferences prefs;
  late ProviderContainer container;

  Future<void> pumpOnboarding(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
    );

    final GoRouter router = GoRouter(
      initialLocation: '/onboarding',
      routes: <RouteBase>[
        GoRoute(
          path: '/onboarding',
          builder: (BuildContext context, GoRouterState state) =>
              const OnboardingScreen(),
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
      // The scene loops forever, so the tree must be torn down explicitly or
      // the tickers outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      container.dispose();
    });
  }

  Future<void> settlePage(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 520));
  }

  testWidgets('shows the first slide with a Next button', (
    WidgetTester tester,
  ) async {
    await pumpOnboarding(tester);

    // Slide one promises the 68-day curriculum.
    expect(find.text('منهاجك كله في 68 يوماً'), findsOneWidget);
    expect(find.text('التالي'), findsOneWidget);
    expect(find.text('ابدأ'), findsNothing);
    expect(find.byKey(skip), findsOneWidget);
  });

  testWidgets('Next walks the three slides and the last one starts', (
    WidgetTester tester,
  ) async {
    await pumpOnboarding(tester);

    await tester.tap(find.byKey(primary));
    await settlePage(tester);

    await tester.tap(find.byKey(primary));
    await settlePage(tester);

    expect(find.text('ابدأ'), findsOneWidget);
    expect(find.text('التالي'), findsNothing);

    await tester.tap(find.byKey(primary));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('TODAY'), findsOneWidget);
    expect(prefs.getBool(OnboardingController.storageKey), isTrue);
  });

  testWidgets('skip finishes the flow immediately', (
    WidgetTester tester,
  ) async {
    await pumpOnboarding(tester);

    await tester.tap(find.byKey(skip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('TODAY'), findsOneWidget);
    expect(prefs.getBool(OnboardingController.storageKey), isTrue);
  });

  testWidgets('a dot jumps straight to its slide', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpOnboarding(tester);

    await tester.tap(find.bySemanticsLabel('الشاشة 3'));
    await settlePage(tester);

    expect(find.text('ابدأ'), findsOneWidget);
    semantics.dispose();
  });

  test('complete() persists and is idempotent', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences store = await SharedPreferences.getInstance();
    final ProviderContainer scope = ProviderContainer(
      overrides: <Override>[sharedPreferencesProvider.overrideWithValue(store)],
    );
    addTearDown(scope.dispose);

    expect(scope.read(onboardingSeenProvider), isFalse);
    await scope.read(onboardingSeenProvider.notifier).complete();
    expect(scope.read(onboardingSeenProvider), isTrue);
    expect(store.getBool(OnboardingController.storageKey), isTrue);

    // A second call must not flip anything back or throw.
    await scope.read(onboardingSeenProvider.notifier).complete();
    expect(scope.read(onboardingSeenProvider), isTrue);
  });
}
