// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/polling_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/thumbnail_service.dart';
import 'package:lucide_icons/lucide_icons.dart';
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
import 'core/services/user_service.dart';
import 'core/services/ad_service.dart';
import 'core/services/integrity_service.dart';

import 'features/media_editor/media_editor_page.dart';
import 'features/ai_tools/generic_tool_page.dart';
import 'features/explore/explore_ai_page.dart';
import 'features/credits/credits_page.dart';
import 'features/settings/settings_page.dart';
import 'features/result_manager/result_manager_page.dart'; // 🔹 NEW import
import 'features/splash/splash_screen.dart'; // 🔹 Splash screen
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

    final jobId = jobMap['job_id']?.toString();
    if (jobId == null || jobId.isEmpty) return;

    // 🛡️ Check if this job was previously deleted - don't recreate it
    final deletedJobIds = getDeletedJobIdsSync(prefs);
    
    final jsonStr = prefs.getString('jobs');
    final existing = jsonStr == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(jsonStr) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final status = (jobMap['status'] ?? '').toString();
    final downloadUrl = (jobMap['download_url'] ?? '').toString();

    final idx = existing.indexWhere((e) => e['jobId'] == jobId);
    if (idx != -1) {
      // Job exists - update it
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
    } else if (deletedJobIds.contains(jobId)) {
      // 🛡️ Job was deleted - don't recreate it
      debugPrint("🛡️ [FCM] Ignoring notification for deleted job $jobId");
      return;
    } else {
      // New job - create entry
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
      debugPrint('📥 [FCM] Cached signed URL for $jobId (valid for ~1hr)');
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
    final data = message.data;
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

    // 🛡️ Check if this job was previously deleted - don't recreate it
    final deletedJobIds = getDeletedJobIdsSync(prefs);

    final jsonStr = prefs.getString('jobs');
    final existing = jsonStr == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(jsonStr) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final idx = existing.indexWhere((e) => e['jobId'] == jobId);

    if (idx >= 0) {
      // Job exists - update it
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

        // ✅ Preserve file paths even if isolate didn't have them
        'localFilePath': preservedLocalPath,
        'inputImagePath': preservedInputImagePath,
      };

      debugPrint(
          "🟣 [FCM isolate] Preserved inputImagePath for $jobId → $preservedInputImagePath");
    } else if (deletedJobIds.contains(jobId)) {
      // 🛡️ Job was deleted - don't recreate it, skip notification too
      debugPrint("🛡️ [FCM Background] Ignoring notification for deleted job $jobId");
      return;
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
      debugPrint('📥 [FCM Background] Cached signed URL for $jobId (valid for ~1hr)');
    }

    await prefs.setString('jobs', jsonEncode(existing));
    await prefs.setBool('has_fcm_update', true);

    // 🔔 Local notification for visibility
    String notifTitle;
    String notifBody;
    
    // Check if server notification is valid (not generic/empty)
    final serverTitle = message.notification?.title ?? '';
    final serverBody = message.notification?.body ?? '';
    final isServerNotifValid = serverTitle.isNotEmpty && 
        !serverTitle.contains('Job Update') && 
        serverBody.isNotEmpty && 
        !serverBody.endsWith(':') &&
        !serverBody.contains('Job status:');
    
    if (isServerNotifValid) {
      notifTitle = serverTitle;
    } else if (normalizedStatus == 'completed') {
      notifTitle = 'Result ready ✨';
    } else if (normalizedStatus == 'failed') {
      notifTitle = 'Job failed';
    } else {
      notifTitle = 'Processing...';
    }
    
    if (isServerNotifValid) {
      notifBody = message.notification!.body!;
    } else if (normalizedStatus == 'completed') {
      notifBody = 'Your AI result is ready — tap to view.';
    } else if (normalizedStatus == 'failed') {
      notifBody = 'Something went wrong. Please try again.';
    } else {
      notifBody = 'Your job is being processed...';
    }
    
    await NotificationService.showNotification(
      title: notifTitle,
      body: notifBody,
      payload: jobId,
    );
  } catch (e, st) {
    debugPrint("⚠️ background handler error: $e\n$st");
  }
}

