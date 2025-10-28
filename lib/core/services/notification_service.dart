// lib/core/services/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static const AndroidInitializationSettings _initSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  static const InitializationSettings _initSettings =
      InitializationSettings(android: _initSettingsAndroid);

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'ai_jobs_channel', // must match your AndroidNotificationDetails ID
    'AI Job Notifications',
    description: 'Notifies when AI jobs complete',
    importance: Importance.max,
  );

  /// 🔹 Call this once from main()
  static Future<void> initialize({
    Function(NotificationResponse)? onTap,
  }) async {
    await _plugin.initialize(
      _initSettings,
      onDidReceiveNotificationResponse: onTap,
    );

    // ✅ Explicitly create notification channel (important for Android 13+)
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(_channel);

    // ✅ Ask for permission (Android 13+)
    await androidPlugin?.requestNotificationsPermission();
  }

  /// 🔹 Show a simple notification
  static Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'ai_jobs_channel', // must match _channel.id
      'AI Job Notifications',
      channelDescription: 'Notifies when AI jobs complete',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      showWhen: true,
    );

    const details = NotificationDetails(android: androidDetails);
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _plugin.show(
      id, // notification ID
      title,
      body,
      details,
      payload: payload,
    );
  }
}
