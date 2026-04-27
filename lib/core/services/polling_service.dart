// lib/core/services/polling_service.dart
//
// 🔄 BACKUP MECHANISM for job status updates
// 
// PRIMARY: FCM notifications deliver status and download_url in real-time.
// The app trusts FCM data stored in SharedPreferences.
//
// BACKUP: This PollingService is only used when:
// 1. FCM failed to deliver (rare)
// 2. Jobs are stuck in "processing" for > 2 minutes
// 3. Manual refresh requested by user
//
// The goal is to minimize server API calls - FCM should handle 99% of updates.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/main.dart' show navigatorKey;

/// 🔄 Backup service for job status polling (FCM is primary)
class PollingService {
  PollingService._();
  static final PollingService instance = PollingService._();
  static final allowed = ["processing", "completed", "failed"];
  static const int minPollIntervalSec = 20; // per-job cooldown (for background polling only)
  static const int maxJobAgeMinutesForBackgroundPoll = 60; // background poll skips very old jobs

  Timer? _timer;
  bool _running = false;
  bool _isTicking = false;

  // Public stream the UI can listen to. Emits a map with keys:
  // { "job_id": String, "status": String, "download_url": String? , "raw": Map }
  final StreamController<Map<String, dynamic>> _onStatus =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get onStatus => _onStatus.stream;

  // API config
  static const String baseUrl = "https://genedit.mooo.com";
  final int pollIntervalSec = 10;
  final AuthService _authService = AuthService();

  /// 🔍 Check if URL is the old download endpoint (should not be used)
  static bool _isOldDownloadEndpoint(String? url) {
    if (url == null || url.isEmpty) return false;
    return url.contains('/download/') && !url.contains('workers.dev');
  }

  /// 🔍 Check if a signed URL is still valid (not expired)
  /// Returns true if URL has at least [minRemainingSeconds] before expiration
  static bool isSignedUrlValid(String? url, {int minRemainingSeconds = 300}) {
    if (url == null || url.isEmpty) return false;
    if (_isOldDownloadEndpoint(url)) return false;
    
    try {
      final uri = Uri.parse(url);
      final expStr = uri.queryParameters['exp'];
      if (expStr == null) return false;
      
      final expTimestamp = int.tryParse(expStr);
      if (expTimestamp == null) return false;
      
      final nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final remainingSeconds = expTimestamp - nowTimestamp;
      
      // URL is valid if it has at least minRemainingSeconds left
      return remainingSeconds > minRemainingSeconds;
    } catch (e) {
      debugPrint("⚠️ Error parsing URL expiration: $e");
      return false;
    }
  }

