// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_vid_gen_edit_frontend/core/services/file_service.dart';
import 'package:image_vid_gen_edit_frontend/core/services/polling_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Import the generated options file
import 'firebase_options.dart';

// Existing imports
import 'core/theme/app_theme.dart';
import 'core/app_state.dart';
import 'core/services/notification_service.dart';

import 'features/image_editor/image_editor_page.dart';
import 'features/ai_tools/ai_tools_page.dart';
import 'features/ai_tools/generic_tool_page.dart';
import 'features/video_editor/video_editor_page.dart';
import 'features/credits/credits_page.dart';
import 'features/settings/settings_page.dart';
import 'features/result_manager/result_manager_page.dart'; // 🔹 NEW import
import 'package:media_kit/media_kit.dart';

// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Pending navigations queued before UI ready.
/// Stores tuple-like map {jobId, config}
final List<Map<String, dynamic>> _pendingNavigations = [];

// ----------------------
// Helpers: apply and persist FCM updates
// ----------------------

Future<void> _mergeAndPersistJobMap(Map<String, dynamic> jobMap) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // ✅ ensure latest copy before merge

    final jsonStr = prefs.getString('jobs');
    final existing = jsonStr == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(jsonStr) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final jobId = jobMap['job_id']?.toString();
    if (jobId == null || jobId.isEmpty) return;

    final status = (jobMap['status'] ?? '').toString();
    final downloadUrl = (jobMap['download_url'] ?? '').toString();

    final idx = existing.indexWhere((e) => e['jobId'] == jobId);
    if (idx != -1) {
      final old = existing[idx];
      existing[idx] = {
        'jobId': jobId,
        'title': old['title'] ?? jobMap['title'] ?? jobId,
        'model': old['model'] ?? jobMap['model'] ?? 'unknown',
        'outputType': old['outputType'] ?? jobMap['outputType'] ?? 'image',
        'downloadUrl':
            downloadUrl.isNotEmpty ? downloadUrl : (old['downloadUrl']),
        'status': status.isNotEmpty ? status : (old['status'] ?? 'processing'),
        'createdAt': old['createdAt'] ?? DateTime.now().toIso8601String(),
        'localFilePath': old['localFilePath'],
        'inputImagePath': old['inputImagePath'],
      };
    } else {
      existing.insert(0, {
        'jobId': jobId,
        'title': jobMap['title'] ?? jobId,
        'model': jobMap['model'] ?? 'unknown',
        'outputType': jobMap['outputType'] ?? 'image',
        'downloadUrl': downloadUrl.isNotEmpty ? downloadUrl : null,
        'status': status.isNotEmpty ? status : 'processing',
        'createdAt': DateTime.now().toIso8601String(),
      });
    }

    if (downloadUrl.isNotEmpty) {
      await prefs.setString('pending_download_url_$jobId', downloadUrl);
    }

    await prefs.setString('jobs', jsonEncode(existing));
    await prefs.reload(); // ✅ force disk write flush

    debugPrint("💾 [FCM] job $jobId persisted (status=$status)");
  } catch (e, st) {
    debugPrint("⚠️ _mergeAndPersistJobMap failed: $e\n$st");
  }
}

/// 🧠 Always reload jobs directly from the actual prefs file on disk.
/// Works even if background isolate updated SharedPreferences.
Future<void> _reloadJobsToNotifier() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // ✅ Always refresh cache

    // 🧩 Detect if background FCM updated while app minimized
    final hasUpdate = prefs.getBool('has_fcm_update') ?? false;
    if (hasUpdate) {
      debugPrint("📦 Detected FCM background update — applying reload");
      await prefs.remove('has_fcm_update');
    }

    final jsonStr = prefs.getString('jobs');
    if (jsonStr == null) {
      jobListNotifier.value = [];
      debugPrint("📂 No jobs found — cleared");
      return;
    }

    final decoded = jsonDecode(jsonStr);
    if (decoded is! List) {
      debugPrint("⚠️ Invalid jobs list format");
      return;
    }

    final list = decoded
        .map((e) => JobModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    jobListNotifier.value = List<JobModel>.from(list);
    debugPrint("✅ Reloaded ${list.length} jobs (after FCM check)");
    for (final j in list) {
      debugPrint(
          "✅ Loaded ${j.jobId} input=${j.inputImagePath} local=${j.localFilePath}");
    }
  } catch (e, st) {
    debugPrint("⚠️ _reloadJobsToNotifier failed: $e\n$st");
  }
}

