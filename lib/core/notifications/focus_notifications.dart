import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The one place that owns the local-notification plugin.
///
/// Previously `main.dart`, the permission bootstrap and the focus controller
/// each constructed their own `FlutterLocalNotificationsPlugin`, and the timer
/// channel was only created lazily (by `show`, after the fact). On Android the
/// first `NotificationChannel` wins forever, so if anything created the channel
/// with a lower importance the sound was silently gone for the life of the
/// install. Creating `Importance.max` here, once, at startup, removes that
/// class of bug.
abstract final class FocusNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String alertChannelId = 'khutati_timer_alerts';

  /// The completion channel: heads-up, sound and vibration.
  static const AndroidNotificationChannel alertChannel =
      AndroidNotificationChannel(
        alertChannelId,
        'تنبيهات الجلسات',
        description: 'تنبيه صوتي عند انتهاء جلسة التركيز أو الاستراحة',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

  /// Called once from `main()` before the first frame.
  static Future<void> init() async {
    const AndroidInitializationSettings android = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    await _plugin.initialize(
      const InitializationSettings(android: android),
      // A tap on the notification body only opens the app. It must never carry
      // an action: state reconciliation happens in FocusController on resume.
      onDidReceiveNotificationResponse: (NotificationResponse response) {},
    );
    await _android?.createNotificationChannel(alertChannel);
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
    try {
      await _plugin.show(
        isBreak ? 1002 : 1001,
        isBreak ? 'انتهت الاستراحة' : 'انتهى وقت التركيز',
        isBreak ? 'وقت العودة للدراسة.' : 'أحسنت! أكملت جلسة التركيز.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            alertChannelId,
            'تنبيهات الجلسات',
            channelDescription: 'تنبيه صوتي عند انتهاء جلسة التركيز أو الاستراحة',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            playSound: true,
            enableVibration: true,
            visibility: NotificationVisibility.public,
            ticker: 'مؤقت التركيز',
          ),
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
