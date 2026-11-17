import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/core/design/tokens.dart';

/// Guards the design source of truth: if the prototype palette is ever
/// "adjusted" by hand, these tests fail before the UI ships.
void main() {
  test('dark palette matches the prototype exactly', () {
    expect(KColors.dark.bg, const Color(0xFF0D1A2D));
    expect(KColors.dark.card, const Color(0xFF15263F));
    expect(KColors.dark.card2, const Color(0xFF1C3150));
    expect(KColors.dark.line, const Color(0xFF26395A));
    expect(KColors.dark.tx, const Color(0xFFEAE5DA));
    expect(KColors.dark.mute, const Color(0xFF93A1B8));
    expect(KColors.dark.red, const Color(0xFFB52A20));
    expect(KColors.dark.redtx, const Color(0xFFF0766B));
    expect(KColors.dark.ok, const Color(0xFF7CCBB0));
    expect(KColors.dark.gold, const Color(0xFFE8B65A));
  });

  test('light palette matches the prototype overrides', () {
    expect(KColors.light.bg, const Color(0xFFF1EDE4));
    expect(KColors.light.card, const Color(0xFFFFFFFF));
    expect(KColors.light.tx, const Color(0xFF0D1A2D));
    expect(KColors.light.redtx, const Color(0xFFA8241B));
    expect(KColors.light.ok, const Color(0xFF1F7A5F));
    expect(KColors.light.gold, const Color(0xFF9A6A12));
    // --red is not overridden in the light theme; it inherits the dark value.
    expect(KColors.light.red, KColors.dark.red);
  });

  test('subject accents come from the prototype palette', () {
    expect(KColors.subjects.length, 5);
    expect(KColors.subject('ch').accent, const Color(0xFF6AA6FF));
    expect(KColors.subject('ph').accent, const Color(0xFF5DD6C0));
    expect(KColors.subject('en').accent, const Color(0xFFF0A8C8));
    expect(KColors.subject('hi').accent, const Color(0xFFE8B65A));
    expect(KColors.subject('bi').accent, const Color(0xFFF0766B));
  });

  test('geometry matches the prototype metrics', () {
    expect(KMetrics.ringSize, 240);
    expect(KMetrics.ringRadius, 104);
    expect(KMetrics.ringStroke, 10);
    expect(KMetrics.navRadius, 30);
    expect(KMetrics.heroRadius, 18);
    expect(KMetrics.tapTarget, 48);
  });

  test('typography uses both Arabic families', () {
    expect(KTypography.bodyFamily, 'IBM Plex Sans Arabic');
    expect(KTypography.displayFamily, 'Reem Kufi');
    expect(KTypography.h1Size, 46);
    expect(KTypography.bodySize, 16);
  });
}
