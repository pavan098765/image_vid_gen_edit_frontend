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

  /// Call this from main()
  static Future<void> initialize(
      {Function(NotificationResponse)? onTap}) async {
    await _plugin.initialize(
      _initSettings,
      onDidReceiveNotificationResponse: onTap,
    );
  }

  /// Simple notification with optional payload
  static Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'ai_jobs_channel',
      'AI Job Notifications',
      channelDescription: 'Notifies when AI jobs complete',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);

    await _plugin.show(
      0,
      title,
      body,
      platformDetails,
      payload: payload,
    );
  }
}
