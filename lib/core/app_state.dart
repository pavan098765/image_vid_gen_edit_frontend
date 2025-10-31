// lib/core/app_state.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global app-level selected index for the bottom navigation.
final ValueNotifier<int> selectedIndexNotifier = ValueNotifier<int>(0);
final ValueNotifier<int> userCreditsNotifier = ValueNotifier<int>(0);

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

  JobModel({
    required this.jobId,
    required this.title,
    required this.model,
    required this.outputType,
    this.downloadUrl,
    this.status = 'processing',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // --- JSON serialization helpers for SharedPreferences persistence ---
  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'title': title,
        'model': model,
        'outputType': outputType,
        'downloadUrl': downloadUrl,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
      };

  factory JobModel.fromJson(Map<String, dynamic> json) => JobModel(
        jobId: json['jobId'],
        title: json['title'],
        model: json['model'],
        outputType: json['outputType'],
        downloadUrl: json['downloadUrl'],
        status: json['status'],
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );
}

/// Global list of jobs
final jobListNotifier = ValueNotifier<List<JobModel>>([]);

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

/// 🔄 Load jobs from SharedPreferences when app starts
Future<void> loadJobsFromPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('jobs');
    if (jsonStr == null) return;

    final list = (jsonDecode(jsonStr) as List)
        .map((e) => JobModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    jobListNotifier.value = list;
    debugPrint("📂 Loaded ${list.length} jobs from prefs");
  } catch (e) {
    debugPrint("⚠️ Failed to load jobs: $e");
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
