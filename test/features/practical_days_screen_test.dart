import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:khutati/app/theme/khutati_theme.dart';
import 'package:khutati/core/settings/theme_mode_controller.dart';
import 'package:khutati/data/database/app_database.dart';
import 'package:khutati/data/database/database_provider.dart';
import 'package:khutati/data/import/plan_importer.dart';
import 'package:khutati/data/providers.dart';
import 'package:khutati/data/repositories/schedule_repository.dart';
import 'package:khutati/data/repositories/template_repository.dart';
import 'package:khutati/domain/plan/plan_calendar.dart';
import 'package:khutati/features/settings/presentation/practical_days_screen.dart';
import 'package:khutati/features/today/application/today_controller.dart';
import 'package:khutati/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings → «أيام العملي» after the redesign: a two-column selector, and a
/// save that confirms, toasts and returns to Settings in one gesture.
void main() {
  late AppDatabase db;
  late PlanCalendar calendar;
  late ProviderContainer container;
  late GoRouter router;

  setUp(() async {
    await initializeDateFormatting('ar');
    // Haptics read the persisted preference, so the provider that `main`
    // normally installs has to exist here too.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    db = AppDatabase.memory();
    calendar = PlanCalendar(startDate: DateTime(2026, 11, 19), totalDays: 68);
    await PlanImporter(db)
        .ensureImported(File('khutati_plan_data.json').readAsStringSync());
    container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        planCalendarProvider.overrideWith((Ref ref) async => calendar),
        todayClockProvider.overrideWith(
          (Ref ref) => Stream<DateTime>.value(DateTime(2026, 11, 20, 9)),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> open(WidgetTester tester) async {
    router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Center(child: Text('HOME'))),
        ),
        GoRoute(
          path: '/practical-days',
          builder: (BuildContext context, GoRouterState state) =>
              const PracticalDaysScreen(),
        ),
      ],
    );

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: KhutatiTheme.dark,
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );

    router.push('/practical-days');
    await tester.pumpAndSettle();
  }

  testWidgets('the selector is a grid and the count follows the selection', (
    WidgetTester tester,
  ) async {
    await open(tester);

    expect(find.byType(GridView), findsOneWidget);
    // Monday and Friday are the default pair; five cards are still available.
    expect(find.text('متاح'), findsNWidgets(5));
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.text('السبت'));
    await tester.pumpAndSettle();

    expect(find.text('متاح'), findsNWidgets(4));
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('حفظ التغيير'), findsOneWidget);
  });

  testWidgets('every changed day is reachable in the preview', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('السبت'));
    await tester.pumpAndSettle();

    final SchedulePreview preview = await container
        .read(scheduleRepositoryProvider)
        .preview(calendar, <int>[
          DateTime.monday,
          DateTime.friday,
          DateTime.saturday,
        ]);
    expect(preview.loadChanges.length, greaterThan(8));
    final int lastDay = preview.loadChanges.last.dayNumber;

    await tester.tap(find.text('حفظ التغيير'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pd-impact-list')), findsOneWidget);
    // The old sheet replaced the remainder with "N other days"; every day
    // must now be in the scrollable list instead.
    expect(find.textContaining('أخرى'), findsNothing);

    await tester.dragUntilVisible(
      find.text('اليوم $lastDay'),
      find.byKey(const Key('pd-impact-list')),
      const Offset(0, -200),
    );
    expect(find.text('اليوم $lastDay'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
  });

  testWidgets('confirming saves, toasts and returns to the caller', (
    WidgetTester tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('السبت'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ التغيير'));
    await tester.pumpAndSettle();

    expect(find.text('تأكيد تغيير أيام العملي'), findsOneWidget);

    await tester.tap(find.text('تأكيد وحفظ'));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('تم تحديث جدول الخطة.'), findsOneWidget);

    final ScheduleRepository schedule = ScheduleRepository(
      db,
      TemplateRepository(db),
    );
    expect(await schedule.practicalWeekdays(), <int>[
      DateTime.monday,
      DateTime.friday,
      DateTime.saturday,
    ]);

    // Let the toast timer finish so the test ends without pending timers.
    await tester.pump(const Duration(seconds: 3));
  });
}
