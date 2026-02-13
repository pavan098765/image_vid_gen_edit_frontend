import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:video_thumbnail/video_thumbnail.dart';

/// Service for efficient thumbnail generation and caching.
/// Handles large images (16-20MB+) without blocking the main thread.
class ThumbnailService {
  ThumbnailService._();
  static final ThumbnailService instance = ThumbnailService._();

  // In-memory cache for quick access (path -> thumbnail bytes)
  final Map<String, Uint8List> _memoryCache = {};
  
  // Maximum memory cache size (50 thumbnails)
  static const int _maxMemoryCacheSize = 50;
  
  // Thumbnail directory
  Directory? _thumbnailDir;
  
  // Pending generations to avoid duplicates
  final Map<String, Completer<Uint8List?>> _pendingGenerations = {};

  /// Initialize the service - call once at app startup
  Future<void> init() async {
    final tempDir = await getTemporaryDirectory();
    _thumbnailDir = Directory('${tempDir.path}/thumbnails');
    if (!await _thumbnailDir!.exists()) {
      await _thumbnailDir!.create(recursive: true);
    }
    debugPrint('🖼️ ThumbnailService initialized at ${_thumbnailDir!.path}');
  }

  /// Get cached thumbnail directory path
  Future<String> get thumbnailDirPath async {
    if (_thumbnailDir == null) await init();
    return _thumbnailDir!.path;
  }

  /// Generate a unique cache key for an image file
  String _getCacheKey(String filePath, int size) {
    final hash = md5.convert(filePath.codeUnits).toString();
    return '${hash}_$size';
  }

  /// Get thumbnail file path
  String _getThumbnailPath(String cacheKey) {
    return '${_thumbnailDir!.path}/$cacheKey.jpg';
  }

  /// Check if file is a video by extension
  bool _isVideoFile(String filePath) {
    final ext = filePath.toLowerCase().split('.').last;
    return ext == 'mp4' || ext == 'mov' || ext == 'avi' || ext == 'mkv' || ext == 'webm';
  }

  /// Get or generate a thumbnail for a file
  /// Returns null if generation fails
  Future<Uint8List?> getThumbnail(
    String filePath, {
    int size = 150, // Thumbnail size (width and height)
    int quality = 85, // JPEG quality (70-100)
  }) async {
    if (_thumbnailDir == null) await init();
    
    final cacheKey = _getCacheKey(filePath, size);
    
    // 1. Check memory cache first
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey];
    }
    
    // 2. Check disk cache
    final thumbPath = _getThumbnailPath(cacheKey);
    final thumbFile = File(thumbPath);
    if (await thumbFile.exists()) {
      try {
        final bytes = await thumbFile.readAsBytes();
        _addToMemoryCache(cacheKey, bytes);
        return bytes;
      } catch (e) {
        debugPrint('⚠️ Failed to read cached thumbnail: $e');
      }
    }
    
    // 3. Check if generation is already in progress
    if (_pendingGenerations.containsKey(cacheKey)) {
      return _pendingGenerations[cacheKey]!.future;
    }
    
    // 4. Generate new thumbnail
    final completer = Completer<Uint8List?>();
    _pendingGenerations[cacheKey] = completer;
    
    try {
      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) {
        completer.complete(null);
        return null;
      }
      
      Uint8List? result;
      
      // Handle video files separately (must run on main thread)
      if (_isVideoFile(filePath)) {
        debugPrint('🎬 Generating video thumbnail for: $filePath');
        try {
          // Generate video thumbnail using video_thumbnail package
          final thumbnailBytes = await VideoThumbnail.thumbnailData(
            video: filePath,
            imageFormat: ImageFormat.JPEG,
            maxWidth: size,
            quality: quality,
            timeMs: 0, // First frame
          );
          
          if (thumbnailBytes != null) {
            // Save to disk cache
            final outputFile = File(thumbPath);
            await outputFile.writeAsBytes(thumbnailBytes);
            result = thumbnailBytes;
            debugPrint('✅ Video thumbnail generated successfully');
          } else {
            debugPrint('⚠️ Video thumbnail generation returned null');
          }
        } catch (e) {
          debugPrint('❌ Video thumbnail generation failed: $e');
        }
      } else {
        // Handle image files in isolate to avoid blocking main thread
        result = await compute(
          _generateThumbnailIsolate,
          _ThumbnailParams(
            filePath: filePath,
            outputPath: thumbPath,
            size: size,
            quality: quality,
          ),
        );
      }
      
      if (result != null) {
        _addToMemoryCache(cacheKey, result);
        completer.complete(result);
        return result;
      } else {
        completer.complete(null);
        return null;
      }
    } catch (e) {
      debugPrint('❌ Thumbnail generation failed: $e');
      completer.complete(null);
      return null;
    } finally {
      _pendingGenerations.remove(cacheKey);
    }
  }

  /// Add to memory cache with LRU eviction
  void _addToMemoryCache(String key, Uint8List bytes) {
    // Simple LRU: remove oldest if at capacity
    if (_memoryCache.length >= _maxMemoryCacheSize) {
      final oldestKey = _memoryCache.keys.first;
      _memoryCache.remove(oldestKey);
    }
    _memoryCache[key] = bytes;
  }

  /// Clear all cached thumbnails
  Future<void> clearCache() async {
    _memoryCache.clear();
    if (_thumbnailDir != null && await _thumbnailDir!.exists()) {
      await _thumbnailDir!.delete(recursive: true);
      await _thumbnailDir!.create(recursive: true);
    }
    debugPrint('🗑️ Thumbnail cache cleared');
  }

  /// Clear memory cache only (keeps disk cache)
  void clearMemoryCache() {
    _memoryCache.clear();
    debugPrint('🗑️ Thumbnail memory cache cleared');
  }

  /// Preload thumbnails for a list of file paths
  Future<void> preloadThumbnails(List<String> filePaths, {int size = 150}) async {
    for (final path in filePaths) {
      // Fire and forget - don't await each one
      getThumbnail(path, size: size);
    }
  }
}

