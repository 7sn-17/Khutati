import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/core/utils/format.dart';
import 'package:khutati/l10n/generated/app_localizations.dart';

void main() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('ar'));
  final KhutatiFormat format = KhutatiFormat(l10n);

  group('KhutatiFormat.duration', () {
    test('renders hours and minutes like the prototype', () {
      expect(format.duration(135), '2 س 15 د');
    });

    test('drops the minute suffix on whole hours', () {
      expect(format.duration(120), '2 س');
    });

    test('drops the hour suffix under one hour', () {
      expect(format.duration(45), '45 د');
      expect(format.duration(0), '0 د');
    });
  });

  group('KhutatiFormat.range', () {
    test('prints the day part once when both ends share it', () {
      expect(format.range('08:00', '09:14'), '8:00 – 9:14 صباحاً');
    });

    test('repeats the day part when it changes', () {
      expect(format.range('11:50', '12:30'), '11:50 صباحاً – 12:30 ظهراً');
    });

    test('handles afternoon starts', () {
      expect(format.range('16:00', '17:30'), '4:00 – 5:30 عصراً');
    });
  });

  group('KhutatiFormat.twelveHour', () {
    test('maps midnight and noon to 12', () {
      expect(KhutatiFormat.twelveHour('00:30'), '12:30');
      expect(KhutatiFormat.twelveHour('12:00'), '12:00');
    });
  });

  group('KhutatiFormat.minutesOfDay', () {
    test('parses plan times', () {
      expect(KhutatiFormat.minutesOfDay('08:00'), 480);
      expect(KhutatiFormat.minutesOfDay('21:26'), 1286);
    });

    test('rejects malformed input instead of guessing', () {
      expect(() => KhutatiFormat.minutesOfDay('8'), throwsFormatException);
      expect(() => KhutatiFormat.minutesOfDay('24:00'), throwsFormatException);
    });
  });

  group('KhutatiFormat.westernDigits', () {
    test('converts Arabic-Indic digits', () {
      expect(KhutatiFormat.westernDigits('ج١ وج٢'), 'ج1 وج2');
      expect(KhutatiFormat.westernDigits('الجزء ۱۳'), 'الجزء 13');
    });

    test('leaves western digits untouched', () {
      expect(KhutatiFormat.westernDigits('الفصل 7'), 'الفصل 7');
    });
  });
}
