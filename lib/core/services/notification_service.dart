// lib/core/services/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'ai_jobs_channel',
    'AI Job Notifications',
    description: 'Notifies when AI jobs complete or fail.',
    importance: Importance.max,
    playSound: true,
  );

  /// 🔹 Initialize notification plugin once
  static Future<void> initialize({
    Function(NotificationResponse)? onTap,
  }) async {
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings();

      const settings =
          InitializationSettings(android: androidSettings, iOS: iosSettings);

      await _plugin.initialize(settings,
          onDidReceiveNotificationResponse: onTap);

      // ✅ Android channel
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(_channel);

      // ✅ Ask for runtime permission (Android 13+)
      await androidImpl?.requestNotificationsPermission();

      // ✅ iOS permission
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      debugPrint("✅ NotificationService initialized");
    } catch (e) {
      debugPrint("❌ NotificationService init failed: $e");
    }
  }

  /// 🔹 Display a local notification
  static Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'ai_jobs_channel',
        'AI Job Notifications',
        channelDescription: 'Notifies when AI jobs complete',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        showWhen: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await _plugin.show(id, title, body, details, payload: payload?.toString(),);
      debugPrint("🔔 Local notification shown: $title");
    } catch (e) {
      debugPrint("❌ showNotification failed: $e");
    }
  }
}
