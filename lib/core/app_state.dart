// lib/core/app_state.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/job_model.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import user service for credit notifier, ad-free state, and VIP state
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart'
    show
        userCreditsNotifier,
        currentUserNotifier,
        isLoadingUserNotifier,
        UserData,
        isAdFreeNotifier,
        shouldShowAds,
        shouldShowNativeBannerAds,
        shouldRequireHeavyTierRewardedAd,
        completeHeavyTierRewardedAdIfNeeded,
        adExperienceNotifier,
        applyAuthUserApiFields,
        notifyAdFreeStatusChanged,
        resetAdFreeVerification,
        VipStatus,
        vipStatusNotifier,
        isVipUser,
        getMaxVariations,
        canUseBulkEdit,
        isUpscaleFree,
        notifyVipStatusChanged,
        resetVipVerification;

// Re-export for other files that import app_state.dart
export 'package:kala_ai_create_images_videos_with_ai/core/job_model.dart';
export 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart'
    show
        userCreditsNotifier,
        currentUserNotifier,
        isLoadingUserNotifier,
        UserData,
        isAdFreeNotifier,
        shouldShowAds,
        shouldShowNativeBannerAds,
        shouldRequireHeavyTierRewardedAd,
        completeHeavyTierRewardedAdIfNeeded,
        adExperienceNotifier,
        applyAuthUserApiFields,
        notifyAdFreeStatusChanged,
        resetAdFreeVerification,
        VipStatus,
        vipStatusNotifier,
        isVipUser,
        getMaxVariations,
        canUseBulkEdit,
        isUpscaleFree,
        notifyVipStatusChanged,
        resetVipVerification;

/// Global app-level selected index for the bottom navigation.
final ValueNotifier<int> selectedIndexNotifier = ValueNotifier<int>(0);

/// Global notifier for email verification status changes
/// When email is verified from any screen, this notifier is updated
/// so all listening screens can refresh their UI
final ValueNotifier<bool> emailVerifiedNotifier = ValueNotifier<bool>(false);

/// Call this when email verification status changes (from any screen)
void notifyEmailVerificationChanged(bool isVerified) {
  emailVerifiedNotifier.value = isVerified;
  debugPrint("📧 Email verification status changed: $isVerified");
}

/// Global theme mode notifier - controls app-wide theme
final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.system);

/// Global seen jobs notifier - tracks which completed jobs user has seen
/// Shared between ai_tools_page and explore_ai_page
final ValueNotifier<Set<String>> seenJobIdsNotifier =
    ValueNotifier<Set<String>>({});
const String _seenJobsKey = 'seen_completed_job_ids';

/// Load seen jobs from SharedPreferences
Future<void> loadSeenJobs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final seenList = prefs.getStringList(_seenJobsKey) ?? [];
    seenJobIdsNotifier.value = seenList.toSet();
  } catch (e) {
    debugPrint('⚠️ Failed to load seen jobs: $e');
  }
}

/// Mark all completed jobs as seen
Future<void> markAllCompletedJobsAsSeen() async {
  try {
    final completedJobs = jobListNotifier.value
        .where((j) => j.status == 'completed')
        .map((j) => j.jobId)
        .toList();
    final updatedSet = Set<String>.from(seenJobIdsNotifier.value)
      ..addAll(completedJobs);
    seenJobIdsNotifier.value = updatedSet;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_seenJobsKey, updatedSet.toList());
  } catch (e) {
    debugPrint('⚠️ Failed to save seen jobs: $e');
  }
}

/// Get count of unseen completed jobs
int getUnseenCompletedJobCount() {
  return jobListNotifier.value
      .where((j) =>
          j.status == 'completed' &&
          !seenJobIdsNotifier.value.contains(j.jobId))
      .length;
}

/// Check if there are unseen completed jobs
bool hasUnseenCompletedJobs() {
  return getUnseenCompletedJobCount() > 0;
}

/// App Settings that can be read from anywhere
class AppSettings {
  static bool highQualityPreviews = true;
  static bool notificationsEnabled = true;

  /// Load settings from SharedPreferences
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load theme mode
      final themeModeIndex = prefs.getInt('theme_mode') ?? 0;
      themeModeNotifier.value = ThemeMode.values[themeModeIndex.clamp(0, 2)];

