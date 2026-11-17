import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_mode_controller.dart' show sharedPreferencesProvider;

/// Notification preferences (PRD 5.9). Each type is independently toggleable;
/// Phase 4 wires the actual scheduling to these flags.
class NotificationPrefs {
  const NotificationPrefs({
    required this.tasks,
    required this.daily,
    required this.review,
    required this.timer,
  });

  final bool tasks;
  final bool daily;
  final bool review;
  final bool timer;

  NotificationPrefs copyWith({
    bool? tasks,
    bool? daily,
    bool? review,
    bool? timer,
  }) {
    return NotificationPrefs(
      tasks: tasks ?? this.tasks,
      daily: daily ?? this.daily,
      review: review ?? this.review,
      timer: timer ?? this.timer,
    );
  }
}

final NotifierProvider<NotificationPrefsController, NotificationPrefs>
    notificationPrefsProvider =
    NotifierProvider<NotificationPrefsController, NotificationPrefs>(
  NotificationPrefsController.new,
);

class NotificationPrefsController extends Notifier<NotificationPrefs> {
  static const String tasksKey = 'notif_tasks';
  static const String dailyKey = 'notif_daily';
  static const String reviewKey = 'notif_review';
  static const String timerKey = 'notif_timer';

  @override
  NotificationPrefs build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return NotificationPrefs(
      tasks: prefs.getBool(tasksKey) ?? true,
      daily: prefs.getBool(dailyKey) ?? true,
      review: prefs.getBool(reviewKey) ?? true,
      timer: prefs.getBool(timerKey) ?? true,
    );
  }

  Future<void> setTasks(bool value) =>
      _write(tasksKey, value, (NotificationPrefs p) => p.copyWith(tasks: value));

  Future<void> setDaily(bool value) =>
      _write(dailyKey, value, (NotificationPrefs p) => p.copyWith(daily: value));

  Future<void> setReview(bool value) =>
      _write(reviewKey, value, (NotificationPrefs p) => p.copyWith(review: value));

  Future<void> setTimer(bool value) =>
      _write(timerKey, value, (NotificationPrefs p) => p.copyWith(timer: value));

  Future<void> _write(
    String key,
    bool value,
    NotificationPrefs Function(NotificationPrefs) update,
  ) async {
    state = update(state);
    await ref.read(sharedPreferencesProvider).setBool(key, value);
  }
}