/// Shows integrity violation dialog and exits the app
/// This is called when tampering is detected
Future<void> _showIntegrityViolationAndExit(IntegrityResult result) async {
  // Ensure widgets are initialized for showing dialog
  WidgetsFlutterBinding.ensureInitialized();
  
  // Run the app with just an error screen
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.security,
                size: 80,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 24),
              const Text(
                'Security Alert',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                result.message,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'This app cannot run on this device.\n'
                'Please reinstall from the official app store.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  // Exit the app
                  SystemNavigator.pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                ),
                child: const Text(
                  'Close App',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ));
  
  // Wait a bit then force exit (in case user doesn't tap button)
  await Future.delayed(const Duration(seconds: 30));
  SystemNavigator.pop();
}

/// App initialization that runs while splash is visible
/// Returns a Future that completes when all services are ready
Future<void> initializeApp() async {
  debugPrint("🚀 Starting app initialization...");
  
  // ============================================================
  // INTEGRITY CHECK - Run FIRST before initializing anything else
  // ============================================================
  final integrityResult = await IntegrityService.instance.checkIntegrity();
  if (!integrityResult.passed) {
    debugPrint("🚨 INTEGRITY CHECK FAILED: ${integrityResult.status}");
    debugPrint("   Message: ${integrityResult.message}");
    debugPrint("   Details: ${integrityResult.details}");
    
    // Show error and close app
    await _showIntegrityViolationAndExit(integrityResult);
    return; // Should not reach here as app exits
  }
  debugPrint("✅ Integrity check passed");
  
  // Initialize Firebase first (required for other services)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("✅ Firebase initialized");

  // Initialize persistent app state
  await initAppState();
  await AppSettings.load();
  await loadSeenJobs(); // Load shared seen jobs state
  await FileService.loadPreviewCache();
  await ThumbnailService.instance.init();
  await UserService().initialize();
  await AdService.initialize();
  
  // ============================================================
  // AD-FREE STATUS - Requires authentication + server verification
  // ============================================================
  // Reset ad-free status - will be verified after auth check
  resetAdFreeVerification();
  
  // Check ad-free status from server (after user service is ready)
  // This validates the local cached status with the server
  // Only authenticated users can be ad-free
  if (currentUserNotifier.value != null) {
    final isAdFree = await UserService().checkAdFreeStatus();
    notifyAdFreeStatusChanged(isAdFree, verifiedByServer: true);
    debugPrint("✅ Ad-free status verified: $isAdFree");
  } else {
    debugPrint("ℹ️ User not authenticated - ads will be shown");
  }
  
  debugPrint("✅ App state initialized");

  // Register background handler for FCM
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize notification service
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

  // Setup FCM
  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission(alert: true, badge: true, sound: true);

  final token = await fcm.getToken();
  debugPrint("🔑 FCM Token: $token");
  final prefs = await SharedPreferences.getInstance();
  if (token != null) await prefs.setString("fcm_token", token);

  // FCM token refresh listener
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    debugPrint("🔄 FCM token refreshed: $newToken");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("fcm_token", newToken);
  });

  // Foreground messages handler
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    debugPrint("📩 FCM onMessage: ${message.messageId} data=${message.data}");

    final data = message.data;
    final jobId = (data['job_id'] ?? '').toString();
    const allowed = ['processing', 'completed', 'failed'];

    final status = (data['status'] ?? '').toString().toLowerCase();
    final normalizedStatus = allowed.contains(status) ? status : 'processing';
    final downloadUrl = (data['download_url'] ?? data['downloadUrl'] ?? '').toString();
    final title = (data['title'] ?? '').toString();
    final model = (data['model'] ?? '').toString();
    final outputType = (data['outputType'] ?? '').toString();

    // 🛡️ EMPTY NOTIFICATION CHECK
    // Server sometimes sends empty data payloads for bulk/variation jobs
    // When this happens, trigger a refresh instead of showing confusing notifications
    if (data.isEmpty || jobId.isEmpty) {
      debugPrint("⚠️ FCM received empty data payload - triggering job refresh");
      debugPrint("   notification.title: ${message.notification?.title}");
      debugPrint("   notification.body: ${message.notification?.body}");
      debugPrint("   data keys: ${data.keys.toList()}");
      
      // Trigger a refresh to catch any updates the empty notification was about
      await PollingService.instance.refreshProcessingJobs(forceRefresh: true);
      
      // Don't show notification for empty data - it's confusing
      return;
    }

