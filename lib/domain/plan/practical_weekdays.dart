/// The weekdays the user attends practical training.
///
/// The bundled plan uses Monday and Friday. The value is a user setting, not
/// template data: the importer never changes it, and removing it restores the
/// original day-by-day schedule.
///
/// The product allows one, two or three practical days. Three is the ceiling:
/// a fourth would leave the remaining study days carrying more than the
/// reference normal-day workload, which the plan is not sized for.
abstract final class PracticalWeekdays {
  static const int monday = DateTime.monday;
  static const int tuesday = DateTime.tuesday;
  static const int wednesday = DateTime.wednesday;
  static const int thursday = DateTime.thursday;
  static const int friday = DateTime.friday;
  static const int saturday = DateTime.saturday;
  static const int sunday = DateTime.sunday;

  /// Monday and Friday, the pattern printed in the source plan.
  static const List<int> original = <int>[monday, friday];

  /// The most practical days a week may contain.
  static const int maxDays = 3;

  /// Validates a selection and returns it sorted.
  ///
  /// Duplicates collapse; a selection of zero, four or more days is rejected so
  /// the stored preference can never describe a week the engine cannot fill.
  static List<int> validate(Iterable<int> weekdays) {
    final Set<int> unique = <int>{};
    for (final int weekday in weekdays) {
      if (weekday < DateTime.monday || weekday > DateTime.sunday) {
        throw ArgumentError.value(weekday, 'weekdays', 'not a weekday');
      }
      unique.add(weekday);
    }
    if (unique.isEmpty) {
      throw const FormatException('select at least one practical weekday');
    }
    if (unique.length > maxDays) {
      throw const FormatException('select at most three practical weekdays');
    }
    return unique.toList(growable: false)..sort();
  }

  static bool isOriginal(Iterable<int> weekdays) {
    final List<int> value = weekdays.toList(growable: false)..sort();
    return value.length == original.length &&
        value[0] == original[0] &&
        value[1] == original[1];
  }

  /// Decodes the JSON-array string stored in `app_settings`.
  ///
  /// A malformed or missing value falls back to `null`, which means "use the
  /// original schedule"; a corrupt preference must never make the app show an
  /// empty or half-generated plan.
  static List<int>? tryDecode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final Object? decoded = _decodeArray(raw);
      if (decoded is! List) return null;
      final List<int> values = <int>[
        for (final Object? value in decoded)
          if (value is num) value.toInt(),
      ];
      if (values.length != decoded.length) return null;
      return validate(values);
    } catch (_) {
      return null;
    }
  }

  static String encode(Iterable<int> weekdays) {
    final List<int> value = validate(weekdays);
    return '[${value.join(',')}]';
  }

  /// Small local decoder so this pure-Dart file does not need `dart:convert`
  /// in every caller; the accepted grammar is deliberately only `[1,5]`.
  static Object? _decodeArray(String raw) {
    final String value = raw.trim();
    if (!value.startsWith('[') || !value.endsWith(']')) return null;
    final String body = value.substring(1, value.length - 1).trim();
    if (body.isEmpty) return <int>[];
    return <int>[
      for (final String part in body.split(',')) int.parse(part.trim()),
    ];
  }
}
