import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:khutati/app/theme/khutati_theme.dart';
import 'package:khutati/core/design/widgets/widgets.dart';
import 'package:khutati/core/settings/theme_mode_controller.dart';
import 'package:khutati/core/utils/format.dart';
import 'package:khutati/data/database/app_database.dart';
import 'package:khutati/data/database/database_provider.dart';
import 'package:khutati/data/import/plan_importer.dart';
import 'package:khutati/data/providers.dart';
import 'package:khutati/data/repositories/schedule_repository.dart';
import 'package:khutati/domain/plan/plan_calendar.dart';
import 'package:khutati/features/plan/presentation/reschedule_screen.dart';
import 'package:khutati/features/today/application/today_controller.dart';
import 'package:khutati/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The rescheduling screen replaced a one-task bottom sheet. These tests drive
/// the two gestures that matter — the arrows and the save — against the real
/// in-memory plan, so a regression in the draft, the preview or the pop is
/// caught without a device.
void main() {
  late AppDatabase db;
  late PlanCalendar calendar;
  late ProviderContainer container;
  late GoRouter router;

  setUp(() async {
    // The screen prints weekday names with the Arabic locale, which `main`
    // initialises at startup.
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
        // Day 2 of the plan is Friday 20 November 2026, so the screen opens on
        // week one.
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
          path: '/reschedule',
          builder: (BuildContext context, GoRouterState state) =>
              const RescheduleScreen(),
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

    router.push('/reschedule');
    await tester.pumpAndSettle();
  }

  Future<ScheduleSnapshot> snapshot() =>
      container.read(scheduleRepositoryProvider).load(calendar);

  /// Finds the first day of week one that has more than one task, so the
  /// up/down arrows are both meaningful, without expanding it.
  Future<({ScheduledDay day, List<ScheduledTask> tasks, Finder label})>
  firstFullDay(WidgetTester tester) async {
    final ScheduleSnapshot data = await snapshot();
    final ScheduledDay day = data.days.firstWhere(
      (ScheduledDay item) =>
          item.week == 1 &&
          !item.isRest &&
          data.tasksForDay(item.dayNumber).length >= 2,
    );
    final String name = KhutatiFormat.westernDigits(
      DateFormat('EEEE', 'ar').format(calendar.dateOfDay(day.dayNumber)),
    );
    final Finder label = find.text(name);
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    return (day: day, tasks: data.tasksForDay(day.dayNumber), label: label);
  }

  /// Opens the first day of week one that has more than one task.
  Future<({ScheduledDay day, List<ScheduledTask> tasks})> expandFirstFullDay(
    WidgetTester tester,
  ) async {
    final ({ScheduledDay day, List<ScheduledTask> tasks, Finder label}) data =
        await firstFullDay(tester);
    await tester.ensureVisible(data.label);
    await tester.pumpAndSettle();
    await tester.tap(data.label);
    await tester.pumpAndSettle();
    return (day: data.day, tasks: data.tasks);
  }

  testWidgets('dragging a day header scrolls without expanding it', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final ({ScheduledDay day, List<ScheduledTask> tasks, Finder label}) data =
        await firstFullDay(tester);

    expect(find.text(data.tasks.first.task.title), findsNothing);
    await tester.drag(data.label, const Offset(0, -250));
    await tester.pumpAndSettle();

    expect(find.text(data.tasks.first.task.title), findsNothing);
  });

  testWidgets('tapping a task row does not collapse its day', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final ({ScheduledDay day, List<ScheduledTask> tasks}) data =
        await expandFirstFullDay(tester);

    await tester.tap(find.text(data.tasks.first.task.title).first);
    await tester.pumpAndSettle();

    // The row opens the move panel; the day around it must stay expanded.
    expect(find.textContaining('نقل «'), findsOneWidget);
    expect(find.text(data.tasks.first.task.title), findsOneWidget);
  });

  testWidgets('a day expands, and an arrow makes a pending change', (
    WidgetTester tester,
  ) async {
    await open(tester);

    expect(find.text('HOME'), findsNothing);
    expect(find.text('الأسبوع 1 من 10'), findsOneWidget);
    // Nothing pending yet: no impact panel, save is idle.
    expect(find.text('أثر التعديل'), findsNothing);
    expect(find.text('حفظ التعديلات'), findsOneWidget);

    final ({ScheduledDay day, List<ScheduledTask> tasks}) data =
        await expandFirstFullDay(tester);
    final List<ScheduledTask> tasks = data.tasks;
    expect(find.text(tasks.first.task.title), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('أثر التعديل'), findsOneWidget);
    expect(find.text('حفظ 1'), findsOneWidget);
    // The moved task is still on the same day, now one slot later.
    expect(find.text(tasks[1].task.title), findsOneWidget);
  });

  testWidgets('the move panel previews a destination and can be cancelled', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final ({ScheduledDay day, List<ScheduledTask> tasks}) data =
        await expandFirstFullDay(tester);

    await tester.tap(find.text(data.tasks.first.task.title));
    await tester.pumpAndSettle();

    expect(find.textContaining('نقل «'), findsOneWidget);
    expect(find.text('إلى اليوم'), findsOneWidget);
    expect(find.text('الترتيب'), findsOneWidget);

    await tester.tap(find.widgetWithText(KButton, 'إلغاء').first);
    await tester.pumpAndSettle();

    expect(find.text('إلى اليوم'), findsNothing);
    expect(find.text('أثر التعديل'), findsNothing);
  });

  testWidgets('saving persists the move and returns to the previous screen', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final ScheduledDay day = (await expandFirstFullDay(tester)).day;

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('حفظ 1'), findsOneWidget);

    await tester.tap(find.text('حفظ 1'));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('تم حفظ ترتيب المهام.'), findsOneWidget);

    final List<ScheduleOverrideRow> rows = await db
        .select(db.scheduleOverrides)
        .get();
    expect(rows, hasLength(1));
    expect(rows.single.dayNumber, day.dayNumber);

    // Let the toast timer finish so the test ends without pending timers.
    await tester.pump(const Duration(seconds: 3));
  });
}
