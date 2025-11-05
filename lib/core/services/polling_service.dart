// lib/core/services/polling_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_vid_gen_edit_frontend/core/app_state.dart';
import 'package:image_vid_gen_edit_frontend/core/services/file_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'package:image_vid_gen_edit_frontend/main.dart' show navigatorKey;


class PollingService {
  PollingService._();
  static final PollingService instance = PollingService._();
  static final allowed = ["processing", "completed", "failed"];
  static const int minPollIntervalSec = 20; // per-job cooldown
  static const int maxJobAgeMinutes = 10; // skip very old jobs

  Timer? _timer;
  bool _running = false;
  bool _isTicking = false;

  // Public stream the UI can listen to. Emits a map with keys:
  // { "job_id": String, "status": String, "download_url": String? , "raw": Map }
  final StreamController<Map<String, dynamic>> _onStatus =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get onStatus => _onStatus.stream;

  // Match your controller config here (keep in sync)
  static const String baseUrl = "https://genedit.mooo.com";
  static const String controllerApiKey = "SECRETKEY";
  static const String controllerSharedSecret = "SECRETKEY";
  final int pollIntervalSec = 10;

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

      // --- 1️⃣ Sign and call job_status
      final payloadJson = jsonEncode({"job_id": jobId});
      final sigBytes = Hmac(sha256, utf8.encode(controllerSharedSecret))
          .convert(utf8.encode(payloadJson));
      final sig = "sha256=${sigBytes.toString()}";
      final headers = {
        "Authorization": "Bearer $controllerApiKey",
        "X-Signature": sig,
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
      String? downloadUrl = data["download_url"] as String?;
      if (downloadUrl != null && downloadUrl.isNotEmpty) {
        await prefs.setString("pending_download_url_$jobId", downloadUrl);
      } else {
        downloadUrl = prefs.getString("pending_download_url_$jobId");
      }

      // --- 2️⃣ Emit event to UI

      // ✅ Update jobListNotifier immediately (for in-app processing jobs)
      final jobs = List<JobModel>.from(jobListNotifier.value);
      final idx = jobs.indexWhere((j) => j.jobId == jobId);
      if (idx != -1) {
        final old = jobs[idx];
        jobs[idx] = JobModel(
          jobId: old.jobId,
          title: old.title,
          model: old.model,
          outputType: old.outputType,
          downloadUrl: (downloadUrl != null && downloadUrl.isNotEmpty)
              ? downloadUrl
              : old.downloadUrl,
          status: status.isNotEmpty ? status : old.status,
          createdAt: old.createdAt,
        );
        jobListNotifier.value = jobs;
      }

      if (!_onStatus.isClosed) {
        _onStatus.add({
          "job_id": jobId,
          "status": status,
          "download_url": downloadUrl,
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
                await addOrUpdateJob(job);

                // 🔔 force UI rebuild
                jobListNotifier.value = List.from(jobListNotifier.value);

                debugPrint("✅ Preview auto-downloaded for $jobId");
              }
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
  Future<void> refreshNow() async {
    debugPrint("🟢 PollingService.refreshNow(): Refreshing all known jobs");

    try {
      final prefs = await SharedPreferences.getInstance();

      // get the entire job list from prefs
      final jsonStr = prefs.getString('jobs');
      if (jsonStr == null) {
        debugPrint("ℹ️ No saved jobs to refresh");
        return;
      }

      final list = (jsonDecode(jsonStr) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // refresh each job from backend
      for (final job in list) {
        final jobId = job["jobId"];
        if (jobId == null) continue;

        final payloadJson = jsonEncode({"job_id": jobId});
        final sigBytes = Hmac(sha256, utf8.encode(controllerSharedSecret))
            .convert(utf8.encode(payloadJson));
        final sig = "sha256=${sigBytes.toString()}";

        final headers = {
          "Authorization": "Bearer $controllerApiKey",
          "X-Signature": sig,
        };

        final url = "$baseUrl/job_status?job_id=$jobId";
        final resp = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 15));

        if (resp.statusCode != 200) continue;

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        String status = (data["status"] ?? "").toString().toLowerCase();
        const allowed = ["processing", "completed", "failed"];
        if (!allowed.contains(status)) {
          status = "processing";
        }
        String? downloadUrl = data["download_url"] as String?;

        // ✅ Try cached downloadUrl if backend hasn’t sent one yet
        if (downloadUrl == null || downloadUrl.isEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final cachedUrl = prefs.getString("pending_download_url_$jobId");
          if (cachedUrl != null && cachedUrl.isNotEmpty) {
            downloadUrl = cachedUrl;
          }
        }

        // ✅ Update jobListNotifier safely
        final jobs = List<JobModel>.from(jobListNotifier.value);
        final idx = jobs.indexWhere((j) => j.jobId == jobId);
        if (idx != -1) {
          final old = jobs[idx];

          // ✅ Preserve old downloadUrl if new one is empty
          final finalUrl = (downloadUrl != null && downloadUrl.isNotEmpty)
              ? downloadUrl
              : old.downloadUrl;

          jobs[idx] = JobModel(
            jobId: old.jobId,
            title: old.title,
            model: old.model,
            outputType: old.outputType,
            downloadUrl: finalUrl,
            status: status.isNotEmpty ? status : old.status,
            createdAt: old.createdAt,
          );

          // ✅ Persist this downloadUrl for next refresh
          if (finalUrl != null && finalUrl.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString("pending_download_url_$jobId", finalUrl);
          }

          debugPrint(
              "✅ Refreshed job=$jobId → $status (url: ${finalUrl ?? 'none'})");
        }
        jobListNotifier.value = jobs;
      }
      await saveJobsToPrefs();
    } catch (e, st) {
      debugPrint("⚠️ PollingService.refreshNow() failed: $e\n$st");
    }
  }

  /// ✅ Refresh only jobs still marked as "processing"
  Future<void> refreshProcessingJobs() async {
    debugPrint(
        "🟢 PollingService.refreshProcessingJobs(): Refreshing active jobs only");
    try {
      final prefs = await SharedPreferences.getInstance();
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

      // 🧩 Only refresh recent 'processing' jobs
      final processingJobs = list.where((job) {
        final status = (job["status"] ?? "").toString().toLowerCase();
        if (status != "processing") return false;

        final createdAt =
            DateTime.tryParse(job["createdAt"] ?? "") ?? DateTime.now();
        final ageMin = now.difference(createdAt).inMinutes;
        if (ageMin > maxJobAgeMinutes) {
          debugPrint("⏩ Skipping old job ${job["jobId"]} (${ageMin} min old)");
          return false;
        }
        return true;
      }).toList();

      if (processingJobs.isEmpty) {
        debugPrint("✅ No processing jobs found — nothing to refresh");
        return;
      }

      debugPrint(
          "🌐 Checking ${processingJobs.length} recent processing jobs...");

      for (final job in processingJobs) {
        final jobId = job["jobId"];
        if (jobId == null) continue;

        // 🧠 Per-job throttle
        final lastPollKey = "last_poll_$jobId";
        final lastPollMs = prefs.getInt(lastPollKey) ?? 0;
        if (nowMs - lastPollMs < minPollIntervalSec * 1000) {
          debugPrint("⏩ Skipping $jobId (polled recently)");
          continue;
        }
        await prefs.setInt(lastPollKey, nowMs);

        final payloadJson = jsonEncode({"job_id": jobId});
        final sigBytes = Hmac(sha256, utf8.encode(controllerSharedSecret))
            .convert(utf8.encode(payloadJson));
        final sig = "sha256=${sigBytes.toString()}";

        final headers = {
          "Authorization": "Bearer $controllerApiKey",
          "X-Signature": sig,
        };

        final url = "$baseUrl/job_status?job_id=$jobId";
        final resp = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 15));

        if (resp.statusCode != 200) continue;

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        String status = (data["status"] ?? "").toString().toLowerCase();
        const allowed = ["processing", "completed", "failed"];
        if (!allowed.contains(status)) {
          status = "processing";
        }
        String? downloadUrl = data["download_url"] as String?;

        // Use cached URL if backend didn’t send one yet
        if (downloadUrl == null || downloadUrl.isEmpty) {
          final cached = prefs.getString("pending_download_url_$jobId");
          if (cached != null && cached.isNotEmpty) downloadUrl = cached;
        }

        // Update the local notifier list
        final jobs = List<JobModel>.from(jobListNotifier.value);
        final idx = jobs.indexWhere((j) => j.jobId == jobId);
        if (idx != -1) {
          final old = jobs[idx];
          final finalUrl = (downloadUrl != null && downloadUrl.isNotEmpty)
              ? downloadUrl
              : old.downloadUrl;

          jobs[idx] = JobModel(
            jobId: old.jobId,
            title: old.title,
            model: old.model,
            outputType: old.outputType,
            downloadUrl: finalUrl,
            status: status.isNotEmpty ? status : old.status,
            createdAt: old.createdAt,
          );

          if (finalUrl != null && finalUrl.isNotEmpty) {
            await prefs.setString("pending_download_url_$jobId", finalUrl);
          }

          debugPrint(
              "✅ Processing job=$jobId → $status (url: ${finalUrl ?? 'none'})");
          jobListNotifier.value = jobs;
        }
      }

      await saveJobsToPrefs();
      debugPrint("✅ refreshProcessingJobs() completed successfully");
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