      // Load other settings
      highQualityPreviews = prefs.getBool('high_quality_previews') ?? true;
      notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;

      debugPrint(
          "⚙️ Settings loaded: theme=${themeModeNotifier.value}, highQuality=$highQualityPreviews");
    } catch (e) {
      debugPrint("⚠️ Failed to load settings: $e");
    }
  }

  /// Save a specific setting
  static Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }

  static Future<void> setHighQualityPreviews(bool value) async {
    highQualityPreviews = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('high_quality_previews', value);
  }

  static Future<void> setNotificationsEnabled(bool value) async {
    notificationsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', value);
  }
}

/// Helpful constants for default tab indices.
/// Adjust if you reorder the tabs in main.dart.
/// Navigation: Editor (0), AI Explore (1), Studio (2), Store/Credits (3), Settings (4)
class AppTabs {
  static const int editor = 0;
  static const int explore = 1;
  static const int studio = 2;
  static const int creations = 3;
  static const int credits = 4;
}

/// Shell scaffold. The menu button opens its drawer.
final GlobalKey<ScaffoldState> appShellKey = GlobalKey<ScaffoldState>();

void openAppMenu() {
  appShellKey.currentState?.openDrawer();
}

/// Global list of jobs
final jobListNotifier = ValueNotifier<List<JobModel>>([]);

Future<String> generateFriendlyJobName() async {
  final now = DateTime.now();
  final formatted = "${now.month.toString().padLeft(2, '0')}"
      "${now.day.toString().padLeft(2, '0')}"
      "${now.minute.toString().padLeft(2, '0')}"
      "${now.second.toString().padLeft(2, '0')}";
  return "Job-$formatted";
}

/// 🚀 Save jobs to SharedPreferences (called automatically on changes)
Future<void> saveJobsToPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final list = jobListNotifier.value.map((j) => j.toJson()).toList();
    await prefs.setString('jobs', jsonEncode(list));
    debugPrint("💾 Saved ${list.length} jobs to prefs");
  } catch (e) {
    debugPrint("⚠️ Failed to save jobs: $e");
  }
}

/// True when this job was removed from Result Manager and must stay gone.
Future<bool> wasJobDeleted(String jobId) async {
  if (jobId.isEmpty) return false;
  final prefs = await SharedPreferences.getInstance();
  return getDeletedJobIdsSync(prefs).contains(jobId);
}

/// Drops jobs the user already deleted, and rewrites prefs when any were present.
Future<List<JobModel>> withoutDeletedJobs(List<JobModel> jobs) async {
  final prefs = await SharedPreferences.getInstance();
  final blocked = getDeletedJobIdsSync(prefs).toSet();
  if (blocked.isEmpty) return jobs;
  final kept = jobs.where((job) => !blocked.contains(job.jobId)).toList();
  if (kept.length != jobs.length) {
    await prefs.setString(
      'jobs',
      jsonEncode(kept.map((job) => job.toJson()).toList()),
    );
  }
  return kept;
}

/// Add a new job or update existing by jobId. Persists immediately.
Future<void> addOrUpdateJob(JobModel job) async {
  if (await wasJobDeleted(job.jobId)) {
    final kept = jobListNotifier.value
        .where((existing) => existing.jobId != job.jobId)
        .toList();
    if (kept.length != jobListNotifier.value.length) {
      jobListNotifier.value = kept;
      await saveJobsToPrefs();
    }
    return;
  }
  job.stampCloudReady();
  final list = List<JobModel>.from(jobListNotifier.value);
  final idx = list.indexWhere((j) => j.jobId == job.jobId);
  if (idx >= 0) {
    list[idx] = job;
  } else {
    list.insert(0, job);
  }

  jobListNotifier.value = list;
  await saveJobsToPrefs();
}

