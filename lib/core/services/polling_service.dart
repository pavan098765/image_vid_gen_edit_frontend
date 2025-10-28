// lib/core/services/polling_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class PollingService {
  PollingService._();
  static final PollingService instance = PollingService._();

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
      final status = (data["status"] ?? "").toString().toLowerCase();
      String? downloadUrl = data["download_url"] as String?;
      if (downloadUrl != null && downloadUrl.isNotEmpty) {
        await prefs.setString("pending_download_url", downloadUrl);
      } else {
        downloadUrl = prefs.getString("pending_download_url");
      }

      // --- 2️⃣ Emit event to UI
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
