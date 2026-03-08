// lib/core/services/media_upload_service.dart
//
// Lightweight service for uploading media (images/videos) to R2 via presigned URLs.
//
// Flow:
// 1. Call getMediaUploadUrls() to get presigned PUT URLs + R2 keys from the backend
// 2. PUT raw binary data to each presigned URL
// 3. Return the R2 keys so the caller can include them in the /submit payload
//
// On any failure the methods return null so callers can fall back to base64.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Result of requesting upload URLs from the backend.
class MediaUploadUrlResult {
  final String uploadUrl;
  final String r2Key;
  const MediaUploadUrlResult({required this.uploadUrl, required this.r2Key});
}

class MediaUploadService {
  MediaUploadService._();

  static const String _baseUrl = "https://genedit.mooo.com";

  /// Request [count] presigned PUT URLs for the given [mediaType] ("image" or "video").
  /// Returns null on failure so the caller can fall back to base64.
  static Future<List<MediaUploadUrlResult>?> getMediaUploadUrls({
    required int count,
    required String mediaType,
    required String authToken,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/get_media_upload_urls'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode({'count': count, 'media_type': mediaType}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        debugPrint('⚠️ R2 getMediaUploadUrls failed: ${resp.statusCode} ${resp.body}');
        return null;
      }

      final data = jsonDecode(resp.body);
      final uploads = data['uploads'] as List<dynamic>?;
      if (uploads == null || uploads.length < count) {
        debugPrint('⚠️ R2 getMediaUploadUrls returned fewer URLs than requested');
        return null;
      }

      return uploads.map((u) {
        return MediaUploadUrlResult(
          uploadUrl: u['upload_url'] as String,
          r2Key: u['r2_key'] as String,
        );
      }).toList();
    } catch (e) {
      debugPrint('⚠️ R2 getMediaUploadUrls error: $e');
      return null;
    }
  }

  /// Upload raw bytes to a single presigned PUT URL.
  /// Returns true on success, false on failure.
  static Future<bool> uploadToR2(String presignedUrl, Uint8List bytes, {String contentType = 'application/octet-stream'}) async {
    try {
      final resp = await http
          .put(
            Uri.parse(presignedUrl),
            headers: {'Content-Type': contentType},
            body: bytes,
          )
          .timeout(const Duration(seconds: 120));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return true;
      }
      debugPrint('⚠️ R2 PUT failed: ${resp.statusCode} (${bytes.length} bytes)');
      return false;
    } catch (e) {
      debugPrint('⚠️ R2 PUT error: $e');
      return false;
    }
  }

  /// Upload a batch of files to R2 in parallel.
  ///
  /// 1. Requests presigned URLs from the backend.
  /// 2. PUTs each file in parallel.
  /// 3. Returns the list of R2 keys on success, or null if any step fails
  ///    (so the caller can fall back to base64).
  ///
  /// [files] — non-empty list of raw bytes to upload.
  /// [mediaType] — "image" or "video".
  /// [authToken] — Firebase ID token.
  static Future<List<String>?> uploadMediaBatch({
    required List<Uint8List> files,
    required String mediaType,
    required String authToken,
  }) async {
    if (files.isEmpty) return null;

    final urls = await getMediaUploadUrls(
      count: files.length,
      mediaType: mediaType,
      authToken: authToken,
    );

    if (urls == null) return null;

    // Upload all files in parallel
    final results = await Future.wait(
      List.generate(files.length, (i) {
        final contentType = mediaType == 'video' ? 'video/mp4' : 'application/octet-stream';
        return uploadToR2(urls[i].uploadUrl, files[i], contentType: contentType);
      }),
    );

    if (results.any((ok) => !ok)) {
      debugPrint('⚠️ R2 batch upload: one or more uploads failed — falling back to base64');
      return null;
    }

    return urls.map((u) => u.r2Key).toList();
  }

  /// Convenience: Upload a batch of nullable files (e.g. masks where some slots are null).
  /// Returns a list of nullable R2 keys aligned with the input list, or null on failure.
  static Future<List<String?>?> uploadNullableMediaBatch({
    required List<Uint8List?> files,
    required String mediaType,
    required String authToken,
  }) async {
    // Collect non-null items with their indices
    final nonNullIndices = <int>[];
    final nonNullFiles = <Uint8List>[];
    for (int i = 0; i < files.length; i++) {
      if (files[i] != null) {
        nonNullIndices.add(i);
        nonNullFiles.add(files[i]!);
      }
    }

    if (nonNullFiles.isEmpty) {
      // All null — return aligned list of nulls (no upload needed)
      return List<String?>.filled(files.length, null);
    }

    final keys = await uploadMediaBatch(
      files: nonNullFiles,
      mediaType: mediaType,
      authToken: authToken,
    );

    if (keys == null) return null;

    // Rebuild aligned list
    final aligned = List<String?>.filled(files.length, null);
    for (int j = 0; j < nonNullIndices.length; j++) {
      aligned[nonNullIndices[j]] = keys[j];
    }
    return aligned;
  }
}