/// Update only specific fields for a job (status/downloadUrl/title/model optional).
/// If job does not exist it creates a new one with defaults.
Future<void> updateJobFields({
  required String jobId,
  String? status,
  String? downloadUrl,
  String? title,
  String? model,
  String? outputType,
  String? inputImagePath, // ✅ optional explicit override
  String? localFilePath, // ✅ optional explicit override
  int? estimatedWaitSeconds,
  int? queuePosition,
  // NEW: Variation and prompt enhancement fields
  int? variations,
  List<VariationResult>? variationResults,
  bool? allCompleted,
  String? enhancedPrompt,
  bool? promptEnhanced,
  String? originalPrompt,
  Map<String, dynamic>? music,
}) async {
  if (await wasJobDeleted(jobId)) {
    final kept =
        jobListNotifier.value.where((job) => job.jobId != jobId).toList();
    if (kept.length != jobListNotifier.value.length) {
      jobListNotifier.value = kept;
      await saveJobsToPrefs();
    }
    return;
  }
  final list = List<JobModel>.from(jobListNotifier.value);
  final idx = list.indexWhere((j) => j.jobId == jobId);

  if (idx >= 0) {
    final old = list[idx];

    // 🛡️ NEVER downgrade terminal status (completed/failed → processing)
    String finalStatus = status ?? old.status;
    if ((old.status == 'completed' || old.status == 'failed') &&
        status != null &&
        status == 'processing') {
      debugPrint(
          "🛡️ updateJobFields: Blocking status downgrade for job $jobId: ${old.status} → $status");
      finalStatus = old.status;
    }

    list[idx] = old.copyWith(
      title: title,
      model: model,
      outputType: outputType,
      downloadUrl:
          (downloadUrl != null && downloadUrl.isNotEmpty) ? downloadUrl : null,
      status: finalStatus,
      localFilePath: localFilePath,
      inputImagePath: inputImagePath,
      estimatedWaitSeconds: estimatedWaitSeconds,
      queuePosition: queuePosition,
      variations: variations,
      variationResults: variationResults,
      allCompleted: allCompleted,
      enhancedPrompt: enhancedPrompt,
      promptEnhanced: promptEnhanced,
      originalPrompt: originalPrompt,
      music: preferRicherMusic(old.music, music),
    );
    list[idx].stampCloudReady();

    if (status != null) {
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
      if (!allowed.contains(status.toLowerCase())) {
        status = 'processing';
      }
    }
  } else {
    final created = JobModel(
      jobId: jobId,
      title: title ?? await generateFriendlyJobName(),
      model: model ?? 'unknown',
      outputType: outputType ?? 'image',
      downloadUrl: (downloadUrl != null && downloadUrl.isNotEmpty)
          ? downloadUrl
          : null,
      status: status ?? 'processing',
      inputImagePath: inputImagePath,
      localFilePath: localFilePath,
      estimatedWaitSeconds: estimatedWaitSeconds,
      queuePosition: queuePosition,
      variations: variations ?? 1,
      variationResults: variationResults,
      allCompleted: allCompleted ?? false,
      enhancedPrompt: enhancedPrompt,
      promptEnhanced: promptEnhanced ?? false,
      originalPrompt: originalPrompt,
      music: music,
    );
    created.stampCloudReady();
    list.insert(0, created);
  }

  jobListNotifier.value = list;
  await saveJobsToPrefs();
}

// ----------------------
// 🔄 FILE-BASED FCM UPDATES (more reliable than SharedPreferences for cross-isolate)
// ----------------------

/// Job ids whose push only carried one file. The next status fetch restores versions.
final List<String> _fcmJobsToRefresh = [];

List<String> takeFcmJobsToRefresh() {
  final ids = List<String>.from(_fcmJobsToRefresh);
  _fcmJobsToRefresh.clear();
  return ids;
}
const String _fcmUpdatesFileName = 'fcm_pending_updates.json';

/// Get the FCM updates file path
Future<File> getFcmUpdatesFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/$_fcmUpdatesFileName');
}