/// Called from all FCM receivers (background/foreground). Accepts raw message map
/// Expected keys: job_id, status, download_url, title, model, outputType (optional)
Future<void> _applyFcmUpdate(Map<String, dynamic> data) async {
  try {
    final jobId = (data['job_id'] ?? data['jobId'] ?? '').toString();
    if (jobId.isEmpty) return;

    // Merge into prefs
    await _mergeAndPersistJobMap({
      'job_id': jobId,
      'status': data['status'] ?? '',
      'download_url': data['download_url'] ?? data['downloadUrl'] ?? '',
      'title': data['title'] ?? '',
      'model': data['model'] ?? '',
      'outputType': data['outputType'] ?? '',
    });

    // If app is in foreground (we have navigatorKey.currentContext), also reload notifier so UI updates immediately.
    if (navigatorKey.currentState != null &&
        navigatorKey.currentContext != null) {
      await _reloadJobsToNotifier();
    }
  } catch (e, st) {
    debugPrint("⚠️ _applyFcmUpdate failed: $e\n$st");
  }
}

/// Background FCM handler (runs in a background isolate when app is killed)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  try {
    final data = message.data ?? {};
    final jobId = (data['job_id'] ?? '').toString();
    const allowed = ['processing', 'completed', 'failed'];
    final status = (data['status'] ?? '').toString().toLowerCase();
    final normalizedStatus = allowed.contains(status) ? status : 'processing';

    final downloadUrl =
        (data['download_url'] ?? data['downloadUrl'] ?? '').toString();
    final title = (data['title'] ?? '').toString();
    final model = (data['model'] ?? '').toString();
    final outputType = (data['outputType'] ?? '').toString();

    if (jobId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // ✅ ensure we have freshest data

    final jsonStr = prefs.getString('jobs');
    final existing = jsonStr == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(jsonStr) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final idx = existing.indexWhere((e) => e['jobId'] == jobId);

    if (idx >= 0) {
      final old = existing[idx];

      // 🧠 Preserve paths if they existed before
      final preservedInputImagePath = old['inputImagePath'];
      final preservedLocalPath = old['localFilePath'];

      existing[idx] = {
        'jobId': jobId,
        'title': old['title'] ?? title,
        'model': old['model'] ?? model,
        'outputType': old['outputType'] ?? outputType,
        'downloadUrl':
            downloadUrl.isNotEmpty ? downloadUrl : (old['downloadUrl']),
        'status': normalizedStatus.isNotEmpty
            ? normalizedStatus
            : (old['status'] ?? 'processing'),
        'createdAt': old['createdAt'] ?? DateTime.now().toIso8601String(),

        // ✅ Preserve file paths even if isolate didn’t have them
        'localFilePath': preservedLocalPath,
        'inputImagePath': preservedInputImagePath,
      };

      debugPrint(
          "🟣 [FCM isolate] Preserved inputImagePath for $jobId → $preservedInputImagePath");
    } else {
      // 🔹 New job record — no previous entry to merge from
      existing.insert(0, {
        'jobId': jobId,
        'title': title.isNotEmpty ? title : jobId,
        'model': model.isNotEmpty ? model : 'unknown',
        'outputType': outputType.isNotEmpty ? outputType : 'image',
        'downloadUrl': downloadUrl.isNotEmpty ? downloadUrl : null,
        'status': normalizedStatus.isNotEmpty ? normalizedStatus : 'processing',
        'createdAt': DateTime.now().toIso8601String(),
        // keep null for these if truly new
        'inputImagePath': null,
        'localFilePath': null,
      });
    }

    // persist per-job download url key too (prevents global clobber)
    if (downloadUrl.isNotEmpty) {
      await prefs.setString('pending_download_url_$jobId', downloadUrl);
    }

    await prefs.setString('jobs', jsonEncode(existing));
    await prefs.setBool('has_fcm_update', true);

    // 🔔 Local notification for visibility
    await NotificationService.showNotification(
      title: message.notification?.title ??
          (normalizedStatus == 'completed' ? 'Result ready' : 'Job update'),
      body: message.notification?.body ??
          (normalizedStatus == 'completed'
              ? 'Tap to view your result'
              : 'Job status updated'),
      payload: jobId,
    );
  } catch (e, st) {
    debugPrint("⚠️ background handler error: $e\n$st");
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

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
      await _refreshJobsAfterNotification();
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

    final data = message.data ?? {};
    final jobId = (data['job_id'] ?? '').toString();
    const allowed = ['processing', 'completed', 'failed'];

    final status = (data['status'] ?? '').toString().toLowerCase();
    final normalizedStatus = allowed.contains(status) ? status : 'processing';
    final downloadUrl =
        (data['download_url'] ?? data['downloadUrl'] ?? '').toString();
    final title = (data['title'] ?? '').toString();
    final model = (data['model'] ?? '').toString();
    final outputType = (data['outputType'] ?? '').toString();

    if (jobId.isNotEmpty) {
      // ✅ Update both prefs and notifier in one go
      await _applyFcmUpdate({
        'job_id': jobId,
        'status': normalizedStatus,
        'download_url': downloadUrl,
        'title': title,
        'model': model,
        'outputType': outputType,
      });
    }

    // ✅ Show a local notification for user feedback
    final notifTitle = message.notification?.title ??
        (status == 'completed' ? 'Result ready' : 'Job update');
    final notifBody = message.notification?.body ??
        (status == 'completed'
            ? 'Your AI result is ready — tap to view.'
            : 'Job status: $status');

    await NotificationService.showNotification(
      title: notifTitle,
      body: notifBody,
      payload: jobId,
    );
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    debugPrint("🔁 onMessageOpenedApp: ${message.data}");
    final data = message.data ?? {};
    final jobId = (data['job_id'] ?? '').toString();
    if (jobId.isEmpty) return;

    // Normalize values
    const allowed = ['processing', 'completed', 'failed'];
    final status = (data['status'] ?? '').toString().toLowerCase();
    final normalizedStatus = allowed.contains(status) ? status : 'processing';
    final downloadUrl =
        (data['download_url'] ?? data['downloadUrl'] ?? '').toString();

    // 🧠 Preserve paths explicitly (optional but very safe)
    final currentJob = jobListNotifier.value.firstWhere((j) => j.jobId == jobId,
        orElse: () => JobModel(
              jobId: jobId,
              title: jobId,
              model: 'unknown',
              outputType: 'image',
            ));

    await updateJobFields(
      jobId: jobId,
      status: normalizedStatus.isNotEmpty ? normalizedStatus : null,
      downloadUrl: downloadUrl.isNotEmpty ? downloadUrl : null,
      inputImagePath: currentJob.inputImagePath,
      localFilePath: currentJob.localFilePath,
    );

    // ✅ Refresh and navigate
    if (isResultManagerOpen) {
      debugPrint("🔁 ResultManager already open after onMessageOpenedApp");
      return;
    }
    _openResultManager();
  });

