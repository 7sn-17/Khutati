import 'dart:async';

/// Returns the current device-local time. Injected in tests.
typedef LocalNow = DateTime Function();

/// Whether two instants fall on the same device-local calendar day.
bool sameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Emits the device-local time whenever its calendar date changes.
///
/// The stream starts with the current time immediately, then checks at least
/// once every [maxPoll]. That catches three cases the app cannot observe
/// directly:
/// * midnight while the app stays open;
/// * a timezone change that moves the local date while the app is foreground;
/// * a timer that was throttled while the app was in the background.
///
/// It never emits for a mere time-of-day change, so watching it does not
/// rebuild Today every few seconds. A one-minute poll is cheap for a study app
/// and bounds how long a stale date can be shown to a minute.
class LocalDayClock {
  LocalDayClock({LocalNow? now, Duration maxPoll = const Duration(minutes: 1)})
    : _now = now ?? DateTime.now,
      _maxPoll = maxPoll;

  final LocalNow _now;
  final Duration _maxPoll;

  Stream<DateTime> watch() async* {
    DateTime last = _now();
    yield last;

    while (true) {
      final DateTime now = _now();
      final DateTime nextMidnight = DateTime(now.year, now.month, now.day + 1);
      Duration wait = nextMidnight.difference(now);
      if (wait.isNegative || wait > _maxPoll) wait = _maxPoll;
      if (wait < const Duration(milliseconds: 1)) {
        wait = const Duration(milliseconds: 1);
      }

      await Future<void>.delayed(wait);

      final DateTime current = _now();
      if (!sameLocalDay(current, last)) {
        last = current;
        yield current;
      }
    }
  }
}
