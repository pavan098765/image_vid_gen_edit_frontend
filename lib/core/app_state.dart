// lib/core/app_state.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import user service for credit notifier
export 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart'
    show userCreditsNotifier, currentUserNotifier, isLoadingUserNotifier, UserData;

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
      };

  factory JobModel.fromJson(Map<String, dynamic> json) {
    String rawStatus =
        (json['status'] ?? 'processing').toString().toLowerCase();
    // Only allow 3 states
    const allowed = ['processing', 'completed', 'failed'];
    if (!allowed.contains(rawStatus)) rawStatus = 'processing';

    return JobModel(
      jobId: json['jobId'],
      title: json['title'],
      model: json['model'],
      outputType: json['outputType'],
      downloadUrl: json['downloadUrl'],
      status: rawStatus,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      localFilePath: json['localFilePath'], // ✅ restore saved preview path
      inputImagePath: json['inputImagePath'] as String?,
    );
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
}) async {
  final list = List<JobModel>.from(jobListNotifier.value);
  final idx = list.indexWhere((j) => j.jobId == jobId);

  if (idx >= 0) {
    final old = list[idx];

    list[idx] = JobModel(
      jobId: old.jobId,
      title: title ?? old.title,
      model: model ?? old.model,
      outputType: outputType ?? old.outputType,
      downloadUrl: (downloadUrl != null && downloadUrl.isNotEmpty)
          ? downloadUrl
          : old.downloadUrl,
      status: status ?? old.status,
      createdAt: old.createdAt,

      // ✅ Preserve paths by default
      localFilePath: localFilePath ?? old.localFilePath,
      inputImagePath: inputImagePath ?? old.inputImagePath,
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

  // ✅ Automatically persist whenever the job list changes
  jobListNotifier.addListener(() async {
    await saveJobsToPrefs();
  });
}
