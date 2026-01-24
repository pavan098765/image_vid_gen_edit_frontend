// lib/core/app_state.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import user service for credit notifier, ad-free state, and VIP state
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart'
    show userCreditsNotifier, currentUserNotifier, isLoadingUserNotifier, UserData,
         isAdFreeNotifier, shouldShowAds, notifyAdFreeStatusChanged, resetAdFreeVerification,
         VipStatus, vipStatusNotifier, isVipUser, getMaxVariations, canUseBulkEdit, 
         isUpscaleFree, notifyVipStatusChanged, resetVipVerification;

// Re-export for other files that import app_state.dart
export 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart'
    show userCreditsNotifier, currentUserNotifier, isLoadingUserNotifier, UserData,
         isAdFreeNotifier, shouldShowAds, notifyAdFreeStatusChanged, resetAdFreeVerification,
         VipStatus, vipStatusNotifier, isVipUser, getMaxVariations, canUseBulkEdit,
         isUpscaleFree, notifyVipStatusChanged, resetVipVerification;

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
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

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
      
      debugPrint("⚙️ Settings loaded: theme=${themeModeNotifier.value}, highQuality=$highQualityPreviews");
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
class AppTabs {
  static const int editor = 0;
  static const int video = 1;
  static const int aiTools = 2;
  static const int credits = 3;
  static const int settings = 4;
}

/// Represents a single variation result from the backend
class VariationResult {
  final int variationIndex;
  final String status; // 'queued', 'running', 'completed', 'failed'
  final String? resultUrl;
  final String? error;
  String? localFilePath; // Local file path for saved variation

  VariationResult({
    required this.variationIndex,
    required this.status,
    this.resultUrl,
    this.error,
    this.localFilePath,
  });

  Map<String, dynamic> toJson() => {
    'variationIndex': variationIndex,
    'status': status,
    'resultUrl': resultUrl,
    'error': error,
    'localFilePath': localFilePath,
  };

  factory VariationResult.fromJson(Map<String, dynamic> json) {
    return VariationResult(
      variationIndex: json['variationIndex'] ?? json['variation_index'] ?? 0,
      status: json['status'] ?? 'queued',
      resultUrl: json['resultUrl'] ?? json['result_url'],
      error: json['error'],
      localFilePath: json['localFilePath'],
    );
  }

  bool get isCompleted => status == 'completed' && resultUrl != null;
  bool get isFailed => status == 'failed';
  bool get isSavedLocally => localFilePath != null && File(localFilePath!).existsSync();
}

/// Represents an AI job (image/video generation, etc.)
class JobModel {
  final String jobId;
  final String title;
  final String model;
  final String outputType;
  String? downloadUrl;
  String status; // 'pending', 'processing', 'completed', 'failed'
  DateTime createdAt;
  String? localFilePath; // store preview/download file path
  String? inputImagePath;
  
  // NEW: Variation support
  int variations; // Number of variations requested (1-4)
  List<VariationResult>? variationResults; // Individual variation results
  bool allCompleted; // True when all variations finished
  
  // NEW: Enhanced prompt support
  String? enhancedPrompt; // The AI-enhanced prompt (if enhancement was enabled)
  bool promptEnhanced; // Whether prompt was enhanced by AI
  String? originalPrompt; // Original user prompt (for comparison)

  /// Cloud results expire after 24 hours
  static const int cloudExpiryHours = 24;

  JobModel({
    required this.jobId,
    required this.title,
    required this.model,
    required this.outputType,
    this.downloadUrl,
    this.status = 'processing',
    DateTime? createdAt,
    this.localFilePath,
    this.inputImagePath,
    this.variations = 1,
    this.variationResults,
    this.allCompleted = false,
    this.enhancedPrompt,
    this.promptEnhanced = false,
    this.originalPrompt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Check if the cloud result has expired (>24 hours old)
  bool get isCloudExpired {
    final age = DateTime.now().difference(createdAt);
    return age.inHours >= cloudExpiryHours;
  }

  /// Check if the result is saved locally (safe from cloud expiry)
  bool get isSavedLocally {
    if (localFilePath == null || localFilePath!.isEmpty) return false;
    return File(localFilePath!).existsSync();
  }

  /// Get remaining time before cloud expiry
  Duration get timeUntilExpiry {
    final expiryTime = createdAt.add(const Duration(hours: cloudExpiryHours));
    final remaining = expiryTime.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Format remaining time as human-readable string
  String get expiryTimeFormatted {
    final remaining = timeUntilExpiry;
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes % 60}m';
    } else if (remaining.inMinutes > 0) {
      return '${remaining.inMinutes}m';
    } else {
      return 'Expired';
    }
  }

  // --- JSON serialization helpers for SharedPreferences persistence ---
  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'title': title,
        'model': model,
        'outputType': outputType,
        'downloadUrl': downloadUrl,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'localFilePath': localFilePath,
        'inputImagePath': inputImagePath,
        'variations': variations,
        'variationResults': variationResults?.map((v) => v.toJson()).toList(),
        'allCompleted': allCompleted,
        'enhancedPrompt': enhancedPrompt,
        'promptEnhanced': promptEnhanced,
        'originalPrompt': originalPrompt,
      };

