// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_vid_gen_edit_frontend/core/services/file_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Import the generated options file
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
import 'features/result_manager/result_manager_page.dart'; // 🔹 NEW import

// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Pending navigations queued before UI ready.
/// Stores tuple-like map {jobId, config}
final List<Map<String, dynamic>> _pendingNavigations = [];

/// Background FCM handler (runs in a background isolate when app is killed)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase in background isolate using the same options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Show a local notification (payload is job_id)
  await NotificationService.showNotification(
    title: message.notification?.title ?? "Processing Complete.",
    body: message.notification?.body ?? "Tap to view result.",
    payload: message.data['job_id'] ?? '',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("✅ Firebase initialized");

  // ✅ Initialize persistent app state before anything else
  await initAppState();
  await FileService.loadPreviewCache();
  debugPrint("✅ App state initialized & jobs restored");

  // Register background handler for FCM
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize local notification service (single call)
  await NotificationService.initialize(onTap: (response) async {
    try {
      final jobId = response.payload;
      if (jobId == null || jobId.isEmpty) {
        _openResultManager();
        return;
      }

      debugPrint("🔔 Notification tapped for job=$jobId");
      _openJobFromNotification(jobId, null);
    } catch (e) {
      debugPrint("⚠️ Notification tap restore failed: $e");
      _openResultManager();
    }
  });

  debugPrint("✅ NotificationService initialized");

  // Setup FCM, request permissions
  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission(alert: true, badge: true, sound: true);

  // Get & store token
  final token = await fcm.getToken();
  debugPrint("🔑 FCM Token: $token");
  final prefs = await SharedPreferences.getInstance();
  if (token != null) await prefs.setString("fcm_token", token);

  // Listen for token refresh and update local storage (so server gets fresh token)
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    debugPrint("🔄 FCM token refreshed: $newToken");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("fcm_token", newToken);
    // Optional: inform your backend about the new token here
  });

  // ------------------------
  // Foreground messages handler
  // ------------------------
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    debugPrint("📩 FCM onMessage: ${message.messageId} data=${message.data}");

    final jobId = message.data['job_id'] as String?;
    final status = (message.data['status'] as String?)?.toLowerCase();
    final downloadUrl = message.data['download_url'] as String?;

    // Update job list if present
    if (jobId != null && jobId.isNotEmpty) {
      final updated = <JobModel>[];
      for (final job in jobListNotifier.value) {
        if (job.jobId == jobId) {
          updated.add(JobModel(
            jobId: job.jobId,
            title: job.title,
            model: job.model,
            outputType: job.outputType,
            status: status ?? job.status,
            downloadUrl: downloadUrl ?? job.downloadUrl,
            createdAt: job.createdAt,
          ));
        } else {
          updated.add(job);
        }
      }
      jobListNotifier.value = List<JobModel>.from(updated);
      debugPrint("✅ FCM update: Job $jobId → $status");
    }

    // Show a local notification for foreground (since system may not)
    final notifTitle = message.notification?.title ??
        (status == 'completed' ? 'Result ready' : 'Job update');
    final notifBody = message.notification?.body ??
        (status == 'completed'
            ? 'Your AI result is ready — tap to view.'
            : 'Job status: $status');

    await NotificationService.showNotification(
      title: notifTitle,
      body: notifBody,
      payload: jobId ?? '',
    );

    // Also show an in-app SnackBar if nav is available
    if (navigatorKey.currentContext != null && status == 'completed') {
      ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
        const SnackBar(
          content: Text('✅ Your AI result is ready!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  });

  // When user taps an FCM notification while app was backgrounded (not killed)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    debugPrint("🔁 onMessageOpenedApp: ${message.data}");
    final jobId = message.data['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      _openResultManager();
      return;
    }

    // Try to restore job context and open GenericToolPage (with restoreJobId)
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
      _openJobFromNotification(jobId, config);
      return;
    }

    // fallback
    _openResultManager();
  });

  // If app was killed and opened from notification, queue navigation until UI ready
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null && initialMessage.data['job_id'] != null) {
    final jobId = initialMessage.data['job_id'] as String;
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
      _pendingNavigations.add({
        "jobId": jobId,
        "config": config,
      });
    } else {
      // If no job context, just open result manager when ready
      _pendingNavigations.add({
        "jobId": jobId,
        "config": null,
      });
    }
  }

  // Ensure poller runs (keeps UI in sync if notifications fail)
  PollingService.instance.start();
  debugPrint("✅ PollingService started");

  // Run app
  runApp(const AICreativeStudio());
  debugPrint("✅ runApp() executed");

  // Execute queued navigations after first frame (UI ready)
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (_pendingNavigations.isNotEmpty && navigatorKey.currentState != null) {
      for (final item in _pendingNavigations) {
        final jobId = item['jobId'] as String?;
        final cfgMap = item['config'] as GenericToolConfig?;
        if (jobId != null && cfgMap != null) {
          debugPrint("🎯 Executing queued navigation for job=$jobId");
          navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (_) =>
                  GenericToolPage(config: cfgMap, restoreJobId: jobId),
            ),
          );
        } else {
          // fallback: open the ResultManagerPage
          debugPrint(
              "🎯 Executing queued navigation to ResultManagerPage (fallback)");
          navigatorKey.currentState!.push(
              MaterialPageRoute(builder: (_) => const ResultManagerPage()));
        }
      }
      _pendingNavigations.clear();
    }
  });
}