/// Write FCM update to file (called from background isolate)
/// This is more reliable than SharedPreferences for cross-isolate communication
/// Uses retry logic to handle potential concurrent access issues.
Future<void> writeFcmUpdateToFile(Map<String, dynamic> jobUpdate) async {
  const maxRetries = 3;

  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      final file = await getFcmUpdatesFile();

      // Read existing updates
      List<Map<String, dynamic>> updates = [];
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty && content != '[]') {
          try {
            final decoded = jsonDecode(content);
            if (decoded is List) {
              updates =
                  decoded.map((e) => Map<String, dynamic>.from(e)).toList();
            }
          } catch (parseError) {
            // File might be corrupted or mid-write, start fresh
            debugPrint(
                "⚠️ [FCM File] Parse error on read, starting fresh: $parseError");
            updates = [];
          }
        }
      }

      // Add or update this job
      final jobId = jobUpdate['jobId'];
      final existingIdx = updates.indexWhere((u) => u['jobId'] == jobId);
      if (existingIdx >= 0) {
        // Merge with existing update (preserve fields that might be missing)
        final existing = updates[existingIdx];
        updates[existingIdx] = {
          ...existing,
          ...jobUpdate,
        };
      } else {
        updates.add(jobUpdate);
      }

      // Write back to file
      final jsonContent = jsonEncode(updates);
      await file.writeAsString(jsonContent, flush: true);
      debugPrint(
          "📁 [FCM File] Wrote update for job $jobId to file (attempt $attempt)");
      return; // Success, exit
    } catch (e) {
      debugPrint("⚠️ [FCM File] Write attempt $attempt failed: $e");
      if (attempt < maxRetries) {
        // Wait before retry with exponential backoff
        await Future.delayed(Duration(milliseconds: 100 * attempt));
      }
    }
  }

  // All retries failed
  debugPrint("❌ [FCM File] Failed to write after $maxRetries attempts");
}

