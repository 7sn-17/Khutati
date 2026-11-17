import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/core/design/tokens.dart';

/// The ECG trace, the focus ring and the hexagon texture are vector artwork, not
/// code. These tests diff them against the prototype so the "source of truth"
/// claim is enforced, not assumed.
void main() {
  late String html;

  setUpAll(() {
    html = File('خطتي اليومية، الإصدار 3.html').readAsStringSync();
  });

  test('ECG path matches the prototype path element', () {
    final RegExpMatch? match = RegExp(r'<path class="g" d="([^"]+)"').firstMatch(html);
    expect(match, isNotNull);
    expect(KArtwork.ecgPath, match!.group(1));
  });

  test('ECG viewBox and stroke come from the prototype', () {
    expect(KArtwork.ecgViewWidth, 300);
    expect(KArtwork.ecgViewHeight, 40);
    expect(KArtwork.ecgStrokeWidth, 2.5);
    expect(KArtwork.ecgRenderedHeight, 52);
  });

  test('ring geometry matches the prototype circle', () {
    final String circle = RegExp(r'<circle class="v" id="rv"[^>]*>').firstMatch(html)!.group(0)!;
    expect(circle, contains('r="104"'));
    expect(circle, contains('stroke-width="10"'));
    expect(circle, contains('stroke-dasharray="653"'));
    expect(KArtwork.ringRadius, 104);
    expect(KArtwork.ringStrokeWidth, 10);
    expect(KArtwork.ringCircumference, 653);
  });

  test('hexagon tile matches the --hx data URI', () {
    expect(html, contains(KArtwork.hexPatternPath));
    expect(html, contains("width='${KArtwork.hexTileWidth.toInt()}'"));
    expect(html, contains("height='${KArtwork.hexTileHeight.toInt()}'"));
    expect(KArtwork.hexOpacity, 0.2);
  });
}
