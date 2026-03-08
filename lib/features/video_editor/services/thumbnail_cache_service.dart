// lib/features/video_editor/services/thumbnail_cache_service.dart

import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Service for generating and caching timeline thumbnail strips.
///
/// This wraps the pro_video_editor thumbnail generation and adds
/// caching to avoid regenerating thumbnails on every rebuild.
class ThumbnailCacheService {
  ThumbnailCacheService._();

  static final Map<String, List<Uint8List>> _cache = {};

  /// Get cached thumbnails for a video clip.
  static List<Uint8List>? getCached(String clipId) => _cache[clipId];

  /// Store thumbnails in cache.
  static void cache(String clipId, List<Uint8List> thumbnails) {
    _cache[clipId] = thumbnails;
  }

  /// Remove a clip's thumbnails from cache.
  static void evict(String clipId) => _cache.remove(clipId);

  /// Clear the entire cache.
  static void clearAll() => _cache.clear();

  /// Generate thumbnails for a video file using pro_video_editor.
  ///
  /// This is a placeholder — the actual generation should use
  /// ProVideoEditorController or FFmpeg to extract frames.
  static Future<List<Uint8List>> generateThumbnails({
    required String videoPath,
    required int count,
    required Duration start,
    required Duration end,
    int thumbnailWidth = 80,
    int thumbnailHeight = 80,
  }) async {
    // Check cache first
    final cacheKey = '$videoPath:$count:${start.inMilliseconds}:${end.inMilliseconds}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    // TODO: Implement actual thumbnail extraction using pro_video_editor
    // or FFmpeg. For now, return empty list — the UI shows a placeholder.
    final thumbnails = <Uint8List>[];

    _cache[cacheKey] = thumbnails;
    return thumbnails;
  }
}
