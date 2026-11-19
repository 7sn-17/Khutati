import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/app/theme/khutati_theme.dart';
import 'package:khutati/core/design/widgets/widgets.dart';
import 'package:khutati/data/database/app_database.dart';
import 'package:khutati/data/database/database_provider.dart';
import 'package:khutati/features/focus/presentation/focus_log_screen.dart';
import 'package:khutati/l10n/l10n.dart';

/// The range chips once wrapped their label in a bare `GestureDetector`, which
/// defers hit testing to the text glyph. Taps in the pill's padding — most of
/// its surface — did nothing, so the filter looked broken.
///
/// These tests tap inside the pill but *outside* the label and assert the
/// summary follows, which is the behaviour a user expects from a segmented
/// control.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  Future<void> seed(Duration ago, {bool completed = true}) async {
    final DateTime start = DateTime.now().subtract(ago);
    await db
        .into(db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            clientId: Value('session-${start.microsecondsSinceEpoch}'),
            mode: const Value<String>('pomodoro'),
            phase: 'focus',
            plannedSeconds: 1500,
            actualSeconds: 1500,
            startedAt: start,
            endedAt: Value(start.add(const Duration(minutes: 25))),
            completed: Value(completed),
          ),
        );
  }

  Widget host() {
    return ProviderScope(
      overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: KhutatiTheme.dark,
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FocusLogScreen(),
      ),
    );
  }

  /// Taps the pill 3 px below its top edge: inside the control, outside the
  /// text, which is exactly the area that used to be dead.
  Future<void> tapPill(WidgetTester tester, String label) async {
    final Finder pill = find
        .ancestor(
          of: find.text(label).first,
          matching: find.byType(KInkSurface),
        )
        .first;
    final Rect rect = tester.getRect(pill);
    await tester.tapAt(Offset(rect.center.dx, rect.top + 3));
    await tester.pumpAndSettle();
  }

  /// The session count lives in the first stat of the summary card. It is read
  /// by key because a figure like `1` also appears in the streak badge.
  String summaryValue(WidgetTester tester) {
    return tester
        .widget<Text>(find.byKey(const Key('focus-log-sessions')))
        .data!;
  }

  testWidgets('range chips respond to taps in their padding', (
    WidgetTester tester,
  ) async {
    await seed(const Duration(hours: 1));
    await seed(const Duration(days: 3));
    await seed(const Duration(days: 20));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // Default range is a week: today and three days ago.
    expect(summaryValue(tester), '2');

    await tapPill(tester, 'الشهر');
    expect(summaryValue(tester), '3');

    await tapPill(tester, 'اليوم');
    expect(summaryValue(tester), '1');

    await tapPill(tester, 'الكل');
    expect(summaryValue(tester), '3');
  });

  testWidgets('mode chips filter the list as well', (
    WidgetTester tester,
  ) async {
    await seed(const Duration(hours: 2));
    final DateTime older = DateTime.now().subtract(const Duration(days: 2));
    await db
        .into(db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            clientId: Value('free-${older.microsecondsSinceEpoch}'),
            mode: const Value<String>('free'),
            phase: 'focus',
            plannedSeconds: 900,
            actualSeconds: 900,
            startedAt: older,
            endedAt: Value(older.add(const Duration(minutes: 15))),
          ),
        );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(summaryValue(tester), '2');

    await tapPill(tester, 'بومودورو');
    expect(summaryValue(tester), '1');

    await tapPill(tester, 'مؤقت حر');
    expect(summaryValue(tester), '1');
  });

  testWidgets('the selected chip is exposed to accessibility', (
    WidgetTester tester,
  ) async {
    await seed(const Duration(hours: 1));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // The pill wraps its control in a Semantics node, so a screen reader reads
    // "selected" without needing the visual fill. InkWell adds its own
    // Semantics node around the text, so match on the label instead of order.
    final Finder chip = find.byWidgetPredicate(
      (Widget widget) =>
          widget is Semantics && widget.properties.label == 'الأسبوع',
    );
    expect(chip, findsOneWidget);
    final Semantics node = tester.widget<Semantics>(chip);
    expect(node.properties.selected, isTrue);
    expect(node.properties.button, isTrue);
  });
}
