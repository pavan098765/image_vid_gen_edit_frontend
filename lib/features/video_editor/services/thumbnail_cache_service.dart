// lib/features/video_editor/services/thumbnail_cache_service.dart

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Timeline thumbnail caching and generation.
class ThumbnailCacheService {
  ThumbnailCacheService._();

  static final Map<String, List<Uint8List>> _cache = {};

  static List<Uint8List>? getCached(String clipId) => _cache[clipId];

  static void cache(String clipId, List<Uint8List> thumbnails) {
    _cache[clipId] = thumbnails;
  }

  static void evict(String clipId) => _cache.remove(clipId);

  static void clearAll() => _cache.clear();

  /// Full-file keyframe strip (used on import / initial load).
  static Future<List<Uint8List>> generateKeyFramesForFile(File file) async {
    final video = EditorVideo.file(file);
    return ProVideoEditor.instance.getKeyFrames(
      KeyFramesConfigs(
        video: video,
        outputSize: const Size.square(48),
        boxFit: ThumbnailBoxFit.cover,
        maxOutputFrames: 10,
        outputFormat: ThumbnailFormat.jpeg,
      ),
    );
  }

  /// Assumes [source] frames are spread across **[0, fileDuration]** in order.
  /// Returns thumbnails whose indices fall in **[rangeStart, rangeEnd]** (file time).
  static List<Uint8List>? sliceThumbnailsToFileRange({
    required List<Uint8List> source,
    required Duration fileDuration,
    required Duration rangeStart,
    required Duration rangeEnd,
  }) {
    if (source.isEmpty || fileDuration.inMilliseconds <= 0) return null;
    if (rangeEnd <= rangeStart) return null;
    final n = source.length;
    if (n == 1) return List<Uint8List>.from(source);

    int indexFor(Duration t) {
      final frac =
          (t.inMilliseconds / fileDuration.inMilliseconds).clamp(0.0, 1.0);
      return (frac * (n - 1)).round().clamp(0, n - 1);
    }

    final endProbe = rangeEnd - const Duration(microseconds: 1);
    final a = indexFor(rangeStart);
    final b = indexFor(endProbe < rangeStart ? rangeStart : endProbe);
    final lo = min(a, b);
    final hi = max(a, b);
    return List<Uint8List>.from(source.sublist(lo, hi + 1));
  }

  /// Extracts JPEG thumbnails at evenly spaced times in **[trimStart, trimEnd]**.
  static Future<List<Uint8List>> extractThumbnailsForSourceRange({
    required String videoPath,
    required Duration trimStart,
    required Duration trimEnd,
    int maxFrames = 8,
    int size = 48,
  }) async {
    if (trimEnd <= trimStart) return [];
    final spanMs = trimEnd.inMilliseconds - trimStart.inMilliseconds;
    final count = maxFrames.clamp(1, 20).toInt();
    final out = <Uint8List>[];
    for (int i = 0; i < count; i++) {
      final ms = trimStart.inMilliseconds +
          (count <= 1
              ? 0
              : ((spanMs * i) / (count - 1)).round());
      final clamped = ms.clamp(
        trimStart.inMilliseconds,
        max(trimStart.inMilliseconds, trimEnd.inMilliseconds - 1),
      ).toInt();
      try {
        final data = await VideoThumbnail.thumbnailData(
          video: videoPath,
          timeMs: clamped,
          imageFormat: ImageFormat.JPEG,
          maxHeight: size,
          maxWidth: size,
          quality: 75,
        );
        if (data != null) out.add(data);
      } catch (e) {
        debugPrint('Thumbnail extract failed at ${clamped}ms: $e');
      }
    }
    return out;
  }

  /// Backing implementation for [generateThumbnails] — range-based extraction.
  static Future<List<Uint8List>> generateThumbnails({
    required String videoPath,
    required int count,
    required Duration start,
    required Duration end,
    int thumbnailWidth = 80,
    int thumbnailHeight = 80,
  }) async {
    final cacheKey =
        '$videoPath:$count:${start.inMilliseconds}:${end.inMilliseconds}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    final size = max(thumbnailWidth, thumbnailHeight);
    final list = await extractThumbnailsForSourceRange(
      videoPath: videoPath,
      trimStart: start,
      trimEnd: end,
      maxFrames: count,
      size: size,
    );
    _cache[cacheKey] = list;
    return list;
  }
}
