import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/core/design/khutati_icons.dart';

/// The navigation glyphs are copied from the prototype, not redrawn. This test
/// diffs them against the HTML so a future "improvement" cannot slip through.
void main() {
  test('nav glyphs match the prototype exactly', () {
    final String html = File('خطتي اليومية، الإصدار 3.html').readAsStringSync();
    final RegExp navPattern = RegExp(r'<nav>([\s\S]*?)</nav>');
    final String? nav = navPattern.firstMatch(html)?.group(1);
    expect(nav, isNotNull, reason: 'prototype must keep a <nav> block');

    final List<String> bodies = RegExp(r'<svg[^>]*>([\s\S]*?)</svg>')
        .allMatches(nav!)
        .map((RegExpMatch m) => m.group(1)!.trim())
        .toList();

    expect(bodies, hasLength(4), reason: 'four nav glyphs in the prototype');
    expect(bodies, KhutatiIcons.navBodies);
  });

  test('svg wrapper applies the prototype stroke rules', () {
    final String svg = KhutatiIcons.svg(KhutatiIcons.todayBody);
    expect(svg, contains('viewBox="0 0 24 24"'));
    expect(svg, contains('fill="none"'));
    expect(svg, contains('stroke="currentColor"'));
    expect(svg, contains('stroke-width="1.8"'));
    expect(svg, contains('stroke-linecap="round"'));
    expect(svg, contains('stroke-linejoin="round"'));
  });
}