//     // 🐛 DEBUG: Show raw FCM data in snackbar (REMOVE AFTER DEBUGGING)
//     if (navigatorKey.currentContext != null) {
//       final debugInfo = '''
// 🔔 FCM DEBUG
// job_id: $jobId
// raw_status: ${data['status']}
// normalized: $normalizedStatus
// title: $title
// model: $model
// notif_title: ${message.notification?.title}
// notif_body: ${message.notification?.body}
// download_url: ${downloadUrl.isNotEmpty ? '${downloadUrl.substring(0, 50.clamp(0, downloadUrl.length))}...' : 'empty'}
// all_data: ${data.keys.join(', ')}
// ''';
//       ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
//         SnackBar(
//           content: Text(debugInfo, style: const TextStyle(fontSize: 11)),
//           duration: const Duration(seconds: 10),
//           backgroundColor: Colors.black87,
//           behavior: SnackBarBehavior.floating,
//           action: SnackBarAction(
//             label: 'Dismiss',
//             textColor: Colors.cyan,
//             onPressed: () {},
//           ),
//         ),
//       );
//     }
//     // 🐛 END DEBUG

    await _applyFcmUpdate({
      'job_id': jobId,
      'status': normalizedStatus,
      'download_url': downloadUrl,
      'title': title,
      'model': model,
      'outputType': outputType,
    });

    // Use normalizedStatus for notification content (not raw status which might be empty)
    // Also check if server notification is valid (not generic/incomplete)
    String notifTitle;
    String notifBody;
    
    final serverTitle = message.notification?.title ?? '';
    final serverBody = message.notification?.body ?? '';
    final isServerNotifValid = serverTitle.isNotEmpty && 
        !serverTitle.contains('Job Update') && 
        serverBody.isNotEmpty && 
        !serverBody.endsWith(':') &&
        !serverBody.contains('Job status:');
    
    if (isServerNotifValid) {
      notifTitle = serverTitle;
    } else if (normalizedStatus == 'completed') {
      notifTitle = 'Result ready ✨';
    } else if (normalizedStatus == 'failed') {
      notifTitle = 'Job failed';
    } else {
      notifTitle = 'Processing...';
    }
    
    if (isServerNotifValid) {
      notifBody = serverBody;
    } else if (normalizedStatus == 'completed') {
      notifBody = 'Your AI result is ready — tap to view.';
    } else if (normalizedStatus == 'failed') {
      notifBody = 'Something went wrong. Please try again.';
    } else {
      notifBody = 'Your job is being processed...';
    }

    await NotificationService.showNotification(
      title: notifTitle,
      body: notifBody,
      payload: jobId,
    );
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    debugPrint("🔁 onMessageOpenedApp: ${message.data}");
    final data = message.data;
    final jobId = (data['job_id'] ?? '').toString();
    if (jobId.isEmpty) return;

    const allowed = ['processing', 'completed', 'failed'];
    final status = (data['status'] ?? '').toString().toLowerCase();
    final normalizedStatus = allowed.contains(status) ? status : 'processing';
    final downloadUrl = (data['download_url'] ?? data['downloadUrl'] ?? '').toString();

    final currentJob = jobListNotifier.value.firstWhere(
      (j) => j.jobId == jobId,
      orElse: () => JobModel(
        jobId: jobId,
        title: jobId,
        model: 'unknown',
        outputType: 'image',
      ),
    );

    await updateJobFields(
      jobId: jobId,
      status: normalizedStatus.isNotEmpty ? normalizedStatus : null,
      downloadUrl: downloadUrl.isNotEmpty ? downloadUrl : null,
      inputImagePath: currentJob.inputImagePath,
      localFilePath: currentJob.localFilePath,
    );

    if (isResultManagerOpen) {
      debugPrint("🔁 ResultManager already open after onMessageOpenedApp");
      return;
    }
    _openResultManager();
  });

  // Handle cold start from notification
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    final data = initialMessage.data;
    final jobId = (data['job_id'] ?? '').toString();
    debugPrint("🟣 App launched from notification while killed: job=$jobId");

    const allowed = ['processing', 'completed', 'failed'];
    final status = (data['status'] ?? '').toString().toLowerCase();
    final normalizedStatus = allowed.contains(status) ? status : 'processing';
    final downloadUrl = (data['download_url'] ?? data['downloadUrl'] ?? '').toString();
    
    await updateJobFields(
      jobId: jobId,
      status: normalizedStatus.isNotEmpty ? normalizedStatus : null,
      downloadUrl: downloadUrl.isNotEmpty ? downloadUrl : null,
    );

    _pendingNavigations.clear();
    _pendingNavigations.add({
      "jobId": null,
      "config": null,
    });
  }

  debugPrint("✅ App initialization complete");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 🟢 Run the app IMMEDIATELY to show splash screen
  // Heavy initialization happens in the background while splash is visible
  runApp(
    const AppLifecycleHandler(
      child: KalaAIApp(),
    ),
  );

  debugPrint("✅ runApp() executed - splash visible now");

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
  selectedIndexNotifier.value = 1; // AI Explore tab
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
// Root App - Kala AI
// ----------------------------------------------------
class KalaAIApp extends StatefulWidget {
  const KalaAIApp({super.key});

