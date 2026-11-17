import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/app/theme/khutati_theme.dart';
import 'package:khutati/core/design/tokens.dart';
import 'package:khutati/core/design/widgets/widgets.dart';

Widget host(Widget child) {
  return MaterialApp(
    theme: KhutatiTheme.dark,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('KCard paints the prototype hexagon texture', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(const KCard(child: Text('x'))));

    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is CustomPaint && widget.painter is HexagonPatternPainter,
      ),
      findsOneWidget,
    );
  });

  testWidgets('KCard can drop the texture', (WidgetTester tester) async {
    await tester.pumpWidget(
      host(const KCard(showPattern: false, child: Text('x'))),
    );

    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is CustomPaint && widget.painter is HexagonPatternPainter,
      ),
      findsNothing,
    );
  });

  testWidgets('KChip fills with --ok when selected', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        KChip(
          title: 'حضور',
          subtitle: '8:00 – 8:23',
          selected: true,
          onTap: () {},
        ),
      ),
    );

    final AnimatedContainer container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(KChip),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final BoxDecoration decoration = container.decoration! as BoxDecoration;

    expect(decoration.color, KColors.dark.ok);
    expect(decoration.border, isNotNull);
  });

  testWidgets('KChip reports taps', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(
      host(
        KChip(
          title: 'دراسة',
          subtitle: '8:23 – 8:35',
          selected: false,
          onTap: () => taps++,
        ),
      ),
    );

    await tester.tap(find.byType(KChip));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('KProgressBar fills the requested fraction', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(const SizedBox(width: 200, child: KProgressBar(value: 0.38))),
    );

    final FractionallySizedBox box = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: find.byType(KProgressBar),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(box.widthFactor, 0.38);
    expect(
      tester.getSize(find.byType(KProgressBar)).height,
      KMetrics.barHeight,
    );
  });

  testWidgets('KProgressRing renders its numeral at the prototype size', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        const KProgressRing(
          progress: 0.5,
          numeral: '25:00',
          caption: 'وقت التركيز',
        ),
      ),
    );

    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('وقت التركيز'), findsOneWidget);
    expect(tester.getSize(find.byType(KProgressRing)).width, KMetrics.ringSize);
    expect(
      tester.getSize(find.byType(KProgressRing)).height,
      KMetrics.ringSize,
    );
  });

  testWidgets('KEcgLine keeps the prototype height and animates', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(const KEcgLine(progress: 0.62)));

    expect(tester.getSize(find.byType(KEcgLine)).height, KMetrics.ecgHeight);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('KTag pins its label to the dark background colour', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(const KTag(label: 'الفيزياء', color: Color(0xFF5DD6C0))),
    );

    final Text label = tester.widget<Text>(find.text('الفيزياء'));
    expect(label.style?.color, KColors.dark.bg);
  });

  testWidgets('showKToast displays a message and removes itself', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showKToast(context, 'أحسنت'),
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('أحسنت'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('أحسنت'), findsNothing);
  });
}
