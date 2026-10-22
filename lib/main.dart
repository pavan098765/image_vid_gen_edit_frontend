// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' as material_ui;
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/polling_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/thumbnail_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Import the generated options file
import 'firebase_options.dart';

// Existing imports
import 'core/theme/app_theme.dart';
import 'core/app_state.dart';
import 'core/model_display_name.dart';
import 'core/tool_launch.dart';
import 'core/widgets/backlit_glass.dart';
import 'core/services/notification_service.dart';
import 'core/services/kie_result_saver.dart';
import 'core/services/user_service.dart';
import 'core/services/ad_service.dart';
import 'core/services/integrity_service.dart';
import 'core/services/model_cache_service.dart';
import 'core/services/sale_service.dart';

import 'features/media_editor/media_editor_page.dart';
import 'features/ai_tools/generic_tool_page.dart';
import 'features/explore/explore_ai_page.dart';
import 'features/credits/credits_page.dart';
import 'features/settings/settings_page.dart';
import 'features/studio/studio_page.dart';
import 'features/result_manager/result_manager_page.dart'; // 🔹 NEW import
import 'features/splash/splash_screen.dart'; // 🔹 Splash screen
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    if (deletedJobIds.contains(jobId)) {
      if (idx != -1) {
        existing.removeAt(idx);
        await prefs.setString('jobs', jsonEncode(existing));
        await prefs.reload();
      }
      debugPrint("🛡️ [FCM] Ignoring notification for deleted job $jobId");
      return;
    }
    if (idx != -1) {
      // Job exists - update it
      final old = existing[idx];
      existing[idx] = {
        ...old,
        'title': old['title'] ?? jobMap['title'] ?? jobId,
        'model': preferInternalModelId(
          old['model']?.toString(),
          jobMap['model']?.toString(),
        ),
        'outputType': old['outputType'] ?? jobMap['outputType'] ?? 'image',
        'downloadUrl':
            downloadUrl.isNotEmpty ? downloadUrl : (old['downloadUrl']),
        'status': status.isNotEmpty ? status : (old['status'] ?? 'processing'),
        'createdAt': old['createdAt'] ?? DateTime.now().toIso8601String(),
      };
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
/// 🚀 This is the PRIMARY way to get job updates - FCM data is trusted!
Future<void> _reloadJobsToNotifier({bool retryOnEmpty = true}) async {
  try {
    // 📁 FIRST: Apply any pending FCM updates from file
    // This is the most reliable cross-isolate sync mechanism
    final appliedFromFile = await applyPendingFcmUpdatesFromFile();
    if (appliedFromFile) {
      debugPrint("✅ Applied FCM updates from file - job list updated");
      final jobs = jobListNotifier.value;
      final completed = jobs.where((j) => j.status == 'completed').length;
      final processing = jobs.where((j) => j.status == 'processing').length;
      debugPrint("📊 Status after file sync: $completed completed, $processing processing");
      
      // CRITICAL: After applying file updates, we need to ensure SharedPreferences
      // is reloaded to get the latest data (file updates were saved to SharedPreferences).
      // But we should merge, not overwrite, to preserve any local data like localFilePath.
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // Reload to get the updates we just saved
      await Future.delayed(const Duration(milliseconds: 100)); // Give it time to flush
      await prefs.reload();
      
      // Now merge SharedPreferences data with current notifier to preserve local fields
      final jsonStr = prefs.getString('jobs');
      if (jsonStr != null) {
        try {
          final decoded = jsonDecode(jsonStr);
          if (decoded is List) {
            final prefsJobs = decoded
                .map((e) => JobModel.fromJson(Map<String, dynamic>.from(e)))
                .toList();
            
            // Merge: use SharedPreferences data (which has file updates) but preserve
            // any local fields from current notifier that might not be in SharedPreferences
            final currentJobs = jobListNotifier.value;
            final mergedJobs = <JobModel>[];
            
            // Safety check: if SharedPreferences has fewer jobs than current notifier,
            // something went wrong - keep current notifier data
            if (prefsJobs.length < currentJobs.length) {
              debugPrint("⚠️ [FCM File] SharedPreferences has ${prefsJobs.length} jobs but notifier has ${currentJobs.length} - keeping notifier data");
              // Still merge to get any updates, but don't lose jobs
              for (final currentJob in currentJobs) {
                final prefsJob = prefsJobs.firstWhere(
                  (j) => j.jobId == currentJob.jobId,
                  orElse: () => currentJob,
                );
                
                // Use prefsJob if it has newer status, otherwise keep currentJob
                final usePrefs = prefsJob.status != currentJob.status || 
                                (prefsJob.downloadUrl != null && prefsJob.downloadUrl != currentJob.downloadUrl);
                final sourceJob = usePrefs ? prefsJob : currentJob;
                
                final mergedJob = sourceJob.mergePreservingLaunch(currentJob);
                mergedJobs.add(mergedJob);
              }
            } else {
              // Normal merge: SharedPreferences has same or more jobs
              for (final prefsJob in prefsJobs) {
                final currentJob = currentJobs.firstWhere(
                  (j) => j.jobId == prefsJob.jobId,
                  orElse: () => prefsJob,
                );
                
                // Use prefsJob (has latest status/url) but preserve localFilePath if it exists
      final mergedJob = prefsJob.mergePreservingLaunch(currentJob);
                mergedJobs.add(mergedJob);
              }
            }
            
            jobListNotifier.value = await withoutDeletedJobs(mergedJobs);
            debugPrint("✅ Merged ${mergedJobs.length} jobs from file + SharedPreferences (current had ${currentJobs.length}, prefs had ${prefsJobs.length})");
            return; // Done - file updates applied and merged
          }
        } catch (e) {
          debugPrint("⚠️ Failed to merge SharedPreferences data: $e");
          // Continue with current notifier value (from file updates)
        }
      }
      return; // File updates applied, we're done
    }
    
    // 📦 FALLBACK: If no file updates, load from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    
    // 🔄 Multiple reload attempts to ensure cross-isolate sync
    await prefs.reload();
    await Future.delayed(const Duration(milliseconds: 50));
    await prefs.reload();

    // 🧩 Detect if background FCM updated while app minimized
    final hasUpdate = prefs.getBool('has_fcm_update') ?? false;
    if (hasUpdate) {
      debugPrint("📦 Detected FCM background update flag — applying reload");
      await prefs.remove('has_fcm_update');
      await prefs.reload();
    }

    final jsonStr = prefs.getString('jobs');
    if (jsonStr == null) {
      if (retryOnEmpty) {
        debugPrint("📂 No jobs found — retrying after delay...");
        await Future.delayed(const Duration(milliseconds: 200));
        await prefs.reload();
        final retryJson = prefs.getString('jobs');
        if (retryJson != null) {
          final decoded = jsonDecode(retryJson);
          if (decoded is List) {
            final list = decoded
                .map((e) => JobModel.fromJson(Map<String, dynamic>.from(e)))
                .toList();
            jobListNotifier.value = await withoutDeletedJobs(List<JobModel>.from(list));
            debugPrint("✅ Reloaded ${list.length} jobs on retry");
            return;
          }
        }
      }
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

    jobListNotifier.value = await withoutDeletedJobs(List<JobModel>.from(list));
    debugPrint("✅ Reloaded ${list.length} jobs from SharedPreferences");
    
    // Log status summary
    final completed = list.where((j) => j.status == 'completed').length;
    final processing = list.where((j) => j.status == 'processing').length;
    final failed = list.where((j) => j.status == 'failed').length;
    debugPrint("📊 Status: $completed completed, $processing processing, $failed failed");
  } catch (e, st) {
    debugPrint("⚠️ _reloadJobsToNotifier failed: $e\n$st");
  }
}

/// Called from all FCM receivers (background/foreground). Accepts raw message map
/// Expected keys: job_id, status, download_url, title, model, outputType (optional)
/// 
/// CRITICAL: This function writes to BOTH file and SharedPreferences to ensure
/// updates are never lost, regardless of app state (foreground/background/killed).
Future<void> _applyFcmUpdate(Map<String, dynamic> data) async {
  try {
    final jobId = (data['job_id'] ?? data['jobId'] ?? '').toString();
    if (jobId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (getDeletedJobIdsSync(prefs).contains(jobId)) {
      jobListNotifier.value = jobListNotifier.value
          .where((job) => job.jobId != jobId)
          .toList();
      debugPrint("🛡️ [FCM Foreground] Ignoring deleted job $jobId");
      return;
    }

    var status = (data['status'] ?? '').toString().toLowerCase();
    if (status == 'review') status = 'reviewing';
    if (status == 'done') status = 'completed';
    const allowed = [
      'processing',
      'completed',
      'failed',
      'reviewing',
      'provisioning',
      'queued',
      'running',
      'stitching',
      'uploading',
    ];
    final normalizedStatus = allowed.contains(status) ? status : 'processing';
    final downloadUrl = (data['download_url'] ?? data['downloadUrl'] ?? '').toString();
    final title = (data['title'] ?? '').toString();
    final model = (data['model'] ?? '').toString();
    final outputType = (data['outputType'] ?? '').toString();

    // 📁 FIRST: Write to file (most reliable, works across isolates)
    // This ensures updates are preserved even if SharedPreferences fails
    await writeFcmUpdateToFile({
      'jobId': jobId,
      'status': normalizedStatus,
      'downloadUrl': downloadUrl,
      'title': title.isNotEmpty ? title : jobId,
      'model': preferInternalModelId(model, 'unknown'),
      'outputType': outputType.isNotEmpty ? outputType : 'image',
      'timestamp': DateTime.now().toIso8601String(),
    });
    debugPrint('📁 [FCM Foreground] Wrote to file for job $jobId → $normalizedStatus');

    // 📦 ALSO: Merge into SharedPreferences (backup, might work on some platforms)
    await _mergeAndPersistJobMap({
      'job_id': jobId,
      'status': normalizedStatus,
      'download_url': downloadUrl,
      'title': title,
      'model': model,
      'outputType': outputType,
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
    const allowed = [
      'processing',
      'completed',
      'failed',
      'reviewing',
      'provisioning',
      'queued',
      'running',
      'stitching',
      'uploading',
    ];
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
    if (deletedJobIds.contains(jobId)) {
      if (idx >= 0) {
        existing.removeAt(idx);
        await prefs.setString('jobs', jsonEncode(existing));
        await prefs.reload();
      }
      debugPrint("🛡️ [FCM Background] Ignoring notification for deleted job $jobId");
      return;
    }

    if (idx >= 0) {
      // Job exists - update it
      final old = existing[idx];

      // 🧠 Preserve paths if they existed before
      final preservedInputImagePath = old['inputImagePath'];
      final preservedLocalPath = old['localFilePath'];

      existing[idx] = {
        ...old,
        'title': old['title'] ?? title,
        'model': preferInternalModelId(old['model']?.toString(), model),
        'outputType': old['outputType'] ?? outputType,
        'downloadUrl':
            downloadUrl.isNotEmpty ? downloadUrl : (old['downloadUrl']),
        'status': normalizedStatus.isNotEmpty
            ? normalizedStatus
            : (old['status'] ?? 'processing'),
        'createdAt': old['createdAt'] ?? DateTime.now().toIso8601String(),
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
        'model': preferInternalModelId(model, 'unknown'),
        'outputType': outputType.isNotEmpty ? outputType : 'image',
        'downloadUrl': downloadUrl.isNotEmpty ? downloadUrl : null,
        'status': normalizedStatus.isNotEmpty ? normalizedStatus : 'processing',
        'createdAt': DateTime.now().toIso8601String(),
        // keep null for these if truly new
        'inputImagePath': null,
        'localFilePath': null,
      });
    }

    // 📁 WRITE TO FILE FIRST for reliable cross-isolate sync
    // This is the PRIMARY sync mechanism - SharedPreferences can be unreliable
    // across isolates on some platforms (especially Android)!
    // File-based approach ensures main app can always read the updates.
    final jobCreatedAt = idx >= 0 
        ? (existing[idx]['createdAt'] ?? DateTime.now().toIso8601String())
        : DateTime.now().toIso8601String();
    
    await writeFcmUpdateToFile({
      'jobId': jobId,
      'status': normalizedStatus,
      'downloadUrl': downloadUrl,
      'title': title.isNotEmpty ? title : (idx >= 0 ? existing[idx]['title'] : jobId),
      'model': preferInternalModelId(
        idx >= 0 ? existing[idx]['model']?.toString() : null,
        model,
      ),
      'outputType': outputType.isNotEmpty ? outputType : (idx >= 0 ? existing[idx]['outputType'] : 'image'),
      'timestamp': jobCreatedAt,
    });
    debugPrint('📁 [FCM Background] Wrote to file FIRST for job $jobId → $normalizedStatus');
    
    // persist per-job download url key too (prevents global clobber)
    if (downloadUrl.isNotEmpty) {
      await prefs.setString('pending_download_url_$jobId', downloadUrl);
      debugPrint('📥 [FCM Background] Cached signed URL for $jobId (valid for ~1hr)');
    }

    // 📦 ALSO write to SharedPreferences (backup, might work on some platforms)
    await prefs.setString('jobs', jsonEncode(existing));
    await prefs.setBool('has_fcm_update', true);
    await prefs.reload(); // Force flush to disk
    debugPrint('📦 [FCM Background] Wrote to SharedPreferences for job $jobId');

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
  unawaited(ModelCacheService.prefetchInpaintModelInBackground());
  SaleService().start();
  
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
    const allowed = [
      'processing',
      'completed',
      'failed',
      'reviewing',
      'provisioning',
      'queued',
      'running',
      'stitching',
      'uploading',
    ];

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

    const allowed = [
      'processing',
      'completed',
      'failed',
      'reviewing',
      'provisioning',
      'queued',
      'running',
      'stitching',
      'uploading',
    ];
    final status = (data['status'] ?? '').toString().toLowerCase();
    final normalizedStatus = allowed.contains(status) ? status : 'processing';
    final downloadUrl = (data['download_url'] ?? data['downloadUrl'] ?? '').toString();
    final title = (data['title'] ?? '').toString();
    final model = (data['model'] ?? '').toString();
    final outputType = (data['outputType'] ?? '').toString();

    // 📁 FIRST: Write to file (ensures update is preserved)
    await writeFcmUpdateToFile({
      'jobId': jobId,
      'status': normalizedStatus,
      'downloadUrl': downloadUrl,
      'title': title.isNotEmpty ? title : jobId,
      'model': preferInternalModelId(model, 'unknown'),
      'outputType': outputType.isNotEmpty ? outputType : 'image',
      'timestamp': DateTime.now().toIso8601String(),
    });
    debugPrint('📁 [FCM OpenedApp] Wrote to file for job $jobId → $normalizedStatus');

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

    const allowed = [
      'processing',
      'completed',
      'failed',
      'reviewing',
      'provisioning',
      'queued',
      'running',
      'stitching',
      'uploading',
    ];
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
  FileService.remixAudio = (context, track) {
    return openMusicRemix(
      context,
      filePath: track.filePath,
      prompt: track.style,
      lyrics: track.lyrics,
      modelId: track.modelId,
    );
  };

  // 🟢 Run the app IMMEDIATELY to show splash screen
  // Heavy initialization happens in the background while splash is visible
  // ProviderScope is required for Riverpod (used by VideoEditorPage and its state)
  runApp(
    const ProviderScope(
      child: AppLifecycleHandler(
        child: KalaAIApp(),
      ),
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

  selectedIndexNotifier.value = AppTabs.creations;
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

  await _refreshJobsAfterNotification();
  selectedIndexNotifier.value = AppTabs.creations;
}

ModalRoute<void>? _openOrReplaceResultManager({String? initialJobId}) {
  final nav = navigatorKey.currentState;
  if (nav == null) return null;

  if (isResultManagerOpen) {
    debugPrint("🔁 ResultManagerPage already open — skipping navigation");
    return null;
  }

  debugPrint("➡️ Opening new ResultManagerPage");
  final route = MaterialPageRoute<void>(
    builder: (_) => ResultManagerPage(initialJobId: initialJobId),
    settings: const RouteSettings(name: 'ResultManagerPage'),
  );
  nav.push(route);
  return route;
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

  // Navigation: Editor, AI Explore, Studio, Creations, Store
  final List<Widget> _pages = const [
    MediaEditorPage(),
    ExploreAIPage(),
    StudioPage(),
    ResultManagerPage(asTab: true),
    CreditsPage(),
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
          localizationsDelegates: const [
            ...material_ui.GlobalMaterialLocalizations.delegates,
          ],

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
    
    final shell = Scaffold(
      key: appShellKey,
      backgroundColor: Colors.transparent,
      drawer: Drawer(
        width: MediaQuery.sizeOf(context).width * 0.88,
        child: const SettingsPage(inDrawer: true),
      ),
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

    return Stack(
      children: [
        const Positioned.fill(child: BacklitWash()),
        shell,
      ],
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
      const _NavItem(icon: LucideIcons.palette, label: 'Editor'),
      const _NavItem(icon: LucideIcons.sparkles, label: 'AI Explore'),
      const _NavItem(icon: LucideIcons.film, label: 'Studio'),
      const _NavItem(icon: LucideIcons.galleryVertical, label: 'Creations'),
      const _NavItem(icon: LucideIcons.gem, label: 'Store'),
    ];

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  const Color(0xFF2A1C38).withValues(alpha: 0.82),
                  const Color(0xFF120C16).withValues(alpha: 0.74),
                ]
              : [
                  Colors.white.withValues(alpha: 0.9),
                  const Color(0xFFF6F0FF).withValues(alpha: 0.78),
                ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.white,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFF6A4AD4))
                .withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, -6),
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
                                    colors: isDark
                                        ? [
                                            cs.primary.withValues(alpha: 0.34),
                                            cs.secondary.withValues(alpha: 0.16),
                                          ]
                                        : [
                                            const Color(0xFFE4D9FF),
                                            const Color(0xFFD7F4FF),
                                          ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: isSelected ? null : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: isSelected
                                ? Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.16)
                                        : Colors.white,
                                    width: 1,
                                  )
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: cs.primary.withValues(
                                        alpha: isDark ? 0.28 : 0.16,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
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
                          child: Text(
                            item.label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
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
    KieResultSaver.start(navigatorKey);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      debugPrint("🔁 App resumed — loading FCM data (file first, then SharedPreferences)");
      
      // ✅ PRIMARY: Always check FCM file FIRST (most reliable cross-isolate sync)
      // This ensures we get updates even if SharedPreferences didn't sync
      await _reloadJobsToNotifier();
      debugPrint("✅ Jobs loaded from FCM file + SharedPreferences");

      // 🔄 BACKUP: Server polling only as fallback for stale "processing" jobs
      // Delayed to not block UI, and only for jobs processing > 2 minutes
      // (gives FCM time to deliver, server call is just a safety net)
      _scheduleBackupServerCheck();
      await KieResultSaver.tick();
    }
  }

  /// 🔄 Schedule a delayed backup server check for any stuck "processing" jobs
  /// This is a safety net in case FCM failed to deliver
  void _scheduleBackupServerCheck() {
    Future.delayed(const Duration(seconds: 5), () async {
      // Only check if there are "processing" jobs older than 2 minutes
      final processingJobs = jobListNotifier.value
          .where((j) => j.status == 'processing')
          .where((j) {
            final age = DateTime.now().difference(j.createdAt).inMinutes;
            return age >= 2; // Only check jobs processing for > 2 minutes
          })
          .toList();

      if (processingJobs.isNotEmpty) {
        debugPrint("🔄 Backup check: ${processingJobs.length} stuck processing jobs (>2min old)");
        await PollingService.instance.refreshProcessingJobs(forceRefresh: true);
      } else {
        debugPrint("✅ No stuck processing jobs — skipping backup server check");
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