  factory JobModel.fromJson(Map<String, dynamic> json) {
    String rawStatus =
        (json['status'] ?? 'processing').toString().toLowerCase();
    // Only allow 3 states
    const allowed = ['processing', 'completed', 'failed'];
    if (!allowed.contains(rawStatus)) rawStatus = 'processing';
    
    // Parse variation results if present
    List<VariationResult>? variationResults;
    if (json['variationResults'] != null || json['variation_results'] != null) {
      final resultsList = json['variationResults'] ?? json['variation_results'];
      if (resultsList is List) {
        variationResults = resultsList
            .map((v) => VariationResult.fromJson(Map<String, dynamic>.from(v)))
            .toList();
      }
    }

    return JobModel(
      jobId: json['jobId'] ?? json['job_id'],
      title: json['title'] ?? 'Untitled',
      model: json['model'] ?? 'unknown',
      outputType: json['outputType'] ?? json['output_type'] ?? 'image',
      downloadUrl: json['downloadUrl'] ?? json['download_url'],
      status: rawStatus,
      createdAt: DateTime.tryParse(json['createdAt'] ?? json['created_at'] ?? '') ?? DateTime.now(),
      localFilePath: json['localFilePath'],
      inputImagePath: json['inputImagePath'] as String?,
      variations: json['variations'] ?? 1,
      variationResults: variationResults,
      allCompleted: json['allCompleted'] ?? json['all_completed'] ?? false,
      enhancedPrompt: json['enhancedPrompt'] ?? json['enhanced_prompt'],
      promptEnhanced: json['promptEnhanced'] ?? json['prompt_enhanced'] ?? false,
      originalPrompt: json['originalPrompt'] ?? json['original_prompt'],
    );
  }
  
  /// Get the count of successful variations
  int get successfulVariationsCount {
    if (variationResults == null || variationResults!.isEmpty) {
      return status == 'completed' ? 1 : 0;
    }
    return variationResults!.where((v) => v.isCompleted).length;
  }
  
  /// Get the count of failed variations
  int get failedVariationsCount {
    if (variationResults == null || variationResults!.isEmpty) {
      return status == 'failed' ? 1 : 0;
    }
    return variationResults!.where((v) => v.isFailed).length;
  }
  
  /// Check if this job has multiple variations
  bool get hasMultipleVariations => variations > 1;
  