/// Read and apply all pending FCM updates from file (called on app startup)
/// Returns true if any updates were applied
///
/// CRITICAL FIX: This function now CREATES new jobs if they don't exist in SharedPreferences.
/// Background isolate writes to SharedPreferences might not sync to main app, so we rely
/// on file-based updates to ensure jobs are properly created/updated.
Future<bool> applyPendingFcmUpdatesFromFile() async {
  try {
    final file = await getFcmUpdatesFile();

    if (!await file.exists()) {
      debugPrint("📁 [FCM File] No pending updates file");
      return false;
    }

    // Small delay to ensure any in-flight background writes complete
    await Future.delayed(const Duration(milliseconds: 30));

    final content = await file.readAsString();
    if (content.isEmpty || content == '[]') {
      debugPrint("📁 [FCM File] Updates file is empty");
      return false;
    }

    List<dynamic> decoded;
    try {
      decoded = jsonDecode(content);
    } catch (e) {
      // File might be mid-write, wait and retry once
      debugPrint("⚠️ [FCM File] JSON parse failed, retrying in 200ms: $e");
      await Future.delayed(const Duration(milliseconds: 200));
      try {
        final retryContent = await file.readAsString();
        if (retryContent.isEmpty || retryContent == '[]') {
          return false;
        }
        decoded = jsonDecode(retryContent);
      } catch (retryError) {
        debugPrint(
            "⚠️ [FCM File] Retry failed, clearing corrupt file: $retryError");
        await file.writeAsString('[]');
        return false;
      }
    }

    if (decoded.isEmpty) {
      debugPrint("📁 [FCM File] No pending updates in file");
      return false;
    }

    debugPrint(
        "📁 [FCM File] Found ${decoded.length} pending updates - applying...");

    // Log all job IDs in the file for debugging
    final jobIdsInFile =
        decoded.map((u) => u['jobId']?.toString() ?? 'unknown').toList();
    debugPrint("📁 [FCM File] Job IDs in file: ${jobIdsInFile.join(', ')}");

    // Apply each update to the job list
    final prefs = await SharedPreferences.getInstance();

    // Multiple reload attempts to ensure we have fresh data
    await prefs.reload();
    await Future.delayed(const Duration(milliseconds: 20));
    await prefs.reload();

    final jsonStr = prefs.getString('jobs');
    final jobs = jsonStr == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(jsonStr) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    // Get deleted job IDs to prevent recreating deleted jobs
    final deletedJobIds = getDeletedJobIdsSync(prefs);

    bool anyUpdated = false;
    int updatedCount = 0;
    int createdCount = 0;
    int skippedCount = 0;

    for (final update in decoded) {
      final jobId = update['jobId']?.toString();
      if (jobId == null || jobId.isEmpty) continue;

      final newStatus = update['status']?.toString() ?? 'processing';
      final newUrl = update['downloadUrl']?.toString();
      final newTitle = update['title']?.toString();
      final newModel = update['model']?.toString();
      final newOutputType = update['outputType']?.toString();
      final timestamp = update['timestamp']?.toString();

      final idx = jobs.indexWhere((j) => j['jobId'] == jobId);

      if (deletedJobIds.contains(jobId)) {
        if (idx >= 0) {
          jobs.removeAt(idx);
          anyUpdated = true;
        }
        debugPrint("📁 [FCM File] Skipping deleted job $jobId");
        skippedCount++;
        continue;
      }

      if (idx >= 0) {
        // ✅ UPDATE existing job
        final old = jobs[idx];
        final oldStatus = old['status']?.toString() ?? 'processing';

        // Only update if FCM has newer/better data (completed/failed > processing)
        final shouldUpdate = newStatus == 'completed' ||
            newStatus == 'failed' ||
            oldStatus == 'processing';

        if (shouldUpdate) {
          jobs[idx] = {
            ...old,
            'status': newStatus,
            if (newUrl != null && newUrl.isNotEmpty) 'downloadUrl': newUrl,
          };
          if (!_fcmJobsToRefresh.contains(jobId)) _fcmJobsToRefresh.add(jobId);
          debugPrint(
              "📁 [FCM File] ✅ Updated job $jobId: $oldStatus → $newStatus (URL: ${newUrl != null && newUrl.isNotEmpty ? 'present' : 'missing'})");
          anyUpdated = true;
          updatedCount++;
        } else {
          debugPrint(
              "📁 [FCM File] ⏭️ Skipped job $jobId: oldStatus=$oldStatus, newStatus=$newStatus (no update needed)");
        }
      } else {
        // ✅ CREATE new job (this was the missing piece!)
        // Background isolate wrote to SharedPreferences but main app didn't see it
        final newJob = {
          'jobId': jobId,
          'title': (newTitle != null && newTitle.isNotEmpty) ? newTitle : jobId,
          'model':
              (newModel != null && newModel.isNotEmpty) ? newModel : 'unknown',
          'outputType': (newOutputType != null && newOutputType.isNotEmpty)
              ? newOutputType
              : 'image',
          'downloadUrl': (newUrl != null && newUrl.isNotEmpty) ? newUrl : null,
          'status': newStatus,
          'createdAt': timestamp ?? DateTime.now().toIso8601String(),
          'localFilePath': null,
          'inputImagePath': null,
        };
        jobs.insert(0, newJob);
        if (!_fcmJobsToRefresh.contains(jobId)) _fcmJobsToRefresh.add(jobId);
        debugPrint(
            "📁 [FCM File] ✅ Created NEW job $jobId (status: $newStatus, URL: ${newUrl != null && newUrl.isNotEmpty ? 'present' : 'missing'}) - was missing from SharedPreferences!");
        anyUpdated = true;
        createdCount++;

        // Also cache the download URL separately
        if (newUrl != null && newUrl.isNotEmpty) {
          await prefs.setString('pending_download_url_$jobId', newUrl);
        }
      }
    }

    if (anyUpdated) {
      // Save to SharedPreferences with multiple flush attempts
      await prefs.setString('jobs', jsonEncode(jobs));
      await prefs.reload(); // First reload
      await Future.delayed(
          const Duration(milliseconds: 100)); // Give time to flush
      await prefs.reload(); // Second reload to verify

      // Update notifier with the merged jobs
      jobListNotifier.value = await withoutDeletedJobs(
        jobs
            .map((e) => JobModel.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

      debugPrint(
          "✅ [FCM File] Applied updates: $updatedCount updated, $createdCount created, $skippedCount skipped");
      debugPrint(
          "✅ [FCM File] Saved ${jobs.length} total jobs to SharedPreferences");

      // IMPORTANT: Only clear the file AFTER we've successfully saved to SharedPreferences
      // AND verified the notifier is updated. This ensures if app crashes, we can retry on next startup
      await file.writeAsString('[]');
      debugPrint(
          "📁 [FCM File] Cleared pending updates file after successful sync");
    } else {
      debugPrint(
          "📁 [FCM File] No applicable updates (all jobs already up to date)");
      // Even if no updates, clear old entries to prevent stale data
      // But keep the file structure intact for future writes
      await file.writeAsString('[]');
    }

    return anyUpdated;
  } catch (e, st) {
    debugPrint("⚠️ [FCM File] Failed to apply pending updates: $e\n$st");
    return false;
  }
}

/// 🔄 Load jobs from SharedPreferences when app starts
/// 🚀 First applies file-based FCM updates, then loads from SharedPreferences
Future<void> loadJobsFromPrefs() async {
  try {
    // 📁 FIRST: Apply any pending FCM updates from file
    // This is the most reliable cross-isolate sync mechanism
    final appliedFromFile = await applyPendingFcmUpdatesFromFile();
    if (appliedFromFile) {
      debugPrint("✅ Applied FCM updates from file on startup");
      // Job list was already updated by applyPendingFcmUpdatesFromFile
      final jobs = jobListNotifier.value;
      final completed = jobs.where((j) => j.status == 'completed').length;
      final processing = jobs.where((j) => j.status == 'processing').length;
      debugPrint(
          "📊 Status after FCM file: $completed completed, $processing processing");
      return;
    }

    // 📦 FALLBACK: Load from SharedPreferences
    final prefs = await SharedPreferences.getInstance();

    // 🔄 Multiple reload attempts to ensure cross-isolate sync
    await prefs.reload();
    await Future.delayed(const Duration(milliseconds: 50));
    await prefs.reload();

    // Check for pending FCM updates flag
    final hasUpdate = prefs.getBool('has_fcm_update') ?? false;
    if (hasUpdate) {
      debugPrint("📦 Found pending FCM update flag on app start");
      await prefs.remove('has_fcm_update');
      await prefs.reload();
    }

    final jsonStr = prefs.getString('jobs');
    if (jsonStr == null) {
      jobListNotifier.value = [];
      debugPrint("📂 No jobs found in prefs — cleared list");
      return;
    }

    final decoded = jsonDecode(jsonStr);
    if (decoded is! List) {
      debugPrint("⚠️ Invalid job list format");
      return;
    }

    final list = decoded
        .map((e) => JobModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    jobListNotifier.value = await withoutDeletedJobs(List<JobModel>.from(list));

    // Log status summary
    final completed = list.where((j) => j.status == 'completed').length;
    final processing = list.where((j) => j.status == 'processing').length;
    final failed = list.where((j) => j.status == 'failed').length;
    debugPrint(
        "📂 Loaded ${list.length} jobs: $completed completed, $processing processing, $failed failed");
  } catch (e, st) {
    debugPrint("⚠️ Failed to load jobs from prefs: $e\n$st");
  }
}

/// Initialize app state once on startup
Future<void> initAppState() async {
  await loadJobsFromPrefs();
  await loadAdFreeStatus();

  // ✅ Automatically persist whenever the job list changes
  jobListNotifier.addListener(() async {
    await saveJobsToPrefs();
  });
}

/// Load ad-free status from local storage (for logging only)
/// SECURITY: This does NOT update isAdFreeNotifier - that requires server verification
/// Server-side verification happens via UserService.checkAdFreeStatus()
Future<void> loadAdFreeStatus() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final cachedValue = prefs.getBool('is_ad_free') ?? false;
    // SECURITY: Do NOT set isAdFreeNotifier here - it bypasses verification
    // Just log what's in the cache for debugging
    debugPrint(
        "📦 Cached ad-free status: $cachedValue (awaiting server verification)");
  } catch (e) {
    debugPrint("⚠️ Failed to read ad-free cache: $e");
  }
  // Always start with ads enabled - server will verify if user is ad-free
  resetAdFreeVerification();
}

// ==================== RATE LIMITING ====================
// Protects server from overload by limiting concurrent processing jobs
// Non-VIP: max 5 processing jobs, VIP: max 15 processing jobs

/// Maximum concurrent processing jobs allowed
/// Non-VIP: 5, VIP: 15
int getMaxConcurrentJobs() {
  return isVipUser() ? 15 : 5;
}

/// Server job timeout in minutes (matches backend timeout)
/// Jobs older than this while still "processing" are considered stale
const int _jobTimeoutMinutes = 30;

/// Cooldown period in seconds after a batch submission
/// Prevents rapid-fire submissions that could overwhelm the server
const int _batchCooldownSeconds = 5;

/// Track the last batch submission time for cooldown
DateTime? _lastBatchSubmissionTime;

/// Get count of jobs currently in processing state
/// IMPORTANT: This is used for rate limiting - do not modify to include other states
int getProcessingJobsCount() {
  // Clean up stale jobs first
  _cleanupStaleProcessingJobs();

  final jobs = jobListNotifier.value;
  int count = 0;
  for (final job in jobs) {
    if (job.status == 'processing') {
      count++;
    }
  }
  return count;
}

/// Get the number of available job slots
/// Returns 0 if user has reached their limit
int getAvailableJobSlots() {
  final maxJobs = getMaxConcurrentJobs();
  final currentProcessing = getProcessingJobsCount();
  final available = maxJobs - currentProcessing;
  return available > 0 ? available : 0;
}

/// Check if user can submit a specific number of jobs
/// Returns true if submission is allowed, false otherwise
bool canSubmitJobs(int jobCount) {
  final available = getAvailableJobSlots();
  return available >= jobCount;
}

/// Smart rate limit check for job submission
/// Returns null if allowed, or an error message if blocked
///
/// This function implements intelligent rate limiting:
/// 1. Checks concurrent job limit (5 non-VIP, 15 VIP)
/// 2. Enforces cooldown between batch submissions
/// 3. Handles bulk mode intelligently - blocks entire batch if it would exceed limit
/// 4. Cleans up stale "processing" jobs that timed out
String? checkRateLimitForSubmission(int jobsToSubmit) {
  // 1. Clean up any stale processing jobs first
  _cleanupStaleProcessingJobs();

  final maxJobs = getMaxConcurrentJobs();
  final currentProcessing = getProcessingJobsCount();
  final available = maxJobs - currentProcessing;

  // 2. Check cooldown for batch submissions (> 3 jobs)
  if (jobsToSubmit > 3 && _lastBatchSubmissionTime != null) {
    final elapsed =
        DateTime.now().difference(_lastBatchSubmissionTime!).inSeconds;
    if (elapsed < _batchCooldownSeconds) {
      final remaining = _batchCooldownSeconds - elapsed;
      return 'Please wait $remaining seconds before submitting another batch';
    }
  }

  // 3. Check if submission would exceed limit
  if (jobsToSubmit > available) {
    if (available == 0) {
      // No slots available at all
      final vipHint = isVipUser()
          ? 'You have $currentProcessing jobs processing. Please wait for some to complete.'
          : 'You have $currentProcessing jobs processing. Upgrade to VIP for 15 concurrent jobs!';
      return 'Job limit reached ($currentProcessing/$maxJobs). $vipHint';
    } else {
      // Some slots available but not enough for this batch
      final vipHint =
          isVipUser() ? '' : ' Upgrade to VIP for 15 concurrent jobs!';
      return 'Cannot submit $jobsToSubmit jobs. Only $available slots available ($currentProcessing/$maxJobs processing).$vipHint';
    }
  }

  return null; // Submission allowed
}

/// Record that a batch submission was made (for cooldown tracking)
void recordBatchSubmission(int jobCount) {
  if (jobCount > 3) {
    _lastBatchSubmissionTime = DateTime.now();
    debugPrint(
        "🕐 Batch submission recorded: $jobCount jobs at $_lastBatchSubmissionTime");
  }
}

/// Clean up stale processing jobs
/// Jobs that have been "processing" for longer than the timeout are marked as failed
/// This prevents zombie jobs from blocking the rate limit
void _cleanupStaleProcessingJobs() {
  final jobs = jobListNotifier.value;
  final now = DateTime.now();
  bool hasChanges = false;

  for (final job in jobs) {
    if (job.status == 'processing') {
      final age = now.difference(job.createdAt);
      if (age.inMinutes > _jobTimeoutMinutes) {
        // Job has been processing too long - mark as failed
        job.status = 'failed';
        hasChanges = true;
        debugPrint(
            "⏰ Marked stale job as failed: ${job.jobId} (age: ${age.inMinutes} min)");
      }
    }
  }

  if (hasChanges) {
    // Trigger update
    jobListNotifier.value = List<JobModel>.from(jobs);
    debugPrint("🧹 Cleaned up stale processing jobs");
  }
}

/// Force cleanup of stale jobs (can be called manually)
Future<void> cleanupStaleJobs() async {
  _cleanupStaleProcessingJobs();
  await saveJobsToPrefs();
}

// ----------------------------------------------------
// 🗑️ DELETED JOBS TRACKING
// ----------------------------------------------------
// Prevents FCM notifications from recreating deleted jobs

const String _deletedJobsKey = 'deleted_job_ids';
const int _maxDeletedJobsToTrack = 300; // Limit to prevent bloat

/// Mark a job ID as deleted so FCM won't recreate it
Future<void> markJobAsDeleted(String jobId) async {
  if (jobId.isEmpty) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final deletedList = prefs.getStringList(_deletedJobsKey) ?? [];

    if (!deletedList.contains(jobId)) {
      deletedList.add(jobId);

      // Trim old entries if list gets too long (FIFO)
      while (deletedList.length > _maxDeletedJobsToTrack) {
        deletedList.removeAt(0);
      }

      await prefs.setStringList(_deletedJobsKey, deletedList);
      debugPrint(
          "🗑️ Marked job $jobId as deleted (${deletedList.length} tracked)");
    }
  } catch (e) {
    debugPrint("⚠️ Failed to mark job as deleted: $e");
  }
}

