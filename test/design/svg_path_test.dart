import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/core/design/svg_path.dart';
import 'package:khutati/core/design/tokens.dart';

void main() {
  test('parses absolute and relative commands', () {
    final Path path = parseSvgPath('M0 0 H10 v10 h-5 V5');

    final List<PathMetric> metrics = path.computeMetrics().toList();
    expect(metrics, hasLength(1));
    expect(metrics.first.length, closeTo(30, 0.001));
    expect(metrics.first.isClosed, isFalse);
  });

  test('parses the prototype ECG trace as one open path', () {
    final Path path = parseSvgPath(KArtwork.ecgPath);

    final List<PathMetric> metrics = path.computeMetrics().toList();
    expect(metrics, hasLength(1));
    expect(metrics.first.length, greaterThan(0));
    expect(metrics.first.isClosed, isFalse);
  });

  test('parses the hexagon tile as a closed path', () {
    final Path path = parseSvgPath(KArtwork.hexPatternPath);

    final List<PathMetric> metrics = path.computeMetrics().toList();
    expect(metrics, hasLength(1));
    expect(metrics.first.isClosed, isTrue);
  });

  test('rejects unsupported commands instead of drawing nonsense', () {
    expect(() => parseSvgPath('M0 0 C1 1 2 2 3 3'), throwsFormatException);
  });

  test('throws on a truncated path', () {
    expect(() => parseSvgPath('M0'), throwsFormatException);
  });
}