  /// 🔐 Get valid signed R2 download URL for a completed job
  /// Uses cached URL if still valid, otherwise fetches a new one
  static Future<String?> getSignedDownloadUrl(String jobId, {bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = "pending_download_url_$jobId";
    
    // Check cached URL first (unless force refresh)
    if (!forceRefresh) {
      final cachedUrl = prefs.getString(cacheKey);
      if (isSignedUrlValid(cachedUrl, minRemainingSeconds: 300)) {
        debugPrint("✅ Using cached signed URL for $jobId (still valid)");
        return cachedUrl;
      }
    }
    
    // Fetch new signed URL
    try {
      final url = "$baseUrl/download_url/$jobId";
      
      // Firebase Auth
      final authService = AuthService();
      final token = await authService.getIdToken();
      if (token == null) {
        debugPrint("⚠️ Not authenticated for download URL refresh");
        return null;
      }
      
      final headers = {
        "Authorization": "Bearer $token",
      };
      
      final resp = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
      
      if (resp.statusCode == 200) {
        // The endpoint returns the signed URL directly as a string
        final signedUrl = resp.body.trim();
        // Remove quotes if the response is JSON-encoded string
        final cleanUrl = signedUrl.startsWith('"') && signedUrl.endsWith('"')
            ? signedUrl.substring(1, signedUrl.length - 1)
            : signedUrl;
        
        // Cache the new URL
        await prefs.setString(cacheKey, cleanUrl);
        debugPrint("✅ Fetched & cached new signed URL for $jobId");
        return cleanUrl;
      } else {
        debugPrint("⚠️ Failed to get signed URL: ${resp.statusCode} - ${resp.body}");
        
        // Return cached URL as fallback even if expired (let download fail gracefully)
        final cachedUrl = prefs.getString(cacheKey);
        if (cachedUrl != null && !_isOldDownloadEndpoint(cachedUrl)) {
          return cachedUrl;
        }
        return null;
      }
    } catch (e) {
      debugPrint("❌ Error fetching signed download URL: $e");
      
      // Return cached URL as fallback
      final cachedUrl = prefs.getString(cacheKey);
      if (cachedUrl != null && !_isOldDownloadEndpoint(cachedUrl)) {
        return cachedUrl;
      }
      return null;
    }
  }
  
  /// 🔐 Get valid download URL for a job - smart version
  /// Checks cache first, only fetches if expired/missing
  static Future<String?> getValidDownloadUrl(String jobId) async {
    return getSignedDownloadUrl(jobId, forceRefresh: false);
  }
  
  /// 🔐 Force refresh the download URL for a job
  static Future<String?> refreshDownloadUrl(String jobId) async {
    return getSignedDownloadUrl(jobId, forceRefresh: true);
  }

  void start() {
    if (_running) return;
    _running = true;
    _timer?.cancel();

    // Immediate tick so UI that submitted a job sees faster updates
    _tick();

    // periodic background ticks
    _timer = Timer.periodic(Duration(seconds: pollIntervalSec), (_) => _tick());
    debugPrint("PollingService started");
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    debugPrint("PollingService stopped");
  }

  Future<void> _tick() async {
    if (_isTicking) return;
    _isTicking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jobId = prefs.getString("active_job_id");
      if (jobId == null || jobId.isEmpty) return;

      final notifyRequested = prefs.getBool("notify_requested") ?? false;

      // --- 1️⃣ Firebase Auth and call job_status
      final token = await _authService.getIdToken();
      if (token == null) {
        debugPrint("⚠️ Not authenticated for job status check");
        return;
      }
      
      final headers = {
        "Authorization": "Bearer $token",
      };
      final url = "$baseUrl/job_status?job_id=$jobId";

      final resp = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      String status = (data["status"] ?? "").toString().toLowerCase();
      if (!allowed.contains(status)) {
        status = "processing";
      }
      
      // 🔐 For completed jobs, get valid signed URL (uses cache if valid)
      String? downloadUrl;
      if (status == "completed") {
        downloadUrl = await getValidDownloadUrl(jobId);
      }
      
      // 📦 Parse variation results if present
      List<VariationResult>? variationResults;
      if (data['variation_results'] != null) {
        final resultsList = data['variation_results'] as List;
        variationResults = resultsList
            .map((v) => VariationResult.fromJson(Map<String, dynamic>.from(v)))
            .toList();
      }
      
      // ✨ Parse enhanced prompt fields
      // Note: Don't overwrite variations - each job in a batch is a single variation
      final bool allCompleted = data['all_completed'] ?? (status == 'completed' || status == 'failed');
      final String? enhancedPrompt = data['enhanced_prompt'];
      final bool promptEnhanced = data['prompt_enhanced'] ?? false;
      final int? estimatedWaitSeconds = (data['estimated_wait_seconds'] is num)
          ? (data['estimated_wait_seconds'] as num).toInt()
          : null;
      final int? queuePosition = (data['queue_position'] is num)
          ? (data['queue_position'] as num).toInt()
          : null;

      // --- 2️⃣ Emit event to UI

      // ✅ Update jobListNotifier immediately (for in-app processing jobs)
      final jobs = List<JobModel>.from(jobListNotifier.value);
      final idx = jobs.indexWhere((j) => j.jobId == jobId);
      if (idx != -1) {
        final old = jobs[idx];
        
        // 🛡️ NEVER downgrade terminal status (completed/failed → processing)
        String finalStatus = status;
        if ((old.status == 'completed' || old.status == 'failed') && status == 'processing') {
          debugPrint("🛡️ FCM: Blocking status downgrade for job $jobId: ${old.status} → $status");
          finalStatus = old.status;
        }
        
        jobs[idx] = JobModel(
          jobId: old.jobId,
          title: old.title,
          model: old.model,
          outputType: old.outputType,
          downloadUrl: (downloadUrl != null && downloadUrl.isNotEmpty)
              ? downloadUrl
              : old.downloadUrl,
          status: finalStatus.isNotEmpty ? finalStatus : old.status,
          createdAt: old.createdAt,
          inputImagePath: old.inputImagePath,
          localFilePath: old.localFilePath,
          estimatedWaitSeconds: estimatedWaitSeconds ?? old.estimatedWaitSeconds,
          queuePosition: queuePosition ?? old.queuePosition,
          // Keep original variations (each job is a single variation in the batch)
          variations: old.variations,
          variationResults: variationResults ?? old.variationResults,
          allCompleted: allCompleted,
          enhancedPrompt: enhancedPrompt ?? old.enhancedPrompt,
          promptEnhanced: promptEnhanced || old.promptEnhanced,
          originalPrompt: old.originalPrompt,
        );
        jobListNotifier.value = jobs;
      }

      // Persist ETA / queue info to prefs (best-effort)
      unawaited(updateJobFields(
        jobId: jobId,
        status: status,
        downloadUrl: downloadUrl,
        estimatedWaitSeconds: estimatedWaitSeconds,
        queuePosition: queuePosition,
        variationResults: variationResults,
        allCompleted: allCompleted,
        enhancedPrompt: enhancedPrompt,
        promptEnhanced: promptEnhanced,
      ));

      if (!_onStatus.isClosed) {
        _onStatus.add({
          "job_id": jobId,
          "status": status,
          "download_url": downloadUrl,
          "estimated_wait_seconds": estimatedWaitSeconds,
          "queue_position": queuePosition,
          "raw": data,
        });
      }

      // --- 3️⃣ Handle status
      if (status == "completed") {
        if (downloadUrl == null || downloadUrl.isEmpty) return;
        debugPrint("PollingService: job completed, prefetching result...");

        // 🔥 Auto-generate preview & save path to job
        try {
          final jobs = List<JobModel>.from(jobListNotifier.value);
          final idx = jobs.indexWhere((j) => j.jobId == jobId);

          if (idx != -1) {
            final job = jobs[idx];

            // ✅ Preserve inputImagePath before starting preview fetch
            final inputThumb = job.inputImagePath;

            // If preview not already stored, fetch it
            if (job.localFilePath == null ||
                !(File(job.localFilePath!).existsSync())) {
              final tempPath = await FileService.previewFileAndReturnPath(
                navigatorKey.currentContext!, // ✅ safe global context
                downloadUrl,
                uniqueKey: jobId,
              );

              if (tempPath != null) {
                job.localFilePath = tempPath;
              }

              // ✅ Reinsert with preserved fields
              final updatedJob = JobModel(
                jobId: job.jobId,
                title: job.title,
                model: job.model,
                outputType: job.outputType,
                downloadUrl: job.downloadUrl ?? downloadUrl,
                status: job.status,
                createdAt: job.createdAt,
                inputImagePath: inputThumb, // 🟣 ensure preserved
                localFilePath: job.localFilePath,
                // NEW: Preserve variation and prompt fields
                variations: job.variations,
                variationResults: job.variationResults,
                allCompleted: job.allCompleted,
                enhancedPrompt: job.enhancedPrompt,
                promptEnhanced: job.promptEnhanced,
                originalPrompt: job.originalPrompt,
              );
              await addOrUpdateJob(updatedJob);

              // 🔔 force UI rebuild
              jobListNotifier.value = List.from(jobListNotifier.value);

              debugPrint("✅ Preview auto-downloaded for $jobId");
            }
          }
        } catch (err) {
          debugPrint("⚠️ Auto-preview failed for $jobId: $err");
        }

        try {
          final res = await http.get(Uri.parse(downloadUrl));
          if (res.statusCode == 200) {
            final encoded = base64Encode(res.bodyBytes);
            await prefs.setString("cached_result_bytes", encoded);
            debugPrint("PollingService: result cached locally");

            if (notifyRequested) {
              await NotificationService.showNotification(
                title: "Processing Complete",
                body: "Tap to view your result",
                payload: jobId,
              );
            }

            // Cleanup after success
            await prefs.remove("active_job_id");
            await prefs.remove("notify_requested");
            await prefs.setString("job_last_status", "completed");
          }
        } catch (err) {
          debugPrint("PollingService: prefetch failed $err");
        }
      } else if (status == "failed") {
        if (notifyRequested) {
          await NotificationService.showNotification(
            title: "Processing Failed",
            body: "Your job failed. Tap to retry.",
            payload: jobId,
          );
        }
        await prefs.remove("active_job_id");
        await prefs.remove("notify_requested");
        await prefs.setString("job_last_status", "failed");
      }
    } catch (e, st) {
      debugPrint("PollingService tick error: $e\n$st");
    } finally {
      _isTicking = false;
    }
  }

