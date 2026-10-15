import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/studio/studio_models.dart';

class StudioApiException implements Exception {
  final int statusCode;
  final String message;
  StudioApiException(this.statusCode, this.message);
  @override
  String toString() => 'StudioApiException($statusCode): $message';
}

class StudioApi {
  StudioApi._();
  static final StudioApi instance = StudioApi._();
  final AuthService _auth = AuthService();

  Future<Map<String, String>> _headers() async {
    final token = await _auth.getIdToken();
    if (token == null) {
      throw StudioApiException(401, 'Sign in required');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$kStudioBaseUrl$path');
    final headers = await _headers();
    late http.Response resp;
    if (method == 'GET') {
      resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    } else {
      resp = await http
          .post(uri, headers: headers, body: body == null ? null : jsonEncode(body))
          .timeout(const Duration(seconds: 60));
    }
    if (resp.statusCode >= 400) {
      throw StudioApiException(resp.statusCode, resp.body);
    }
    if (resp.body.isEmpty) return {};
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  Future<Map<String, dynamic>> createJob({
    required String pipeline,
    required StudioPrefs prefs,
    required bool reviewMode,
    required List<String> assetKeys,
    String? fcmToken,
  }) {
    return _json('POST', '/studio/jobs', body: {
      'pipeline': pipeline,
      'prefs': prefs.toJson(),
      'review_mode': reviewMode,
      'asset_keys': assetKeys,
      if (fcmToken != null) 'fcm_token': fcmToken,
    });
  }

  Future<Map<String, dynamic>> getJob(String jobId) {
    return _json('GET', '/studio/jobs/$jobId');
  }

  Future<StudioStoryboard> getStoryboard(String jobId) async {
    final data = await _json('GET', '/studio/jobs/$jobId/storyboard');
    return StudioStoryboard.fromJson(data);
  }

  Future<void> sceneAction({
    required String jobId,
    required String sceneId,
    required String action,
    String? copy,
    String? replaceR2Key,
    String? exploreJobId,
  }) async {
    await _json('POST', '/studio/jobs/$jobId/scenes/$sceneId', body: {
      'action': action,
      if (copy != null) 'copy': copy,
      if (replaceR2Key != null) 'replace_r2_key': replaceR2Key,
      if (exploreJobId != null) 'explore_job_id': exploreJobId,
    });
  }

  Future<void> continueJob(
    String jobId, {
    List<Map<String, dynamic>>? cuts,
  }) async {
    await _json(
      'POST',
      '/studio/jobs/$jobId/continue',
      body: cuts == null ? null : {'cuts': cuts},
    );
  }

  Future<Map<String, dynamic>> getResult(String jobId) {
    return _json('GET', '/studio/jobs/$jobId/result');
  }

  Future<String> uploadFile({required String jobId, required File file}) async {
    final filename = file.uri.pathSegments.isEmpty
        ? 'upload.bin'
        : file.uri.pathSegments.last;
    final uniqueName =
        '${DateTime.now().microsecondsSinceEpoch}_$filename';
    final presign = await _json('POST', '/studio/uploads', body: {
      'job_id': jobId,
      'filename': uniqueName,
      'content_type': 'application/octet-stream',
    });
    final url = presign['upload_url'] as String;
    final key = presign['key'] as String;
    final bytes = await file.readAsBytes();
    final put = await http.put(
      Uri.parse(url),
      headers: {'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
    if (put.statusCode >= 400) {
      throw StudioApiException(put.statusCode, 'upload failed');
    }
    return key;
  }
}
