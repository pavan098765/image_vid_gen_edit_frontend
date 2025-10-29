// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Import the generated options file (created by flutterfire configure)
import 'firebase_options.dart';

// Existing imports
import 'package:image_vid_gen_edit_frontend/core/services/polling_service.dart';
import 'core/theme/app_theme.dart';
import 'core/app_state.dart';
import 'core/services/notification_service.dart';

import 'features/editor/editor_page.dart';
import 'features/ai_tools/ai_tools_page.dart';
import 'features/ai_tools/generic_tool_page.dart';
import 'features/video_gen/video_gen_page.dart';
import 'features/credits/credits_page.dart';
import 'features/settings/settings_page.dart';

// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Queue for delayed navigations before MaterialApp mounts
List<({String jobId, GenericToolConfig config})> _pendingNavigations = [];

/// Background handler for FCM (runs in a background isolate when app is killed)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase in background isolate using the same options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Use local notifications plugin to show a notification
  await NotificationService.showNotification(
    title: message.notification?.title ?? "Processing Complete.",
    body: message.notification?.body ?? "Tap to view result.",
    payload: message.data["job_id"] ?? "",
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with generated options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("✅ Firebase initialized");

  // Register background handler for FCM
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize local notification service (single call)
  await NotificationService.initialize(onTap: (response) async {
    try {
      if (response.payload == null || response.payload!.isEmpty) return;
      final jobId = response.payload!;
      final prefs = await SharedPreferences.getInstance();
      final jobContextStr = prefs.getString("notify_job_$jobId");
      if (jobContextStr == null) return;

      final data = jsonDecode(jobContextStr);
      final config = GenericToolConfig(
        title: data["title"] ?? "AI Tool",
        model: data["model"] ?? "unknown_model",
        inputs: List<Map<String, dynamic>>.from(data["inputs"] ?? []),
        params: Map<String, dynamic>.from(data["params"] ?? {}),
        outputType: data["outputType"] ?? "image",
      );

      _openJobFromNotification(jobId, config);
    } catch (e) {
      debugPrint("⚠️ Notification tap restore failed: $e");
    }
  });
  debugPrint("✅ Local NotificationService initialized");

  // FCM instance & permission
  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission(alert: true, badge: true, sound: true);

  // Store FCM token locally
  final token = await fcm.getToken();
  debugPrint("🔑 FCM Token: $token");
  final prefs = await SharedPreferences.getInstance();
  if (token != null) await prefs.setString("fcm_token", token);

  // Foreground messages -> show via local notifications
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint("📩 Foreground FCM: ${message.notification?.title}");
    NotificationService.showNotification(
      title: message.notification?.title ?? "Processing Complete",
      body: message.notification?.body ?? "Tap to view your result.",
      payload: message.data["job_id"] ?? "",
    );
  });

  // When user taps an FCM notification while app was backgrounded (not killed)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    final jobId = message.data["job_id"];
    if (jobId == null || jobId.isEmpty) return;

    final jobContextStr = prefs.getString("notify_job_$jobId");
    if (jobContextStr == null) return;

    final data = jsonDecode(jobContextStr);
    final config = GenericToolConfig(
      title: data["title"] ?? "AI Tool",
      model: data["model"] ?? "unknown_model",
      inputs: List<Map<String, dynamic>>.from(data["inputs"] ?? []),
      params: Map<String, dynamic>.from(data["params"] ?? {}),
      outputType: data["outputType"] ?? "image",
    );

    _openJobFromNotification(jobId, config);
  });

  // If app was killed and opened from notification, getInitialMessage()
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null && initialMessage.data["job_id"] != null) {
    final jobId = initialMessage.data["job_id"];
    final jobContextStr = prefs.getString("notify_job_$jobId");
    if (jobContextStr != null) {
      final data = jsonDecode(jobContextStr);
      final config = GenericToolConfig(
        title: data["title"] ?? "AI Tool",
        model: data["model"] ?? "unknown_model",
        inputs: List<Map<String, dynamic>>.from(data["inputs"] ?? []),
        params: Map<String, dynamic>.from(data["params"] ?? {}),
        outputType: data["outputType"] ?? "image",
      );
      // queue navigation until UI exists
      _pendingNavigations.add((jobId: jobId, config: config));
    }
  }

  // Start polling service (safe to call; it's idempotent)
  PollingService.instance.start();
  debugPrint("✅ PollingService started");

  // Launch app once
  runApp(const AICreativeStudio());
  debugPrint("✅ runApp() executed");

  // Execute queued navigations after first frame
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (_pendingNavigations.isNotEmpty && navigatorKey.currentState != null) {
      for (final item in _pendingNavigations) {
        debugPrint("🎯 Executing queued navigation for job=${item.jobId}");
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (_) => GenericToolPage(
              config: item.config,
              restoreJobId: item.jobId,
            ),
          ),
        );
      }
      _pendingNavigations.clear();
    }
  });
}

// Helper for both local + FCM notification opens
void _openJobFromNotification(String jobId, GenericToolConfig config) {
  final nav = navigatorKey.currentState;
  if (nav == null) {
    debugPrint("⚠️ Navigator not ready yet, queuing job=$jobId");
    _pendingNavigations.add((jobId: jobId, config: config));
    return;
  }

  debugPrint("🚀 Navigating to GenericToolPage for job=$jobId");
  nav.push(
    MaterialPageRoute(
      builder: (_) => GenericToolPage(
        config: config,
        restoreJobId: jobId,
      ),
    ),
  );
}

// Root App
class AICreativeStudio extends StatelessWidget {
  const AICreativeStudio({super.key});

  final List<Widget> _pages = const [
    EditorPage(),
    VideoGenPage(),
    AiToolsPage(),
    CreditsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    debugPrint("🟢 Building AICreativeStudio widget");

    return MaterialApp(
      title: 'AI Creative Studio',
      theme: AppTheme.darkTheme,
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: ValueListenableBuilder<int>(
            valueListenable: selectedIndexNotifier,
            builder: (_, currentIndex, __) {
              return IndexedStack(
                index: currentIndex,
                children: _pages,
              );
            },
          ),
        ),
        bottomNavigationBar: ValueListenableBuilder<int>(
          valueListenable: selectedIndexNotifier,
          builder: (_, currentIndex, __) {
            return NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: (i) => selectedIndexNotifier.value = i,
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.photo_library), label: "Photo"),
                NavigationDestination(icon: Icon(Icons.movie), label: "Video"),
                NavigationDestination(
                    icon: Icon(Icons.auto_awesome), label: "AI Tools"),
                NavigationDestination(
                    icon: Icon(Icons.monetization_on), label: "Credits"),
                NavigationDestination(
                    icon: Icon(Icons.settings), label: "Settings"),
              ],
            );
          },
        ),
      ),
    );
  }
}
