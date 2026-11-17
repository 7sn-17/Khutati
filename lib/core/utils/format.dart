import 'package:intl/intl.dart';

import '../l10n/app_strings.dart';

/// Formatting helpers that reproduce the prototype's Arabic number and time
/// conventions exactly (see `mn`, `wd`, `f1`, `rg`, `fm` in the HTML source).
///
/// Digits are Western (PRD section 13.1) and the unit suffixes are the short
/// forms the prototype uses: `2 س 15 د`.
abstract final class KhutatiFormat {
  static final RegExp _arabicIndic = RegExp('[\u0660-\u0669\u06F0-\u06F9]');
  static final Map<String, String> _digitMap = <String, String>{
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
    '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
    '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
  };

  /// Converts any Arabic-Indic digits to Western digits.
  static String westernDigits(String input) {
    if (!_arabicIndic.hasMatch(input)) return input;
    return input.split('').map((c) => _digitMap[c] ?? c).join();
  }

  /// `08:00` -> 480. Throws on malformed input rather than guessing.
  static int minutesOfDay(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) {
      throw FormatException('expected HH:mm', hhmm);
    }
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw FormatException('time out of range', hhmm);
    }
    return hour * 60 + minute;
  }

  /// `480` -> `08:00`.
  static String clockOf(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Arabic day-part word for an hour, matching the prototype.
  static String dayPart(int hour) {
    if (hour < 12) return AppStrings.morning;
    if (hour < 15) return AppStrings.noon;
    if (hour < 18) return AppStrings.afternoon;
    return AppStrings.evening;
  }

  /// `08:00` -> `8:00` (12-hour clock, no day part).
  static String twelveHour(String hhmm) {
    final total = minutesOfDay(hhmm);
    final hour = total ~/ 60;
    final minute = total % 60;
    final display = hour % 12 == 0 ? 12 : hour % 12;
    return '$display:${minute.toString().padLeft(2, '0')}';
  }

  /// `08:00`..`09:14` -> `8:00 صباحاً – 9:14 صباحاً`
  /// (the day part is printed once when both ends share it).
  static String range(String start, String end) {
    final startPart = dayPart(minutesOfDay(start) ~/ 60);
    final endPart = dayPart(minutesOfDay(end) ~/ 60);
    final left = twelveHour(start) + (startPart == endPart ? '' : ' $startPart');
    return '$left – ${twelveHour(end)} $endPart';
  }

  /// `135` -> `2 س 15 د`, `45` -> `45 د`, `120` -> `2 س`.
  static String duration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final hours = h > 0 ? '$h ${AppStrings.hourShort} ' : '';
    final mins = (m > 0 || h == 0) ? '$m ${AppStrings.minuteShort}' : '';
    return (hours + mins).trim();
  }

  /// Short Arabic date for a plan day, e.g. `19 تشرين الثاني`.
  static String planDate(DateTime date) {
    final formatted = DateFormat('d MMMM', 'ar').format(date);
    return westernDigits(formatted);
  }
}