/// Mark multiple job IDs as deleted
Future<void> markJobsAsDeleted(List<String> jobIds) async {
  if (jobIds.isEmpty) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final deletedList = prefs.getStringList(_deletedJobsKey) ?? [];

    for (final jobId in jobIds) {
      if (jobId.isNotEmpty && !deletedList.contains(jobId)) {
        deletedList.add(jobId);
      }
    }

    // Trim old entries if list gets too long (FIFO)
    while (deletedList.length > _maxDeletedJobsToTrack) {
      deletedList.removeAt(0);
    }

    await prefs.setStringList(_deletedJobsKey, deletedList);
    debugPrint(
        "🗑️ Marked ${jobIds.length} jobs as deleted (${deletedList.length} tracked)");
  } catch (e) {
    debugPrint("⚠️ Failed to mark jobs as deleted: $e");
  }
}

/// Check if a job ID was previously deleted
Future<bool> isJobDeleted(String jobId) async {
  if (jobId.isEmpty) return false;

  try {
    final prefs = await SharedPreferences.getInstance();
    final deletedList = prefs.getStringList(_deletedJobsKey) ?? [];
    return deletedList.contains(jobId);
  } catch (e) {
    debugPrint("⚠️ Failed to check deleted job: $e");
    return false;
  }
}

/// Synchronous version for use in background isolate (reads directly from prefs)
List<String> getDeletedJobIdsSync(SharedPreferences prefs) {
  return prefs.getStringList(_deletedJobsKey) ?? [];
}

/// Clear the deleted jobs list (for testing/debugging)
Future<void> clearDeletedJobsList() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deletedJobsKey);
    debugPrint("🧹 Cleared deleted jobs list");
  } catch (e) {
    debugPrint("⚠️ Failed to clear deleted jobs list: $e");
  }
}

/// Get rate limit status for display
/// Returns a map with useful info for UI
Map<String, dynamic> getRateLimitStatus() {
  _cleanupStaleProcessingJobs();

  final maxJobs = getMaxConcurrentJobs();
  final currentProcessing = getProcessingJobsCount();
  final available = maxJobs - currentProcessing;

  return {
    'maxJobs': maxJobs,
    'currentProcessing': currentProcessing,
    'available': available,
    'isVip': isVipUser(),
    'percentUsed':
        maxJobs > 0 ? (currentProcessing / maxJobs * 100).round() : 0,
    'canSubmit': available > 0,
  };
}