  /// ✅ Force-refresh all jobs currently in jobListNotifier
  /// 🚀 Uses PARALLEL API calls for faster updates
  Future<void> refreshNow() async {
    debugPrint("🟢 PollingService.refreshNow(): Refreshing all known jobs");

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // Ensure we have latest data from disk

      // get the entire job list from prefs
      final jsonStr = prefs.getString('jobs');
      if (jsonStr == null) {
        debugPrint("ℹ️ No saved jobs to refresh");
        return;
      }

      final list = (jsonDecode(jsonStr) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // Get Firebase token once for all jobs
      final token = await _authService.getIdToken();
      if (token == null) {
        debugPrint("⚠️ Not authenticated for job refresh");
        return;
      }
      
      final headers = {"Authorization": "Bearer $token"};
      final jobIds = list
          .map((job) => job["jobId"] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toList();

      if (jobIds.isEmpty) {
        debugPrint("ℹ️ No jobs to refresh");
        return;
      }

      debugPrint("🌐 Fetching ${jobIds.length} jobs IN PARALLEL...");

      // 🚀 PARALLEL API CALLS - fetch all job statuses concurrently
      final statusFutures = jobIds.map((jobId) async {
        try {
          final url = "$baseUrl/job_status?job_id=$jobId";
          final resp = await http
              .get(Uri.parse(url), headers: headers)
              .timeout(const Duration(seconds: 15));
          
          if (resp.statusCode == 200) {
            return (jobId, jsonDecode(resp.body) as Map<String, dynamic>, true);
          }
          return (jobId, <String, dynamic>{}, false);
        } catch (e) {
          debugPrint("⚠️ Failed to fetch status for $jobId: $e");
          return (jobId, <String, dynamic>{}, false);
        }
      }).toList();

      final statusResults = await Future.wait(statusFutures);
      debugPrint("📦 Received ${statusResults.length} job status responses");

      // Process results and track completed jobs
      var jobs = List<JobModel>.from(jobListNotifier.value);
      final completedJobIds = <String>[];

      for (final (jobId, data, success) in statusResults) {
        if (!success) continue;

        String status = (data["status"] ?? "").toString().toLowerCase();
        const allowedStatuses = ["processing", "completed", "failed"];
        if (!allowedStatuses.contains(status)) {
          status = "processing";
        }
        
        if (status == "completed") {
          completedJobIds.add(jobId);
        }

        // 📦 Parse variation results if present
        List<VariationResult>? variationResults;
        if (data['variation_results'] != null) {
          final resultsList = data['variation_results'] as List;
          variationResults = resultsList
              .map((v) => VariationResult.fromJson(Map<String, dynamic>.from(v)))
              .toList();
        }
        
        final bool allCompleted = data['all_completed'] ?? (status == 'completed' || status == 'failed');
        final String? enhancedPrompt = data['enhanced_prompt'];
        final bool promptEnhanced = data['prompt_enhanced'] ?? false;
        final int? estimatedWaitSeconds = (data['estimated_wait_seconds'] is num)
            ? (data['estimated_wait_seconds'] as num).toInt()
            : null;
        final int? queuePosition = (data['queue_position'] is num)
            ? (data['queue_position'] as num).toInt()
            : null;

        final idx = jobs.indexWhere((j) => j.jobId == jobId);
        if (idx != -1) {
          final old = jobs[idx];
          
          // 🛡️ NEVER downgrade terminal status
          String finalStatus = status;
          if ((old.status == 'completed' || old.status == 'failed') && status == 'processing') {
            debugPrint("🛡️ refreshNow: Blocking status downgrade for $jobId: ${old.status} → $status");
            finalStatus = old.status;
          }

          jobs[idx] = JobModel(
            jobId: old.jobId,
            title: old.title,
            model: old.model,
            outputType: old.outputType,
            downloadUrl: old.downloadUrl, // Will update below for completed jobs
            status: finalStatus.isNotEmpty ? finalStatus : old.status,
            createdAt: old.createdAt,
            inputImagePath: old.inputImagePath,
            localFilePath: old.localFilePath,
            estimatedWaitSeconds: estimatedWaitSeconds ?? old.estimatedWaitSeconds,
            queuePosition: queuePosition ?? old.queuePosition,
            variations: old.variations,
            variationResults: variationResults ?? old.variationResults,
            allCompleted: allCompleted,
            enhancedPrompt: enhancedPrompt ?? old.enhancedPrompt,
            promptEnhanced: promptEnhanced || old.promptEnhanced,
            originalPrompt: old.originalPrompt,
          );

          debugPrint("✅ Job $jobId → $finalStatus");
        }
      }

      // Update UI with status changes
      jobListNotifier.value = List<JobModel>.from(jobs);

      // 🚀 Fetch download URLs for completed jobs IN PARALLEL
      if (completedJobIds.isNotEmpty) {
        debugPrint("🔐 Fetching URLs for ${completedJobIds.length} completed jobs IN PARALLEL...");
        
        final urlFutures = completedJobIds.map((jobId) async {
          try {
            final url = await getValidDownloadUrl(jobId);
            return (jobId, url);
          } catch (e) {
            debugPrint("⚠️ Failed to get URL for $jobId: $e");
            return (jobId, null);
          }
        }).toList();

        final urlResults = await Future.wait(urlFutures);

        jobs = List<JobModel>.from(jobListNotifier.value);
        for (final (jobId, downloadUrl) in urlResults) {
          if (downloadUrl != null && downloadUrl.isNotEmpty) {
            final idx = jobs.indexWhere((j) => j.jobId == jobId);
            if (idx != -1) {
              final old = jobs[idx];
              jobs[idx] = JobModel(
                jobId: old.jobId,
                title: old.title,
                model: old.model,
                outputType: old.outputType,
                downloadUrl: downloadUrl,
                status: old.status,
                createdAt: old.createdAt,
                inputImagePath: old.inputImagePath,
                localFilePath: old.localFilePath,
                estimatedWaitSeconds: old.estimatedWaitSeconds,
                queuePosition: old.queuePosition,
                variations: old.variations,
                variationResults: old.variationResults,
                allCompleted: old.allCompleted,
                enhancedPrompt: old.enhancedPrompt,
                promptEnhanced: old.promptEnhanced,
                originalPrompt: old.originalPrompt,
              );
              debugPrint("✅ Got download URL for $jobId");
            }
          }
        }
        
        jobListNotifier.value = List<JobModel>.from(jobs);
      }

      await saveJobsToPrefs();
      debugPrint("✅ refreshNow() completed (parallel fetch)");
    } catch (e, st) {
      debugPrint("⚠️ PollingService.refreshNow() failed: $e\n$st");
    }
  }

  /// ✅ Refresh only jobs still marked as "processing"
  /// [forceRefresh] - if true, bypasses age limit and throttling (for manual refresh)
  /// 🚀 Uses PARALLEL API calls for faster updates
  Future<void> refreshProcessingJobs({bool forceRefresh = false}) async {
    debugPrint(
        "🟢 PollingService.refreshProcessingJobs(force=$forceRefresh): Refreshing active jobs");
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // Ensure we have latest data from disk (FCM updates)
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;

      final jsonStr = prefs.getString('jobs');
      if (jsonStr == null) {
        debugPrint("ℹ️ No jobs found to refresh");
        return;
      }

      final list = (jsonDecode(jsonStr) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // 🧩 Only refresh 'processing' jobs (apply age filter only for background polling)
      final processingJobs = list.where((job) {
        final status = (job["status"] ?? "").toString().toLowerCase();
        if (status != "processing") return false;

        // Skip age check for manual/force refresh
        if (forceRefresh) return true;

        final createdAt =
            DateTime.tryParse(job["createdAt"] ?? "") ?? DateTime.now();
        final ageMin = now.difference(createdAt).inMinutes;
        if (ageMin > maxJobAgeMinutesForBackgroundPoll) {
          debugPrint("⏩ Skipping old job ${job["jobId"]} ($ageMin min old)");
          return false;
        }
        return true;
      }).toList();

      if (processingJobs.isEmpty) {
        debugPrint("✅ No processing jobs found — nothing to refresh");
        return;
      }

      // Get Firebase token once for all jobs
      final token = await _authService.getIdToken();
      if (token == null) {
        debugPrint("⚠️ Not authenticated for background polling");
        return;
      }

      final headers = {"Authorization": "Bearer $token"};

      // 🚀 Collect job IDs to fetch (apply throttling filter)
      final jobsToFetch = <String>[];
      for (final job in processingJobs) {
        final jobId = job["jobId"] as String?;
        if (jobId == null) continue;

        // 🧠 Per-job throttle (skip for force refresh)
        if (!forceRefresh) {
          final lastPollKey = "last_poll_$jobId";
          final lastPollMs = prefs.getInt(lastPollKey) ?? 0;
          if (nowMs - lastPollMs < minPollIntervalSec * 1000) {
            debugPrint("⏩ Skipping $jobId (polled recently)");
            continue;
          }
          await prefs.setInt(lastPollKey, nowMs);
        }
        jobsToFetch.add(jobId);
      }

      if (jobsToFetch.isEmpty) {
        debugPrint("✅ All jobs were recently polled — skipping");
        return;
      }

      debugPrint("🌐 Fetching ${jobsToFetch.length} jobs IN PARALLEL...");

      // 🚀 PARALLEL API CALLS - fetch all job statuses concurrently
      final statusFutures = jobsToFetch.map((jobId) async {
        try {
          final url = "$baseUrl/job_status?job_id=$jobId";
          final resp = await http
              .get(Uri.parse(url), headers: headers)
              .timeout(const Duration(seconds: 15));
          
          if (resp.statusCode == 200) {
            return (jobId, jsonDecode(resp.body) as Map<String, dynamic>, true);
          }
          return (jobId, <String, dynamic>{}, false);
        } catch (e) {
          debugPrint("⚠️ Failed to fetch status for $jobId: $e");
          return (jobId, <String, dynamic>{}, false);
        }
      }).toList();

      final statusResults = await Future.wait(statusFutures);
      debugPrint("📦 Received ${statusResults.length} job status responses");

      // Process results and track completed jobs for URL fetching
      var jobs = List<JobModel>.from(jobListNotifier.value);
      final completedJobIds = <String>[];

      for (final (jobId, data, success) in statusResults) {
        if (!success) continue;
        
        String status = (data["status"] ?? "").toString().toLowerCase();
        const allowedStatuses = ["processing", "completed", "failed"];
        if (!allowedStatuses.contains(status)) {
          status = "processing";
        }
        
        if (status == "completed") {
          completedJobIds.add(jobId);
        }

        final idx = jobs.indexWhere((j) => j.jobId == jobId);
        if (idx != -1) {
          final old = jobs[idx];

          // 🟣 Preserve blurred input image if available
          String? preservedInputPath = old.inputImagePath;
          if (preservedInputPath == null || preservedInputPath.isEmpty) {
            final jobListJson = prefs.getString('jobs');
            if (jobListJson != null) {
              final decoded = jsonDecode(jobListJson) as List;
              final found = decoded.firstWhere(
                (e) => e['jobId'] == jobId,
                orElse: () => {},
              );
              if (found is Map && found['inputImagePath'] != null) {
                preservedInputPath = found['inputImagePath'];
              }
            }
          }

          // 📦 Parse variation results if present
          List<VariationResult>? variationResults;
          if (data['variation_results'] != null) {
            final resultsList = data['variation_results'] as List;
            variationResults = resultsList
                .map((v) => VariationResult.fromJson(Map<String, dynamic>.from(v)))
                .toList();
          }
          
          final bool allCompleted = data['all_completed'] ?? (status == 'completed' || status == 'failed');
          final String? enhancedPrompt = data['enhanced_prompt'];
          final bool promptEnhanced = data['prompt_enhanced'] ?? false;
          final int? estimatedWaitSeconds = (data['estimated_wait_seconds'] is num)
              ? (data['estimated_wait_seconds'] as num).toInt()
              : null;
          final int? queuePosition = (data['queue_position'] is num)
              ? (data['queue_position'] as num).toInt()
              : null;
          
          // 🛡️ NEVER downgrade terminal status
          String finalStatus = status;
          if ((old.status == 'completed' || old.status == 'failed') && status == 'processing') {
            debugPrint("🛡️ Blocking status downgrade for job $jobId: ${old.status} → $status");
            finalStatus = old.status;
          }

          jobs[idx] = JobModel(
            jobId: old.jobId,
            title: old.title,
            model: old.model,
            outputType: old.outputType,
            downloadUrl: old.downloadUrl, // Will update below for completed jobs
            status: finalStatus.isNotEmpty ? finalStatus : old.status,
            createdAt: old.createdAt,
            inputImagePath: preservedInputPath,
            localFilePath: old.localFilePath,
            estimatedWaitSeconds: estimatedWaitSeconds ?? old.estimatedWaitSeconds,
            queuePosition: queuePosition ?? old.queuePosition,
            variations: old.variations,
            variationResults: variationResults ?? old.variationResults,
            allCompleted: allCompleted,
            enhancedPrompt: enhancedPrompt ?? old.enhancedPrompt,
            promptEnhanced: promptEnhanced || old.promptEnhanced,
            originalPrompt: old.originalPrompt,
          );

          debugPrint("✅ Job $jobId → $finalStatus");
        }
      }

      // Update UI immediately with status changes
      jobListNotifier.value = List<JobModel>.from(jobs);

      // 🚀 Fetch download URLs for completed jobs IN PARALLEL
      if (completedJobIds.isNotEmpty) {
        debugPrint("🔐 Fetching download URLs for ${completedJobIds.length} completed jobs IN PARALLEL...");
        
        final urlFutures = completedJobIds.map((jobId) async {
          try {
            final url = await getValidDownloadUrl(jobId);
            return (jobId, url);
          } catch (e) {
            debugPrint("⚠️ Failed to get URL for $jobId: $e");
            return (jobId, null);
          }
        }).toList();

        final urlResults = await Future.wait(urlFutures);

        // Update jobs with download URLs
        jobs = List<JobModel>.from(jobListNotifier.value);
        for (final (jobId, downloadUrl) in urlResults) {
          if (downloadUrl != null && downloadUrl.isNotEmpty) {
            final idx = jobs.indexWhere((j) => j.jobId == jobId);
            if (idx != -1) {
              final old = jobs[idx];
              jobs[idx] = JobModel(
                jobId: old.jobId,
                title: old.title,
                model: old.model,
                outputType: old.outputType,
                downloadUrl: downloadUrl,
                status: old.status,
                createdAt: old.createdAt,
                inputImagePath: old.inputImagePath,
                localFilePath: old.localFilePath,
                estimatedWaitSeconds: old.estimatedWaitSeconds,
                queuePosition: old.queuePosition,
                variations: old.variations,
                variationResults: old.variationResults,
                allCompleted: old.allCompleted,
                enhancedPrompt: old.enhancedPrompt,
                promptEnhanced: old.promptEnhanced,
                originalPrompt: old.originalPrompt,
              );
              debugPrint("✅ Got download URL for $jobId");
            }
          }
        }
        
        jobListNotifier.value = List<JobModel>.from(jobs);
      }

      await saveJobsToPrefs();
      debugPrint("✅ refreshProcessingJobs() completed (parallel fetch)");
    } catch (e, st) {
      debugPrint("⚠️ PollingService.refreshProcessingJobs() failed: $e\n$st");
    }
  }

  /// Optional helper to force a single immediate check (returns last fetched map or null)
  Future<Map<String, dynamic>?> checkNow() async {
    await _tick();
    // we can't directly return the last emitted map from stream without storing,
    // so keep this simple and let callers use the stream.
    return null;
  }

  /// Dispose if needed (rare, app-level singleton so usually not called)
  void dispose() {
    _timer?.cancel();
    _onStatus.close();
  }
}
