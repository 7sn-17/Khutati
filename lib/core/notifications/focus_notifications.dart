import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The one place that owns the local-notification plugin and every Android
/// channel. The first channel definition on Android is permanent, so all four
/// are created here with their final importance.
enum KhutatiNotificationChannel { tasks, daily, review, timer }

extension KhutatiNotificationChannelInfo on KhutatiNotificationChannel {
  String get id => switch (this) {
        KhutatiNotificationChannel.tasks => 'khutati_reminders_tasks_v1',
        KhutatiNotificationChannel.daily => 'khutati_reminders_daily_v1',
        KhutatiNotificationChannel.review => 'khutati_reminders_review_v1',
        KhutatiNotificationChannel.timer => 'khutati_timer_alerts',
      };

  String get name => switch (this) {
        KhutatiNotificationChannel.tasks => 'تذكير المهام',
        KhutatiNotificationChannel.daily => 'ملخص اليوم',
        KhutatiNotificationChannel.review => 'مراجعة المهام',
        KhutatiNotificationChannel.timer => 'تنبيهات الجلسات',
      };

  String get description => switch (this) {
        KhutatiNotificationChannel.tasks =>
          'تنبيه قبل بدء مهمة من جدول اليوم',
        KhutatiNotificationChannel.daily =>
          'ملخص إنجاز اليوم وخطة الغد',
        KhutatiNotificationChannel.review =>
          'تذكير بمراجعة المهام والأسئلة المعلّمة',
        KhutatiNotificationChannel.timer =>
          'صوت واهتزاز عند انتهاء جلسة التركيز أو الاستراحة',
      };

  int get notificationId => switch (this) {
        KhutatiNotificationChannel.tasks => 2001,
        KhutatiNotificationChannel.daily => 2002,
        KhutatiNotificationChannel.review => 2003,
        KhutatiNotificationChannel.timer => 1001,
      };

  AndroidNotificationDetails get androidDetails => AndroidNotificationDetails(
        id,
        name,
        channelDescription: description,
        importance: this == KhutatiNotificationChannel.timer
            ? Importance.max
            : Importance.high,
        priority: Priority.high,
        category: this == KhutatiNotificationChannel.timer
            ? AndroidNotificationCategory.alarm
            : AndroidNotificationCategory.reminder,
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
      );

  AndroidNotificationChannel get platformChannel => AndroidNotificationChannel(
        id,
        name,
        description: description,
        importance: this == KhutatiNotificationChannel.timer
            ? Importance.max
            : Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: this != KhutatiNotificationChannel.timer,
      );
}

abstract final class FocusNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String alertChannelId =
      'khutati_timer_alerts';
  static const String alertChannelName = 'تنبيهات الجلسات';

  /// Mirrors the persisted timer preference so [showCompletion] can never fire
  /// on a channel the user switched off.
  static bool _timerEnabled = true;

  /// Called once from `main()` before the first frame.
  static Future<void> init({
    bool tasks = true,
    bool daily = true,
    bool review = true,
    bool timer = true,
  }) async {
    const AndroidInitializationSettings android = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    await _plugin.initialize(
      const InitializationSettings(android: android),
      // A tap on the notification body only opens the app. It must never carry
      // an action: state reconciliation happens in FocusController on resume.
      onDidReceiveNotificationResponse: (NotificationResponse response) {},
    );
    await applyPreferences(
      tasks: tasks,
      daily: daily,
      review: review,
      timer: timer,
    );
  }

  /// Creates the channels whose toggles are ON and removes the ones that are
  /// OFF. Removing a channel is the only way Android lets an app truly
  /// suppress it; merely not posting a notification would leave the toggle
  /// cosmetic.
  static Future<void> applyPreferences({
    required bool tasks,
    required bool daily,
    required bool review,
    required bool timer,
  }) async {
    await _setEnabled(KhutatiNotificationChannel.tasks, tasks);
    await _setEnabled(KhutatiNotificationChannel.daily, daily);
    await _setEnabled(KhutatiNotificationChannel.review, review);
    await _setEnabled(KhutatiNotificationChannel.timer, timer);
  }

  static Future<void> setEnabled(
    KhutatiNotificationChannel channel,
    bool enabled,
  ) {
    return _setEnabled(channel, enabled);
  }

  static Future<void> _setEnabled(
    KhutatiNotificationChannel channel,
    bool enabled,
  ) async {
    if (channel == KhutatiNotificationChannel.timer) {
      _timerEnabled = enabled;
    }
    final AndroidFlutterLocalNotificationsPlugin? android = _android;
    if (android == null) return;
    try {
      if (enabled) {
        await android.createNotificationChannel(channel.platformChannel);
      } else {
        await _plugin.cancel(channel.notificationId);
        await _plugin.cancel(channel.notificationId + 1);
        await android.deleteNotificationChannel(channel.id);
      }
    } catch (_) {
      // A denied permission or an OEM restriction must not break Settings.
    }
  }

  /// Android 13+ runtime permission (`POST_NOTIFICATIONS`).
  static Future<bool> requestPermission() async {
    try {
      final bool? granted = await _android?.requestNotificationsPermission();
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> areEnabled() async {
    try {
      final bool? enabled = await _android?.areNotificationsEnabled();
      return enabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Fires at 00:00, from the Dart state machine.
  static Future<void> showCompletion({required bool isBreak}) async {
    if (!_timerEnabled) return;
    try {
      await _plugin.show(
        isBreak ? 1002 : 1001,
        isBreak ? 'انتهت الاستراحة' : 'انتهى وقت التركيز',
        isBreak ? 'وقت العودة للدراسة.' : 'أحسنت! أكملت جلسة التركيز.',
        NotificationDetails(
          android: KhutatiNotificationChannel.timer.androidDetails,
        ),
        payload: isBreak ? 'focus:break-done' : 'focus:done',
      );
    } catch (_) {
      // A denied permission must not break the timer.
    }
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
}
