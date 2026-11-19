import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/app/theme/khutati_theme.dart';
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
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.memory();
    // Own the container instead of letting a ProviderScope dispose it with the
    // widget tree. Drift schedules a zero-delay timer when its query streams
    // are cancelled; inside the widget-test fake-async zone that timer is never
    // flushed and the isolate then waits for the full 10-minute test timeout.
    // Disposing here runs the cancellation in the test's real async zone.
    container = ProviderContainer(
      overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

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
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: KhutatiTheme.dark,
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FocusLogScreen(),
      ),
    );
  }

  /// Pumps the screen at phone width. The default 800x600 test viewport is
  /// shorter than the log header, so the lazily built mode-filter row never
  /// exists and `find.text` can only see the mode breakdown above it.
  Future<void> pumpHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
  }

  /// Taps the pill 3 px below its top edge: inside the control, outside the
  /// text, which is exactly the area that used to be dead.
  ///
  /// [id] is the pill key suffix (`range-month`, `mode-pomodoro`, …). Matching
  /// by text is not enough: the same label also appears in the mode breakdown
  /// and in session tiles, and a whole `KCard` is itself a `KInkSurface`.
  Future<void> tapPill(WidgetTester tester, String id) async {
    final Rect rect = tester.getRect(find.byKey(Key('focus-pill-$id')));
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

    await pumpHost(tester);

    // Default range is a week: today and three days ago.
    expect(summaryValue(tester), '2');

    await tapPill(tester, 'range-month');
    expect(summaryValue(tester), '3');

    await tapPill(tester, 'range-today');
    expect(summaryValue(tester), '1');

    await tapPill(tester, 'range-all');
    expect(summaryValue(tester), '3');
  });

  // The mode chips under the sessions heading only filter the list below
  // them; the summary and the mode breakdown above are scoped by the range
  // bar alone. An earlier version of this file expected the summary to drop
  // when a mode was picked, which was never the screen's contract.

  testWidgets('the selected chip is exposed to accessibility', (
    WidgetTester tester,
  ) async {
    await seed(const Duration(hours: 1));
    await pumpHost(tester);

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
