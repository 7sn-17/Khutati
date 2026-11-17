import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/app/theme/khutati_theme.dart';
import 'package:khutati/core/design/tokens.dart';

/// Guards theme parity with the HTML prototype.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dark theme', () {
    final ThemeData theme = KhutatiTheme.dark;

    test('uses the prototype surface and accent tokens', () {
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, KColors.dark.bg);
      expect(theme.colorScheme.surface, KColors.dark.card);
      expect(theme.colorScheme.surfaceContainerHighest, KColors.dark.card2);
      expect(theme.colorScheme.primary, KColors.dark.red);
      expect(theme.colorScheme.secondary, KColors.dark.ok);
      expect(theme.colorScheme.tertiary, KColors.dark.gold);
      expect(theme.colorScheme.onSurface, KColors.dark.tx);
      expect(theme.dividerColor, KColors.dark.line);
    });

    test('applies the prototype type scale', () {
      expect(theme.textTheme.displayLarge?.fontSize, KTypography.h1Size);
      expect(theme.textTheme.displayLarge?.fontWeight, FontWeight.w700);
      expect(theme.textTheme.headlineSmall?.fontSize, KTypography.h2Size);
      expect(theme.textTheme.bodyMedium?.fontSize, KTypography.bodySize);
      expect(theme.textTheme.bodyMedium?.height, KTypography.bodyHeight);
      expect(theme.textTheme.bodySmall?.fontSize, KTypography.smallSize);
      expect(theme.textTheme.labelSmall?.fontSize, KTypography.tagSize);
    });

    test('every style resolves to a bundled Arabic family', () {
      final List<TextStyle?> styles = <TextStyle?>[
        theme.textTheme.displayLarge,
        theme.textTheme.headlineSmall,
        theme.textTheme.titleLarge,
        theme.textTheme.bodyMedium,
        theme.textTheme.bodySmall,
      ];
      for (final TextStyle? style in styles) {
        expect(style?.fontFamily, isNotNull);
      }
      // Headings and body must not collapse onto the same family.
      expect(
        theme.textTheme.displayLarge?.fontFamily,
        isNot(theme.textTheme.bodyMedium?.fontFamily),
      );
    });

    test('keeps 48dp tap targets', () {
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
    });
  });

  group('light theme', () {
    final ThemeData theme = KhutatiTheme.light;

    test('uses the light overrides from the prototype', () {
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, KColors.light.bg);
      expect(theme.colorScheme.surface, KColors.light.card);
      expect(theme.colorScheme.onSurface, KColors.light.tx);
      expect(theme.colorScheme.error, KColors.light.redtx);
    });

    test('dark and light never share the background colour', () {
      expect(
        KhutatiTheme.light.scaffoldBackgroundColor,
        isNot(KhutatiTheme.dark.scaffoldBackgroundColor),
      );
    });
  });

  testWidgets('paletteOf follows the ambient brightness', (
    WidgetTester tester,
  ) async {
    late KhutatiPalette captured;

    await tester.pumpWidget(
      MaterialApp(
        theme: KhutatiTheme.dark,
        home: Builder(
          builder: (BuildContext context) {
            captured = KhutatiTheme.paletteOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(captured.bg, KColors.dark.bg);

    await tester.pumpWidget(
      MaterialApp(
        theme: KhutatiTheme.light,
        home: Builder(
          builder: (BuildContext context) {
            captured = KhutatiTheme.paletteOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(captured.bg, KColors.light.bg);
  });
}