/// ✅ Simplified — Always open the unified Result Manager page
///
void _openJobFromNotification(String jobId, GenericToolConfig? config) {
  final nav = navigatorKey.currentState;

  if (nav == null) {
    debugPrint("⚠️ Navigator not ready yet, queuing job=$jobId");
    _pendingNavigations.add({"jobId": jobId, "config": config});
    return;
  }

  debugPrint("🚀 Handling notification tap for job=$jobId");

  // Check if current route is already ResultManagerPage
  final canReuse = nav.canPop() &&
      nav.context.widget is Navigator &&
      nav.widget.runtimeType.toString().contains("ResultManagerPage");

  if (canReuse) {
    debugPrint("🔁 Already on ResultManagerPage — no new push");
    selectedIndexNotifier.value = 0;
    return;
  }

  // Otherwise push new page
  selectedIndexNotifier.value = 0;
  nav.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const ResultManagerPage()),
    (route) => route.isFirst, // clears duplicate layers above home
  );
}

void _openResultManager() {
  final nav = navigatorKey.currentState;
  if (nav == null) {
    debugPrint("⚠️ Navigator not ready yet, queueing ResultManagerPage");
    _pendingNavigations.add({"jobId": null, "config": null});
    return;
  }

  final currentRoute = ModalRoute.of(nav.context);
  if (currentRoute?.settings.name == 'ResultManagerPage') {
    debugPrint("🔁 Already on ResultManagerPage — skipping push");
    return;
  }

  nav.pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => const ResultManagerPage(),
      settings: const RouteSettings(name: 'ResultManagerPage'),
    ),
    (route) => route.isFirst,
  );
}

// void _openJobFromNotification(String jobId, GenericToolConfig? config) {
//   final nav = navigatorKey.currentState;

//   if (nav == null) {
//     debugPrint(
//         "⚠️ Navigator not ready yet, queuing ResultManagerPage for job=$jobId");
//     _pendingNavigations.add({"jobId": jobId, "config": config});
//     return;
//   }

//   debugPrint("🚀 Navigating to ResultManagerPage for job=$jobId");

//   // ✅ Keep main shell intact (with bottom nav)
//   selectedIndexNotifier.value = 0; // or index of "Results" tab if exists
//   nav.push(
//     MaterialPageRoute(builder: (_) => const ResultManagerPage()),
//   );
// }

// /// Open the unified Result Manager (if no specific job/context available)
// void _openResultManager() {
//   final nav = navigatorKey.currentState;
//   if (nav == null) {
//     debugPrint("⚠️ Navigator not ready yet, queueing ResultManagerPage");
//     _pendingNavigations.add({"jobId": null, "config": null});
//     return;
//   }
//   nav.push(MaterialPageRoute(builder: (_) => const ResultManagerPage()));
// }

// ----------------------------------------------------
// Root App
// ----------------------------------------------------
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