  @override
  State<KalaAIApp> createState() => _KalaAIAppState();
}

class _KalaAIAppState extends State<KalaAIApp> {
  bool _showSplash = true;

  // Navigation: Editor, AI Explore, Store, Settings (AI Tools accessible from Explore)
  final List<Widget> _pages = const [
    MediaEditorPage(),
    ExploreAIPage(),
    CreditsPage(),
    SettingsPage(),
  ];

  void _onSplashComplete() {
    if (mounted) {
      setState(() => _showSplash = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("🟢 Building KalaAIApp widget");

    // Listen to theme changes from settings
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Kala AI',

          // Light + Dark theme pair
          theme: AppTheme.modernLight,
          darkTheme: AppTheme.modernDark,

          // Controls which theme is active - now reactive!
          themeMode: themeMode,

          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,

          home: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _showSplash
                ? SplashScreen(
                    key: const ValueKey('splash'),
                    onComplete: _onSplashComplete,
                  )
                : _MainAppScaffold(
                    key: const ValueKey('main'),
                    pages: _pages,
                  ),
          ),
        );
      },
    );
  }
}

// Extracted main scaffold to separate widget for cleaner code
class _MainAppScaffold extends StatelessWidget {
  final List<Widget> pages;
  
  const _MainAppScaffold({
    super.key,
    required this.pages,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: selectedIndexNotifier,
          builder: (_, currentIndex, __) {
            return IndexedStack(
              index: currentIndex,
              children: pages,
            );
          },
        ),
      ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: selectedIndexNotifier,
        builder: (_, currentIndex, __) {
          return _ModernBottomNav(
            currentIndex: currentIndex,
            onTap: (i) => selectedIndexNotifier.value = i,
            colorScheme: cs,
            isDark: isDark,
          );
        },
      ),
    );
  }
}

// Custom modern bottom navigation bar with curves
class _ModernBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final ColorScheme colorScheme;
  final bool isDark;

  const _ModernBottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.colorScheme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    
    // Navigation items configuration
    final items = [
      _NavItem(icon: LucideIcons.palette, label: 'Editor'),
      _NavItem(icon: LucideIcons.sparkles, label: 'AI Explore'),
      _NavItem(icon: LucideIcons.gem, label: 'Store'),
      _NavItem(icon: LucideIcons.settings, label: 'Settings'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = index == currentIndex;
              
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onTap(index);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Icon with animated container
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.symmetric(
                            horizontal: isSelected ? 16 : 10,
                            vertical: isSelected ? 8 : 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? LinearGradient(
                                    colors: [
                                      cs.primary.withValues(alpha: 0.2),
                                      cs.secondary.withValues(alpha: 0.15),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: isSelected ? null : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: isSelected
                                ? Border.all(
                                    color: cs.primary.withValues(alpha: 0.3),
                                    width: 1,
                                  )
                                : null,
                          ),
                          child: Icon(
                            item.icon,
                            size: isSelected ? 26 : 24,
                            color: isSelected 
                                ? cs.primary 
                                : cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 3),
                        // Label
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: isSelected ? 12 : 11,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected 
                                ? cs.primary 
                                : cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          child: Text(item.label),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  
  const _NavItem({required this.icon, required this.label});
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