// handle cold start
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    final data = initialMessage.data ?? {};
    final jobId = (data['job_id'] ?? '').toString();
    debugPrint("🟣 App launched from notification while killed: job=$jobId");

    // merge update into persisted jobs
    const allowed = ['processing', 'completed', 'failed'];
    final status = (data['status'] ?? '').toString().toLowerCase();
    final normalizedStatus = allowed.contains(status) ? status : 'processing';
    final downloadUrl =
        (data['download_url'] ?? data['downloadUrl'] ?? '').toString();
    await updateJobFields(
      jobId: jobId,
      status: normalizedStatus.isNotEmpty ? normalizedStatus : null,
      downloadUrl: downloadUrl.isNotEmpty ? downloadUrl : null,
    );

    // queue navigation to result manager (single instance)
    _pendingNavigations.clear();
    _pendingNavigations.add({
      "jobId": null,
      "config": null,
    });
  }

  // Ensure poller runs (keeps UI in sync if notifications fail)
  //PollingService.instance.start();
  //debugPrint("✅ PollingService started");

  // 🟢 Wrap the app in lifecycle handler (so jobs auto-refresh when app resumes)
  runApp(
    const AppLifecycleHandler(
      child: AICreativeStudio(),
    ),
  );

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

Future<void> _refreshJobsAfterNotification() async {
  try {
    debugPrint("🔄 Refreshing jobs after notification tap (FCM only)...");
    await _reloadJobsToNotifier(); // reloads jobListNotifier
  } catch (e) {
    debugPrint("⚠️ Failed to reload jobs: $e");
  }
}