/// Parameters for isolate thumbnail generation
class _ThumbnailParams {
  final String filePath;
  final String outputPath;
  final int size;
  final int quality;

  _ThumbnailParams({
    required this.filePath,
    required this.outputPath,
    required this.size,
    required this.quality,
  });
}

/// Isolate function for thumbnail generation
/// This runs in a separate thread, not blocking the UI
Future<Uint8List?> _generateThumbnailIsolate(_ThumbnailParams params) async {
  try {
    final file = File(params.filePath);
    if (!file.existsSync()) return null;
    
    final bytes = await file.readAsBytes();
    
    // Decode image
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    
    // Calculate thumbnail dimensions (maintain aspect ratio)
    int width, height;
    if (image.width > image.height) {
      width = params.size;
      height = (params.size * image.height / image.width).round();
    } else {
      height = params.size;
      width = (params.size * image.width / image.height).round();
    }
    
    // Resize using high-quality interpolation
    final thumbnail = img.copyResize(
      image,
      width: width,
      height: height,
      interpolation: img.Interpolation.average,
    );
    
    // Encode as JPEG (much smaller than PNG for thumbnails)
    final jpegBytes = Uint8List.fromList(
      img.encodeJpg(thumbnail, quality: params.quality),
    );
    
    // Save to disk cache
    final outputFile = File(params.outputPath);
    await outputFile.writeAsBytes(jpegBytes);
    
    return jpegBytes;
  } catch (e) {
    debugPrint('❌ Isolate thumbnail error: $e');
    return null;
  }
}

/// A widget that efficiently displays thumbnails with caching
class CachedThumbnail extends StatefulWidget {
  final String? filePath;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final int thumbnailSize;

  const CachedThumbnail({
    super.key,
    required this.filePath,
    this.width = 52,
    this.height = 52,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.thumbnailSize = 150,
  });

  @override
  State<CachedThumbnail> createState() => _CachedThumbnailState();
}

class _CachedThumbnailState extends State<CachedThumbnail> {
  Uint8List? _thumbnailBytes;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(CachedThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    if (widget.filePath == null || widget.filePath!.isEmpty) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final bytes = await ThumbnailService.instance.getThumbnail(
        widget.filePath!,
        size: widget.thumbnailSize,
      );
      
      if (mounted) {
        setState(() {
          _thumbnailBytes = bytes;
          _isLoading = false;
          _hasError = bytes == null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    if (_isLoading) {
      return widget.placeholder ?? Container(
        width: widget.width,
        height: widget.height,
        color: cs.surfaceContainerHigh,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.primary.withOpacity(0.5),
            ),
          ),
        ),
      );
    }

    if (_hasError || _thumbnailBytes == null) {
      return widget.errorWidget ?? Container(
        width: widget.width,
        height: widget.height,
        color: cs.surfaceContainerHigh,
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 20,
          color: cs.onSurfaceVariant.withOpacity(0.5),
        ),
      );
    }

    return Image.memory(
      _thumbnailBytes!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true, // Prevents flicker during updates
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Efficient image widget that uses cacheWidth/cacheHeight
/// for memory-efficient loading of large images
class OptimizedImage extends StatelessWidget {
  final String filePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final Widget? placeholder;
  final Widget? errorWidget;

  const OptimizedImage({
    super.key,
    required this.filePath,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.cacheWidth,
    this.cacheHeight,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);
    
    if (!file.existsSync()) {
      return errorWidget ?? const Icon(Icons.broken_image);
    }

    // Calculate cache dimensions based on screen DPR
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final effectiveCacheWidth = cacheWidth ?? 
        (width != null ? (width! * dpr).toInt() : null);
    final effectiveCacheHeight = cacheHeight ?? 
        (height != null ? (height! * dpr).toInt() : null);

    return Image.file(
      file,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: effectiveCacheWidth,
      cacheHeight: effectiveCacheHeight,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: frame != null
              ? child
              : placeholder ?? Container(
                  width: width,
                  height: height,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('❌ Image load error: $error');
        return errorWidget ?? Container(
          width: width,
          height: height,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Icon(
            Icons.broken_image,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}