  /// Get all successful variation URLs
  List<String> get allSuccessfulUrls {
    if (variationResults == null || variationResults!.isEmpty) {
      return downloadUrl != null ? [downloadUrl!] : [];
    }
    return variationResults!
        .where((v) => v.isCompleted && v.resultUrl != null)
        .map((v) => v.resultUrl!)
        .toList();
  }
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

/// Add a new job or update existing by jobId. Persists immediately.
Future<void> addOrUpdateJob(JobModel job) async {
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
  // NEW: Variation and prompt enhancement fields
  int? variations,
  List<VariationResult>? variationResults,
  bool? allCompleted,
  String? enhancedPrompt,
  bool? promptEnhanced,
  String? originalPrompt,
}) async {
  final list = List<JobModel>.from(jobListNotifier.value);
  final idx = list.indexWhere((j) => j.jobId == jobId);

  if (idx >= 0) {
    final old = list[idx];
    
    // 🛡️ NEVER downgrade terminal status (completed/failed → processing)
    String finalStatus = status ?? old.status;
    if ((old.status == 'completed' || old.status == 'failed') && 
        status != null && status == 'processing') {
      debugPrint("🛡️ updateJobFields: Blocking status downgrade for job $jobId: ${old.status} → $status");
      finalStatus = old.status;
    }

    list[idx] = JobModel(
      jobId: old.jobId,
      title: title ?? old.title,
      model: model ?? old.model,
      outputType: outputType ?? old.outputType,
      downloadUrl: (downloadUrl != null && downloadUrl.isNotEmpty)
          ? downloadUrl
          : old.downloadUrl,
      status: finalStatus,
      createdAt: old.createdAt,

      // ✅ Preserve paths by default
      localFilePath: localFilePath ?? old.localFilePath,
      inputImagePath: inputImagePath ?? old.inputImagePath,
      
      // ✅ Variation fields
      variations: variations ?? old.variations,
      variationResults: variationResults ?? old.variationResults,
      allCompleted: allCompleted ?? old.allCompleted,
      
      // ✅ Prompt enhancement fields
      enhancedPrompt: enhancedPrompt ?? old.enhancedPrompt,
      promptEnhanced: promptEnhanced ?? old.promptEnhanced,
      originalPrompt: originalPrompt ?? old.originalPrompt,
    );

    if (status != null) {
      const allowed = ['processing', 'completed', 'failed'];
      if (!allowed.contains(status.toLowerCase())) {
        status = 'processing';
      }
    }
  } else {
    // New fallback record
    list.insert(
      0,
      JobModel(
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
        variations: variations ?? 1,
        variationResults: variationResults,
        allCompleted: allCompleted ?? false,
        enhancedPrompt: enhancedPrompt,
        promptEnhanced: promptEnhanced ?? false,
        originalPrompt: originalPrompt,
      ),
    );
  }

  jobListNotifier.value = list;
  await saveJobsToPrefs();
}

/// 🔄 Load jobs from SharedPreferences when app starts
Future<void> loadJobsFromPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
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

    // 🧠 Always assign a new list object to trigger UI rebuild
    jobListNotifier.value = List<JobModel>.from(list);

    debugPrint("📂 Reloaded ${list.length} jobs from prefs");
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
    debugPrint("📦 Cached ad-free status: $cachedValue (awaiting server verification)");
  } catch (e) {
    debugPrint("⚠️ Failed to read ad-free cache: $e");
  }
  // Always start with ads enabled - server will verify if user is ad-free
  resetAdFreeVerification();
}

// ==================== RATE LIMITING ====================
// Protects server from overload by limiting concurrent processing jobs
// Non-VIP: max 5 processing jobs, VIP: max 25 processing jobs

/// Maximum concurrent processing jobs allowed
/// Non-VIP: 5, VIP: 25
int getMaxConcurrentJobs() {
  return isVipUser() ? 25 : 5;
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
/// 1. Checks concurrent job limit (5 non-VIP, 25 VIP)
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
    final elapsed = DateTime.now().difference(_lastBatchSubmissionTime!).inSeconds;
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
          : 'You have $currentProcessing jobs processing. Upgrade to VIP for 25 concurrent jobs!';
      return 'Job limit reached ($currentProcessing/$maxJobs). $vipHint';
    } else {
      // Some slots available but not enough for this batch
      final vipHint = isVipUser() 
          ? '' 
          : ' Upgrade to VIP for 25 concurrent jobs!';
      return 'Cannot submit $jobsToSubmit jobs. Only $available slots available ($currentProcessing/$maxJobs processing).$vipHint';
    }
  }
  
  return null; // Submission allowed
}

/// Record that a batch submission was made (for cooldown tracking)
void recordBatchSubmission(int jobCount) {
  if (jobCount > 3) {
    _lastBatchSubmissionTime = DateTime.now();
    debugPrint("🕐 Batch submission recorded: $jobCount jobs at ${_lastBatchSubmissionTime}");
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
        debugPrint("⏰ Marked stale job as failed: ${job.jobId} (age: ${age.inMinutes} min)");
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
      debugPrint("🗑️ Marked job $jobId as deleted (${deletedList.length} tracked)");
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
    debugPrint("🗑️ Marked ${jobIds.length} jobs as deleted (${deletedList.length} tracked)");
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
    'percentUsed': maxJobs > 0 ? (currentProcessing / maxJobs * 100).round() : 0,
    'canSubmit': available > 0,
  };
}