/// ✅ Simplified — Always open the unified Result Manager page
///
void _openJobFromNotification(String jobId, GenericToolConfig? config) async {
  final nav = navigatorKey.currentState;

  if (nav == null) {
    debugPrint("⚠️ Navigator not ready yet, queuing job=$jobId");
    _pendingNavigations.add({"jobId": jobId, "config": config});
    return;
  }

  await _refreshJobsAfterNotification(); // 🆕 Force refresh on reopen

  debugPrint("🚀 Handling notification tap for job=$jobId");

  // ✅ Optional: Highlight Results tab or reset to home
  selectedIndexNotifier.value = 0;
  // ✅ Simplify route handling (next section)
  _openOrReplaceResultManager();
}

void _openResultManager() async {
  final nav = navigatorKey.currentState;
  if (nav == null) {
    debugPrint("⚠️ Navigator not ready yet, queueing ResultManagerPage");
    _pendingNavigations.add({"jobId": null, "config": null});
    return;
  }

  await _refreshJobsAfterNotification(); // 🆕 Force refresh
  selectedIndexNotifier.value = 2;
  _openOrReplaceResultManager();
}

void _openOrReplaceResultManager() {
  final nav = navigatorKey.currentState;
  if (nav == null) return;

  if (isResultManagerOpen) {
    debugPrint("🔁 ResultManagerPage already open — skipping navigation");
    return;
  }

  debugPrint("➡️ Opening new ResultManagerPage");
  nav.push(
    MaterialPageRoute(
      builder: (_) => const ResultManagerPage(),
      settings: const RouteSettings(name: 'ResultManagerPage'),
    ),
  );
}

// ----------------------------------------------------
// Root App
// ----------------------------------------------------
class AICreativeStudio extends StatelessWidget {
  const AICreativeStudio({super.key});

  final List<Widget> _pages = const [
    EditorPage(),
    VideoEditorPage(),
    AiToolsPage(),
    CreditsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    debugPrint("🟢 Building AICreativeStudio widget");

    return MaterialApp(
      title: 'AI Creative Studio',

      // ✅ NEW: Light + Dark theme pair
      theme: AppTheme.modernLight, // Light
      darkTheme: AppTheme.modernDark, // Dark

      // ✅ NEW: Controls which one is active
      themeMode: ThemeMode.system, // Auto-follow system theme
      // themeMode: ThemeMode.dark,       // Force dark
      // themeMode: ThemeMode.light,      // Force light

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

// ----------------------------------------------------
// Lifecycle handler to auto-refresh when app resumes
// ----------------------------------------------------
class AppLifecycleHandler extends StatefulWidget {
  final Widget child;
  const AppLifecycleHandler({required this.child, super.key});

  @override
  State<AppLifecycleHandler> createState() => _AppLifecycleHandlerState();
}

class _AppLifecycleHandlerState extends State<AppLifecycleHandler>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      debugPrint("🔁 App resumed — checking for FCM background updates");
      // await Future.delayed(const Duration(milliseconds: 500));
      // Always refresh jobs, but _reloadJobsToNotifier() now respects has_fcm_update
      await _reloadJobsToNotifier();

      // 🧠 Use PollingService to catch missed FCM updates (only for 'processing' jobs)
      await PollingService.instance.refreshProcessingJobs();

      debugPrint("✅ Jobs refreshed after resume");
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
