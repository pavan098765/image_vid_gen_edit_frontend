import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/thumbnail_service.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

class FileService {
  static bool _isSaving = false;
  static String? _lastSavedHash;
  static bool _cleanupStarted = false;
  static bool _isPreviewOpen = false;
  static final Map<String, String> _previewCache =
      {}; // jobId/url → local file path

  // ============================================================
  // Download Queue with Concurrency Limits
  // ============================================================
  static const int _maxConcurrentDownloads = 2;
  static const int _maxQueuedDownloads = 10; // Prevent excessive queueing
  static int _activeDownloads = 0;
  static final List<_DownloadTask> _downloadQueue = [];
  
  // Snackbar debouncing to prevent spam
  static DateTime? _lastErrorSnackbarTime;
  static String? _lastErrorMessage;
  static const Duration _snackbarDebounceTime = Duration(seconds: 3);
  
  /// Queue a download with concurrency control
  /// This prevents multiple large files from being downloaded simultaneously
  static Future<String?> queueDownload(
    BuildContext context,
    String url, {
    String? suggestedFileName,
    String subfolder = 'Kala_AI',
    void Function(double progress)? onProgress,
    int maxRetries = 3,
  }) async {
    // Prevent excessive queueing
    if (_downloadQueue.length >= _maxQueuedDownloads) {
      _showDebouncedSnackbar(
        context, 
        'Download queue full. Please wait for current downloads to complete.',
      );
      return null;
    }
    
    final completer = Completer<String?>();
    
    final task = _DownloadTask(
      context: context,
      url: url,
      suggestedFileName: suggestedFileName,
      subfolder: subfolder,
      onProgress: onProgress,
      maxRetries: maxRetries,
      completer: completer,
    );
    
    _downloadQueue.add(task);
    _processQueue();
    
    return completer.future;
  }
  
  /// Show snackbar with debouncing to prevent spam
  static void _showDebouncedSnackbar(BuildContext context, String message, {Duration? duration}) {
    final now = DateTime.now();
    
    // Skip if same message shown recently
    if (_lastErrorMessage == message && 
        _lastErrorSnackbarTime != null &&
        now.difference(_lastErrorSnackbarTime!) < _snackbarDebounceTime) {
      return;
    }
    
    _lastErrorMessage = message;
    _lastErrorSnackbarTime = now;
    
    if (context.mounted) {
      // Clear any existing snackbars first
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration ?? const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static void _processQueue() async {
    while (_activeDownloads < _maxConcurrentDownloads && _downloadQueue.isNotEmpty) {
      final task = _downloadQueue.removeAt(0);
      _activeDownloads++;
      
      // Execute download and handle completion
      downloadFromUrl(
        task.context,
        task.url,
        suggestedFileName: task.suggestedFileName,
        subfolder: task.subfolder,
        onProgress: task.onProgress,
        maxRetries: task.maxRetries,
      ).then((result) async {
        task.completer.complete(result);
        _activeDownloads--;
        
        // Small delay between downloads to prevent UI jank
        if (_downloadQueue.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
        _processQueue(); // Process next in queue
      }).catchError((error) async {
        task.completer.complete(null);
        _activeDownloads--;
        
        // Small delay between downloads
        if (_downloadQueue.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
        _processQueue(); // Process next in queue
      });
    }
  }

  /// Get current download queue status
  static int get pendingDownloads => _downloadQueue.length;
  static int get activeDownloads => _activeDownloads;

  static Future<Directory> getTempDir() async => await getTemporaryDirectory();

  /// 🚀 Save raw bytes (image/video) to the gallery.
  static Future<String?> saveFile(
    BuildContext context,
    Uint8List bytes, {
    String? customFileName,
    String subfolder = 'Kala_AI',
    String extension = 'png',
    bool showPreview = true,
    Uint8List? previewBytes,
  }) async {
    final currentHash = sha1.convert(bytes).toString();

    if (currentHash == _lastSavedHash) {
      debugPrint('⚠️ Skipping duplicate save (same content)');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File already saved!')),
        );
      }
      return null;
    }

    if (_isSaving) {
      debugPrint('⚠️ Save already in progress — skipping.');
      return null;
    }

    _isSaving = true;
    _lastSavedHash = currentHash;

    try {
      final hasPermission = await Gal.requestAccess();
      if (!hasPermission) {
        debugPrint('❌ Gallery access not granted.');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gallery permission denied.')),
          );
        }
        return null;
      }

      String fileName = (customFileName != null &&
              customFileName.toLowerCase().endsWith('.$extension'))
          ? customFileName
          : _normalizeFileName(customFileName ?? const Uuid().v4(),
              defaultExt: extension);

      // 🧩 Final sanity cleanup: if ".png.png" slipped in, fix it
      fileName = fileName.replaceAll('.$extension.$extension', '.$extension');
      debugPrint("File name to save: $fileName");

      // ✅ Strip extension before passing to Gal (it auto-adds one for images)
      final galName = fileName.replaceAll(RegExp('\\.$extension\$'), '');
      debugPrint("🪄 Passing to Gal: $galName (extension: .$extension)");

      if (extension.toLowerCase() == 'mp4') {
        // --- Write bytes to a temp file named exactly `fileName` (including .mp4)
        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/$fileName';
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(bytes, flush: true);

        // Call Gal.putVideo with the path (Gal expects a path and will copy it to gallery)
        await Gal.putVideo(tempFile.path, album: subfolder);

        // Optionally remove temp file after some delay or immediately
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (e) {
          debugPrint('⚠️ Failed to delete temp video file: $e');
        }
      } else {
        // For images: pass name WITHOUT extension, Gal will append the extension itself
        await Gal.putImageBytes(
          bytes,
          album: subfolder,
          name: galName,
        );
      }

      // ✅ Compute correct save path
      final Directory baseDir = Directory('/storage/emulated/0/Pictures');
      final saveDir = Directory('${baseDir.path}/$subfolder');
      final filePath = '${saveDir.path}/$fileName';

      if (context.mounted && showPreview) {
        // For video files, generate thumbnail if not provided
        Uint8List? finalPreviewBytes = previewBytes;
        final isVideoExt = extension.toLowerCase() == 'mp4' || 
                           extension.toLowerCase() == 'mov' ||
                           extension.toLowerCase() == 'avi';
        if (isVideoExt && finalPreviewBytes == null) {
          try {
            // Write to temp file first to generate thumbnail
            final tempDir = await getTemporaryDirectory();
            final tempPath = '${tempDir.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.$extension';
            final tempFile = File(tempPath);
            await tempFile.writeAsBytes(bytes, flush: true);
            
            // Generate thumbnail using ThumbnailService
            final thumbnail = await ThumbnailService.instance.getThumbnail(
              tempPath,
              size: 200, // Good size for preview
              quality: 85,
            );
            
            if (thumbnail != null) {
              finalPreviewBytes = thumbnail;
              debugPrint('✅ Generated video thumbnail for saved popup');
            }
            
            // Clean up temp file
            try {
              if (await tempFile.exists()) {
                await tempFile.delete();
              }
            } catch (_) {}
          } catch (e) {
            debugPrint('⚠️ Failed to generate video thumbnail for popup: $e');
          }
        }
        
        _showSavedBottomSheet(context, bytes, filePath, finalPreviewBytes);
      }

      debugPrint('✅ Saved file: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('❌ Save error: $e');
      return null;
    } finally {
      _isSaving = false;
    }
  }

  // ✅ Preview returning local path
  static Future<String?> previewFileAndReturnPath(
    BuildContext context,
    String url, {
    required String uniqueKey,
  }) async {
    try {
      final tempFile = await _downloadPreviewFile(url, uniqueKey);
      if (tempFile != null) {
        _showImageDialog(context, tempFile.path);
        return tempFile.path;
      }
    } catch (_) {}
    return null;
  }

// ✅ Internal preview download
  static Future<File?> _downloadPreviewFile(
      String url, String uniqueKey) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;
    final fileName = _normalizeFileName(
        'preview_${DateTime.now().millisecondsSinceEpoch}.png');

    final file = await writeTempFile(response.bodyBytes, fileName);
    _previewCache[uniqueKey] = file.path;
    await _savePreviewCache();
    return file;
  }

// ✅ Save an already-downloaded file to gallery (no re-download)
  static Future<bool> saveExistingToGallery(
    BuildContext context,
    String path,
  ) async {
    try {
      final bytes = await File(path).readAsBytes();
      final isVideo = path.toLowerCase().endsWith('.mp4') || 
                      path.toLowerCase().endsWith('.mov') ||
                      path.toLowerCase().endsWith('.avi');
      
      // Generate thumbnail for videos
      Uint8List? previewBytes;
      if (isVideo) {
        try {
          final thumbnail = await ThumbnailService.instance.getThumbnail(
            path,
            size: 200,
            quality: 85,
          );
          if (thumbnail != null) {
            previewBytes = thumbnail;
            debugPrint('✅ Generated video thumbnail for saveExistingToGallery');
          }
        } catch (e) {
          debugPrint('⚠️ Failed to generate video thumbnail: $e');
        }
      }
      
      final extension = path.split('.').last.toLowerCase();
      final saved = await saveFile(
        context, 
        bytes,
        extension: extension,
        previewBytes: previewBytes,
      );
      return saved != null;
    } catch (_) {
      return false;
    }
  }

  /// 🖼️ Displays the preview image in a fullscreen dialog with zoom and close button
  /// Uses progressive loading for large images to avoid UI freezes
  static void _showImageDialog(BuildContext context, String filePath) {
    if (!File(filePath).existsSync()) {
      debugPrint("⚠️ File not found for preview: $filePath");
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('File not found.')));
      return;
    }

    if (_isPreviewOpen) return; // 🚫 prevent double openings
    _isPreviewOpen = true;

    showGeneralDialog(
      context: context,
      barrierDismissible: false, // ⛔ no tap-outside close
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (_, __, ___) {
        return WillPopScope(
          onWillPop: () async {
            _isPreviewOpen = false;
            return true;
          },
          child: _ProgressiveImagePreview(
            filePath: filePath,
            onClose: () {
              _isPreviewOpen = false;
              Navigator.of(context, rootNavigator: true).pop();
            },
          ),
        );
      },
    ).then((_) {
      // Ensure flag resets even if system back triggered
      _isPreviewOpen = false;
    });
  }

  /// 🖼️ Displays media preview with optional swipe navigation
  /// Supports both images and videos
  static void _showMediaPreviewDialog(
    BuildContext context,
    String filePath, {
    List<String>? allPaths,
    int currentIndex = 0,
  }) {
    if (!File(filePath).existsSync()) {
      debugPrint("⚠️ File not found for preview: $filePath");
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('File not found.')));
      return;
    }

    if (_isPreviewOpen) return; // 🚫 prevent double openings
    _isPreviewOpen = true;

    // Filter allPaths to only include existing files
    final List<String> validPaths = allPaths?.where((p) => File(p).existsSync()).toList() ?? [];
    final hasMultiple = validPaths.length > 1;
    
    // Recalculate current index if paths were filtered
    int adjustedIndex = currentIndex;
    if (hasMultiple && allPaths != null && allPaths.isNotEmpty) {
      final originalPath = allPaths.length > currentIndex ? allPaths[currentIndex] : filePath;
      adjustedIndex = validPaths.indexOf(originalPath);
      if (adjustedIndex < 0) adjustedIndex = 0;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false, // ⛔ no tap-outside close
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (_, __, ___) {
        return WillPopScope(
          onWillPop: () async {
            _isPreviewOpen = false;
            return true;
          },
          child: hasMultiple
              ? _SwipeableMediaPreview(
                  filePaths: validPaths,
                  initialIndex: adjustedIndex,
                  onClose: () {
                    _isPreviewOpen = false;
                    Navigator.of(context, rootNavigator: true).pop();
                  },
                )
              : _ProgressiveImagePreview(
                  filePath: filePath,
                  onClose: () {
                    _isPreviewOpen = false;
                    Navigator.of(context, rootNavigator: true).pop();
                  },
                ),
        );
      },
    ).then((_) {
      // Ensure flag resets even if system back triggered
      _isPreviewOpen = false;
    });
  }

  static Future<void> previewFile(BuildContext context, String url,
      {required String uniqueKey}) async {
    try {
      // ✅ Step 1: Use unique cache key (prefer jobId)
      final cacheKey = uniqueKey;

      // ✅ Step 2: Check in-memory cache
      String? cachedPath = _previewCache[cacheKey];
      if (cachedPath != null && File(cachedPath).existsSync()) {
        debugPrint("🖼️ Using cached preview for $cacheKey");
        _showImageDialog(context, cachedPath);
        return;
      }

      // ✅ Step 3: Download file only once
      debugPrint("⬇️ Downloading preview for $cacheKey");
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception("Server responded ${response.statusCode}");
      }

      // ✅ Step 4: Create unique filename per job
      final fileName = _normalizeFileName(
          'preview_${DateTime.now().millisecondsSinceEpoch}.png');

      // ✅ Step 5: Save to temp folder
      final tempFile = await writeTempFile(response.bodyBytes, fileName);
      _previewCache[cacheKey] = tempFile.path; // store in memory for reuse
      await _savePreviewCache();

      // ✅ Step 6: Show preview
      _showImageDialog(context, tempFile.path);
    } catch (e) {
      debugPrint('❌ Preview failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Preview failed: $e')));
      }
    }
  }

  // ✅ Utility: sanitize and normalize file names
  static String _normalizeFileName(String rawName,
      {String defaultExt = "png"}) {
    if (rawName.isEmpty) return "${const Uuid().v4()}.$defaultExt";

    var name = rawName.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    // Remove duplicate extensions like .png.png or .jpg.png
    final repeatedExt = RegExp('(\\.' + RegExp.escape(defaultExt) + r')+$',
        caseSensitive: false);
    name = name.replaceAll(repeatedExt, '');

    // If it already has some extension (e.g., .jpg), remove it and replace with .png
    final extMatch = RegExp(r'\.[a-zA-Z0-9]+$').firstMatch(name);
    if (extMatch != null) {
      name = name.substring(0, name.length - extMatch.group(0)!.length);
    }

    return "$name.$defaultExt";
  }

  static Future<void> loadPreviewCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('preview_cache');
      if (stored != null) {
        final map = Map<String, String>.from(jsonDecode(stored));
        _previewCache.addAll(map);
        debugPrint(
            "🗂️ Restored ${_previewCache.length} preview cache entries.");
      }
    } catch (e) {
      debugPrint("⚠️ Failed to load preview cache: $e");
    }
  }

  static Future<void> _savePreviewCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('preview_cache', jsonEncode(_previewCache));
    } catch (e) {
      debugPrint("⚠️ Failed to persist preview cache: $e");
    }
  }

  /// Clear all preview cache files and memory
  static Future<void> clearPreviewCache() async {
    try {
      // Delete cached preview files
      for (final path in _previewCache.values) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint("⚠️ Failed to delete preview file: $e");
        }
      }
      
      // Clear memory cache
      _previewCache.clear();
      
      // Persist empty cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('preview_cache');
      
      debugPrint("🗑️ Preview cache cleared");
    } catch (e) {
      debugPrint("❌ Failed to clear preview cache: $e");
    }
  }

  // ✅ Opens an already-downloaded file like preview
  /// [path] - The current file to preview
  /// [allPaths] - Optional list of all file paths for swipe navigation
  /// [currentIndex] - Index of current file in allPaths
  static Future<void> openLocalPreview(
    BuildContext context,
    String path, {
    List<String>? allPaths,
    int currentIndex = 0,
  }) async {
    if (!File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("File not found")),
      );
      return;
    }

    _showMediaPreviewDialog(context, path, allPaths: allPaths, currentIndex: currentIndex);
  }

  static String generateTimestampFilename(String prefix, String ext) {
    final now = DateTime.now();
    final formatted = "${now.year}${now.month.toString().padLeft(2, '0')}"
        "${now.day.toString().padLeft(2, '0')}_"
        "${now.hour.toString().padLeft(2, '0')}"
        "${now.minute.toString().padLeft(2, '0')}"
        "${now.second.toString().padLeft(2, '0')}";

    return "${prefix}_$formatted.$ext";
  }

  static String _safeExtensionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? '';
    final ext = path.split('.').last.toLowerCase();
    if (ext.contains('png')) return 'png';
    if (ext.contains('jpg') || ext.contains('jpeg')) return 'jpg';
    if (ext.contains('mp4')) return 'mp4';
    return 'png';
  }

  /// 🔍 Check if URL is the old download endpoint (should not be used)
  static bool _isOldDownloadEndpoint(String? url) {
    if (url == null || url.isEmpty) return false;
    return url.contains('/download/') && !url.contains('workers.dev');
  }

  /// 🔍 Validate downloaded image/video content
  static bool _isValidContent(Uint8List bytes, String extension) {
    if (bytes.isEmpty) {
      debugPrint('❌ Downloaded file is empty');
      return false;
    }

    // Minimum file size check (blank/black images are usually very small)
    if (bytes.length < 100) {
      debugPrint('❌ Downloaded file too small: ${bytes.length} bytes');
      return false;
    }

    // Check for valid image headers
    if (extension.toLowerCase() == 'png') {
      // PNG signature: 89 50 4E 47 0D 0A 1A 0A
      if (bytes.length < 8) return false;
      final pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      for (int i = 0; i < 8; i++) {
        if (bytes[i] != pngSignature[i]) return false;
      }
    } else if (extension.toLowerCase() == 'jpg' || extension.toLowerCase() == 'jpeg') {
      // JPEG signature: FF D8 FF
      if (bytes.length < 3) return false;
      if (bytes[0] != 0xFF || bytes[1] != 0xD8 || bytes[2] != 0xFF) {
        return false;
      }
    } else if (extension.toLowerCase() == 'mp4') {
      // MP4 signature: files start with 4-byte size, then box type
      // Common box types: 'ftyp' (file type), 'moov' (movie header), 'mdat' (media data)
      // Some MP4s might have 'mdat' first (fast start), or 'moov' first
      if (bytes.length < 12) return false;
      
      // Check for MP4 box signature at offset 4 (after 4-byte size)
      final boxType = String.fromCharCodes(bytes.sublist(4, 8));
      final validBoxTypes = ['ftyp', 'moov', 'mdat', 'free', 'skip', 'wide'];
      
      // Also check if it's a valid MP4 by looking for common patterns
      // Some MP4s might have 'mdat' at the start (fast start encoding)
      bool isValidMp4 = validBoxTypes.contains(boxType);
      
      // If not found at offset 4, check offset 0 (some files might not have size prefix)
      if (!isValidMp4 && bytes.length >= 8) {
        final altBoxType = String.fromCharCodes(bytes.sublist(0, 4));
        isValidMp4 = validBoxTypes.contains(altBoxType);
      }
      
      // Additional check: look for 'mp4' string anywhere in first 100 bytes
      if (!isValidMp4 && bytes.length >= 100) {
        final headerString = String.fromCharCodes(bytes.sublist(0, 100));
        isValidMp4 = headerString.contains('mp4') || 
                     headerString.contains('isom') || 
                     headerString.contains('avc1');
      }
      
      if (!isValidMp4) {
        debugPrint('❌ MP4 validation failed: boxType=$boxType, first 20 bytes: ${bytes.sublist(0, bytes.length < 20 ? bytes.length : 20).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        return false;
      }
    }

    return true;
  }

  /// 🧩 Download file (image/video) from [url] and save to gallery, with progress callback.
  /// Includes retry logic and content validation.
  static Future<String?> downloadFromUrl(
    BuildContext context,
    String url, {
    String? suggestedFileName,
    String subfolder = 'Kala_AI',
    void Function(double progress)? onProgress, // progress: 0.0 → 1.0
    int maxRetries = 3,
  }) async {
    // 🔐 Safety check: reject old download endpoint URLs
    if (_isOldDownloadEndpoint(url)) {
      debugPrint('❌ Rejected old download endpoint URL: $url');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid download URL. Please refresh the job.')),
        );
      }
      return null;
    }

    final uri = Uri.parse(url);
    final safeExt = _safeExtensionFromUrl(url);
    http.Client? client;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          // Exponential backoff: 1s, 2s, 4s
          final delay = Duration(seconds: 1 << (attempt - 1));
          debugPrint('⏳ Retrying download in ${delay.inSeconds}s (attempt ${attempt + 1}/$maxRetries)');
          await Future.delayed(delay);
        }

        client = http.Client();
        final request = http.Request('GET', uri);
        
        // Add timeout: 30 seconds for connection, 60 seconds total
        final response = await client.send(request).timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            throw Exception('Download timeout after 60 seconds');
          },
        );

        if (response.statusCode == 403) {
          // URL expired or invalid signature
          throw Exception('URL expired or invalid. Please refresh.');
        }

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception('Server responded ${response.statusCode}');
        }

        final totalBytes = response.contentLength ?? 0;
        final bytes = <int>[];
        int downloaded = 0;

        try {
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 90),
          )) {
            bytes.addAll(chunk);
            downloaded += chunk.length;
            if (totalBytes > 0 && onProgress != null) {
              onProgress(downloaded / totalBytes);
            }
          }
        } on TimeoutException {
          throw Exception('Download stream timeout after 90 seconds');
        }

        // Validate downloaded content
        final fileData = Uint8List.fromList(bytes);
        if (!_isValidContent(fileData, safeExt)) {
          if (attempt < maxRetries - 1) {
            debugPrint('⚠️ Invalid content detected, retrying...');
            client.close();
            continue; // Retry
          } else {
            throw Exception('Downloaded file appears to be invalid or corrupted');
          }
        }

        final uuid = const Uuid().v4();
        final baseName = (suggestedFileName?.trim().isNotEmpty ?? false)
            ? suggestedFileName!
            : uuid;
        final cleanName = _normalizeFileName(baseName, defaultExt: safeExt);
        
        final savedPath = await saveFile(
          context,
          fileData,
          extension: safeExt,
          showPreview: true,
          customFileName: cleanName,
        );

        if (savedPath != null) {
          final jobs = List<JobModel>.from(jobListNotifier.value);
          final idx = jobs.indexWhere((j) => j.downloadUrl == url);
          if (idx != -1) {
            final job = jobs[idx];
            job.localFilePath = savedPath;
            jobs[idx] = job;
            jobListNotifier.value = jobs;
            await saveJobsToPrefs();
            debugPrint("📸 Linked downloaded file to job ${job.jobId}");
          }
          return savedPath;
        }
        return null;
      } catch (e) {
        debugPrint('❌ Download attempt ${attempt + 1} failed: $e');
        
        if (client != null) {
          try {
            client.close();
          } catch (_) {}
        }

        // If this was the last attempt, show error (debounced)
        if (attempt == maxRetries - 1) {
          String errorMsg = 'Download failed';
          if (e.toString().contains('timeout')) {
            errorMsg = 'Download timed out. Please try again.';
          } else if (e.toString().contains('expired') || e.toString().contains('403')) {
            errorMsg = 'Download URL expired. Refreshing...';
          } else if (e.toString().contains('invalid') || e.toString().contains('corrupted')) {
            errorMsg = 'Downloaded file is invalid. Please try again.';
          }
          
          // Use debounced snackbar to prevent spam
          _showDebouncedSnackbar(context, errorMsg, duration: const Duration(seconds: 4));
          return null;
        }
        // Otherwise, continue to next retry
      }
    }

    return null;
  }

  /// Writes bytes to a temporary file (e.g., previews)
  static Future<File> writeTempFile(Uint8List bytes, String name) async {
    final dir = await getTemporaryDirectory();
    final cleanName = _normalizeFileName(name);
    final file = File('${dir.path}/$cleanName');
    await file.writeAsBytes(bytes);

    if (!_cleanupStarted) {
      _cleanupStarted = true;
      _cleanupOldTempFiles();
    }
    return file;
  }

  /// 🧹 Cleanup old temp files (>24 hours)
  static Future<void> _cleanupOldTempFiles() async {
    try {
      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) return;
      final now = DateTime.now();
      int deleted = 0;

      for (final entity in dir.listSync()) {
        if (entity is File) {
          final stat = await entity.stat();
          if (now.difference(stat.modified).inHours > 24) {
            await entity.delete();
            deleted++;
          }
        }
      }
      debugPrint('🧹 Cleaned $deleted old temp files.');
    } catch (e) {
      debugPrint('⚠️ Cleanup failed: $e');
    }
  }

  static Future<void> deleteJobFiles(
    JobModel job, {
    bool deleteGalleryFile = false, // 🆕 new parameter
  }) async {
    try {
      // 🗑️ Delete only preview/cache files always
      if (_previewCache.containsKey(job.jobId)) {
        final previewPath = _previewCache[job.jobId];
        if (previewPath != null && File(previewPath).existsSync()) {
          await File(previewPath).delete();
          debugPrint('🧹 Deleted preview cache file: $previewPath');
        }
        _previewCache.remove(job.jobId);
        await _savePreviewCache();
      }

      // 🗂️ Optionally delete gallery result if user checked box
      if (deleteGalleryFile &&
          job.localFilePath != null &&
          File(job.localFilePath!).existsSync()) {
        await File(job.localFilePath!).delete();
        debugPrint('🗑️ Deleted result (gallery) file: ${job.localFilePath}');
      }

      debugPrint(
          '✅ Job cleanup done (deleteGalleryFile=$deleteGalleryFile) for ${job.jobId}');
    } catch (e) {
      debugPrint('⚠️ Failed to delete files for ${job.jobId}: $e');
    }
  }

  /// 🪄 Premium floating notification with preview + open option
  /// Replaces any existing snackbar to prevent stacking
  static void _showSavedBottomSheet(
    BuildContext context,
    Uint8List bytes,
    String filePath,
    Uint8List? previewBytes,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isVideo = filePath.toLowerCase().endsWith(".mp4");
    final fileName = filePath.split('/').last;

    // Clear any existing snackbars to prevent stacking
    ScaffoldMessenger.of(context).clearSnackBars();

    // Show a premium styled snackbar with preview
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: EdgeInsets.zero,
        content: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.surfaceContainerHighest,
                cs.surfaceContainerHigh,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: cs.outlineVariant.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: cs.primary.withOpacity(0.08),
                blurRadius: 30,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Preview thumbnail with border
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.green.withOpacity(0.4),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: isVideo
                        ? (previewBytes != null
                            ? Image.memory(
                                previewBytes,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.medium,
                              )
                            : Container(
                                width: 56,
                                height: 56,
                                color: cs.surfaceContainerHighest,
                                child: Icon(
                                  Icons.videocam_rounded,
                                  color: cs.onSurfaceVariant,
                                  size: 28,
                                ),
                              ))
                        : Image.memory(
                            bytes,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                
                // Text content
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Success badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: Colors.green.shade400,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Saved to Gallery',
                              style: TextStyle(
                                color: Colors.green.shade400,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // File name
                      Text(
                        fileName,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                
                // Open button
                Material(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () async => await OpenFilex.open(filePath),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_open_rounded,
                            size: 18,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Open',
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Progressive image preview widget
/// Shows a low-res thumbnail first, then loads full resolution in background
class _ProgressiveImagePreview extends StatefulWidget {
  final String filePath;
  final VoidCallback onClose;

  const _ProgressiveImagePreview({
    required this.filePath,
    required this.onClose,
  });

  @override
  State<_ProgressiveImagePreview> createState() => _ProgressiveImagePreviewState();
}

class _ProgressiveImagePreviewState extends State<_ProgressiveImagePreview> 
    with SingleTickerProviderStateMixin {
  Uint8List? _thumbnailBytes;
  bool _isFullResLoaded = false;
  bool _isLoading = true;
  bool _showControls = true;
  String? _fileSize;
  String? _resolution;

  // Screen-aware cache dimensions for full res
  int? _cacheWidth;
  int? _cacheHeight;
  
  late AnimationController _controlsAnimController;
  late Animation<double> _controlsAnimation;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
    _loadFileInfo();
    
    _controlsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
    _controlsAnimation = CurvedAnimation(
      parent: _controlsAnimController,
      curve: Curves.easeOutCubic,
    );
  }
  
  @override
  void dispose() {
    _controlsAnimController.dispose();
    super.dispose();
  }
  
  Future<void> _loadFileInfo() async {
    try {
      final file = File(widget.filePath);
      if (file.existsSync()) {
        final size = await file.length();
        final sizeStr = _formatFileSize(size);
        
        // Get image dimensions
        final bytes = await file.readAsBytes();
        final decoded = await decodeImageFromList(bytes);
        
        if (mounted) {
          setState(() {
            _fileSize = sizeStr;
            _resolution = '${decoded.width} × ${decoded.height}';
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load file info: $e');
    }
  }
  
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _loadThumbnail() async {
    try {
      // Load cached thumbnail first (fast)
      final thumb = await ThumbnailService.instance.getThumbnail(
        widget.filePath,
        size: 400, // Larger thumbnail for preview placeholder
        quality: 70,
      );
      
      if (mounted) {
        setState(() {
          _thumbnailBytes = thumb;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load preview thumbnail: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Calculate cache dimensions based on screen size and quality setting
    final size = MediaQuery.of(context).size;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    
    if (AppSettings.highQualityPreviews) {
      // High quality: 1.5x screen resolution, up to 4K
      _cacheWidth = (size.width * dpr * 1.5).toInt().clamp(0, 4096);
      _cacheHeight = (size.height * dpr * 1.5).toInt().clamp(0, 4096);
    } else {
      // Low quality: 1x screen resolution, max 2K - uses less memory/data
      _cacheWidth = (size.width * dpr).toInt().clamp(0, 2048);
      _cacheHeight = (size.height * dpr).toInt().clamp(0, 2048);
    }
  }
  
  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _controlsAnimController.forward();
      } else {
        _controlsAnimController.reverse();
      }
    });
  }
  
  String get _fileName {
    final path = widget.filePath;
    return path.split('/').last.split('\\').last;
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 🌌 Gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  Color(0xFF1a1a2e),
                  Color(0xFF0d0d14),
                  Colors.black,
                ],
                stops: [0.0, 0.6, 1.0],
              ),
            ),
          ),
          
          // 🖼️ Zoomable Image with progressive loading
          GestureDetector(
            onTap: _toggleControls,
            child: Center(
              child: InteractiveViewer(
                maxScale: 5,
                minScale: 0.7,
                child: _buildImage(),
              ),
            ),
          ),

          // Loading indicator overlay
          if (_isLoading)
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 3,
                ),
              ),
            ),

          // 🔝 Top action bar with frosted glass effect
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _controlsAnimation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -1),
                  end: Offset.zero,
                ).animate(_controlsAnimation),
                child: Container(
                  padding: EdgeInsets.only(
                    top: topPadding + 8,
                    left: 8,
                    right: 8,
                    bottom: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.black.withOpacity(0.4),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                  child: Row(
                    children: [
                      const Spacer(),
                      // Close button on top right
                      _buildActionButton(
                        icon: Icons.close_rounded,
                        onTap: widget.onClose,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // 📊 Bottom info bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _controlsAnimation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(_controlsAnimation),
                child: Container(
                  padding: EdgeInsets.only(
                    top: 16,
                    left: 20,
                    right: 20,
                    bottom: bottomPadding + 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.8),
                        Colors.black.withOpacity(0.5),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.6, 1.0],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // File name
                      Text(
                        _fileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // File info row
                      Row(
                        children: [
                          if (_resolution != null) ...[
                            _buildInfoChip(
                              icon: Icons.aspect_ratio_rounded,
                              label: _resolution!,
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (_fileSize != null)
                            _buildInfoChip(
                              icon: Icons.storage_rounded,
                              label: _fileSize!,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Tap hint (shows briefly)
          if (_showControls && !_isLoading)
            Positioned(
              bottom: bottomPadding + 90,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _controlsAnimation,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Tap to hide controls • Pinch to zoom',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildInfoChip({required IconData icon, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: Colors.white54,
          size: 14,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildImage() {
    final file = File(widget.filePath);
    
    if (!file.existsSync()) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.broken_image_rounded,
              color: Colors.white38,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Image not found',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      );
    }

    // Use Image.file with cacheWidth/cacheHeight for memory efficiency
    // This prevents loading 20MB images at full resolution
    return Image.file(
      file,
      fit: BoxFit.contain,
      cacheWidth: _cacheWidth,
      cacheHeight: _cacheHeight,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        // If loaded synchronously (cached), show immediately
        if (wasSynchronouslyLoaded || frame != null) {
          // Mark as loaded to hide loading indicator
          if (!_isFullResLoaded && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isFullResLoaded = true);
            });
          }
          return child;
        }
        
        // Show thumbnail while full image loads
        if (_thumbnailBytes != null) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Blurred thumbnail as placeholder
              Image.memory(
                _thumbnailBytes!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.low,
              ),
              // Subtle loading indicator
              Positioned(
                bottom: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Loading full resolution...',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        
        // Fallback loading state
        return Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const CircularProgressIndicator(
              color: Colors.white70,
              strokeWidth: 3,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('❌ Preview image error: $error');
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Colors.red,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load image',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Swipeable media preview widget for navigating between multiple downloaded results
class _SwipeableMediaPreview extends StatefulWidget {
  final List<String> filePaths;
  final int initialIndex;
  final VoidCallback onClose;

  const _SwipeableMediaPreview({
    required this.filePaths,
    required this.initialIndex,
    required this.onClose,
  });

  @override
  State<_SwipeableMediaPreview> createState() => _SwipeableMediaPreviewState();
}

class _SwipeableMediaPreviewState extends State<_SwipeableMediaPreview>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  bool _showControls = true;
  
  late AnimationController _controlsAnimController;
  late Animation<double> _controlsAnimation;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    
    _controlsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
    _controlsAnimation = CurvedAnimation(
      parent: _controlsAnimController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _controlsAnimController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _controlsAnimController.forward();
      } else {
        _controlsAnimController.reverse();
      }
    });
  }

  bool _isVideo(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') || 
           lower.endsWith('.mov') || 
           lower.endsWith('.avi') ||
           lower.endsWith('.webm');
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 🌌 Gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  Color(0xFF1a1a2e),
                  Color(0xFF0d0d14),
                  Colors.black,
                ],
                stops: [0.0, 0.6, 1.0],
              ),
            ),
          ),
          
          // 🖼️ PageView for swipe navigation
          GestureDetector(
            onTap: _toggleControls,
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.filePaths.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                final path = widget.filePaths[index];
                if (_isVideo(path)) {
                  return _VideoPreviewItem(filePath: path);
                } else {
                  return _ImagePreviewItem(filePath: path);
                }
              },
            ),
          ),

          // 🔝 Top action bar with frosted glass effect
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _controlsAnimation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -1),
                  end: Offset.zero,
                ).animate(_controlsAnimation),
                child: Container(
                  padding: EdgeInsets.only(
                    top: topPadding + 8,
                    left: 16,
                    right: 8,
                    bottom: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.black.withOpacity(0.4),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                  child: Row(
                    children: [
                      // Page indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${_currentIndex + 1} / ${widget.filePaths.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Close button on top right
                      _buildActionButton(
                        icon: Icons.close_rounded,
                        onTap: widget.onClose,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // 📍 Page dots indicator at bottom
          Positioned(
            bottom: bottomPadding + 16,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _controlsAnimation,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Left arrow
                      if (_currentIndex > 0)
                        GestureDetector(
                          onTap: () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Icon(
                              Icons.chevron_left_rounded,
                              color: Colors.white70,
                              size: 24,
                            ),
                          ),
                        ),
                      // Dots
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          widget.filePaths.length.clamp(0, 10), // Max 10 dots
                          (index) {
                            final isActive = index == _currentIndex;
                            final showDots = widget.filePaths.length <= 10 ||
                                (index >= _currentIndex - 4 && index <= _currentIndex + 4);
                            if (!showDots && widget.filePaths.length > 10) {
                              if (index == 0 || index == widget.filePaths.length - 1) {
                                return Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            }
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: isActive ? 20 : 8,
                              height: 8,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: isActive
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.4),
                              ),
                            );
                          },
                        ),
                      ),
                      // Right arrow
                      if (_currentIndex < widget.filePaths.length - 1)
                        GestureDetector(
                          onTap: () {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.only(left: 12),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white70,
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Swipe hint
          if (_showControls && widget.filePaths.length > 1)
            Positioned(
              bottom: bottomPadding + 80,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _controlsAnimation,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Swipe to browse • Pinch to zoom',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

/// Individual image preview item for PageView
class _ImagePreviewItem extends StatefulWidget {
  final String filePath;

  const _ImagePreviewItem({required this.filePath});

  @override
  State<_ImagePreviewItem> createState() => _ImagePreviewItemState();
}

class _ImagePreviewItemState extends State<_ImagePreviewItem> {
  int? _cacheWidth;
  int? _cacheHeight;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.of(context).size;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    
    if (AppSettings.highQualityPreviews) {
      _cacheWidth = (size.width * dpr * 1.5).toInt().clamp(0, 4096);
      _cacheHeight = (size.height * dpr * 1.5).toInt().clamp(0, 4096);
    } else {
      _cacheWidth = (size.width * dpr).toInt().clamp(0, 2048);
      _cacheHeight = (size.height * dpr).toInt().clamp(0, 2048);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.filePath);
    
    if (!file.existsSync()) {
      return const Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: Colors.white38,
          size: 48,
        ),
      );
    }

    return Center(
      child: InteractiveViewer(
        maxScale: 5,
        minScale: 0.7,
        child: Image.file(
          file,
          fit: BoxFit.contain,
          cacheWidth: _cacheWidth,
          cacheHeight: _cacheHeight,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(
                Icons.error_outline_rounded,
                color: Colors.red,
                size: 48,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Individual video preview item for PageView
class _VideoPreviewItem extends StatefulWidget {
  final String filePath;

  const _VideoPreviewItem({required this.filePath});

  @override
  State<_VideoPreviewItem> createState() => _VideoPreviewItemState();
}

class _VideoPreviewItemState extends State<_VideoPreviewItem> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _fileSize;
  String? _dimensions;
  String? _format;
  
  @override
  void initState() {
    super.initState();
    _loadVideoInfo();
    _initializeVideo();
  }

  Future<void> _loadVideoInfo() async {
    try {
      final file = File(widget.filePath);
      if (!file.existsSync()) return;

      // Get file size
      final sizeBytes = await file.length();
      final sizeMB = sizeBytes / (1024 * 1024);
      _fileSize = sizeMB.toStringAsFixed(2);

      // Get format from extension
      final ext = widget.filePath.split('.').last.toLowerCase();
      _format = ext.toUpperCase();

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load video info: $e');
    }
  }

  Future<void> _initializeVideo() async {
    try {
      final file = File(widget.filePath);
      if (!file.existsSync()) return;

      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();
      await _controller!.setLooping(true);
      
      // Get dimensions
      if (_controller!.value.size.width > 0 && _controller!.value.size.height > 0) {
        _dimensions = '${_controller!.value.size.width.toInt()} × ${_controller!.value.size.height.toInt()}';
      }
      
      // Listen to position changes
      _controller!.addListener(_updatePosition);
      _duration = _controller!.value.duration;
      
      // Auto-hide controls after 3 seconds
      _hideControlsAfterDelay();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('❌ Failed to initialize video: $e');
    }
  }

  void _updatePosition() {
    if (_controller == null) return;
    if (mounted) {
      setState(() {
        _position = _controller!.value.position;
        _duration = _controller!.value.duration;
        _isPlaying = _controller!.value.isPlaying;
      });
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;

    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _isPlaying = false;
      } else {
        _controller!.play();
        _isPlaying = true;
      }
      _showControls = true;
    });
    _hideControlsAfterDelay();
  }

  void _seekTo(Duration position) {
    if (_controller == null || !_isInitialized) return;
    _controller!.seekTo(position);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _hideControlsAfterDelay();
    }
  }

  void _hideControlsAfterDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_updatePosition);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const CircularProgressIndicator(
                color: Colors.white70,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Loading video...',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video player
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
          
          // Controls overlay
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                  stops: const [0.0, 0.2, 0.7, 1.0],
                ),
              ),
              child: Stack(
                children: [
                  // Top info bar
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _buildVideoInfo(),
                      ),
                    ),
                  ),
                  
                  // Centered play/pause button (like standard video players)
                  // Only show when controls are visible and video is paused, or when tapping to pause
                  if (_showControls || !_isPlaying)
                    Center(
                      child: GestureDetector(
                        onTap: _togglePlayPause,
                        child: AnimatedOpacity(
                          opacity: _showControls ? 1.0 : 0.6,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.4),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                    ),
                  
                  // Bottom controls - seek bar and time positioned above "Swipe to browse" label
                  Positioned(
                    bottom: MediaQuery.of(context).padding.bottom + 100, // Above the "Swipe to browse" label
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Seek bar with time on sides
                          Row(
                            children: [
                              // Current time (left side)
                              Text(
                                _formatDuration(_position),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Seek bar (expanded)
                              Expanded(
                                child: _buildSeekBar(),
                              ),
                              const SizedBox(width: 12),
                              // Total duration (right side)
                              Text(
                                _formatDuration(_duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeekBar() {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            if (_controller == null || _duration.inMilliseconds == 0) return;
            final x = details.localPosition.dx;
            final width = constraints.maxWidth;
            final newPosition = (x / width).clamp(0.0, 1.0) * _duration.inMilliseconds;
            _seekTo(Duration(milliseconds: newPosition.toInt()));
          },
          child: Container(
            height: 32, // Larger touch target
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Background track
                Container(
                  height: 4,
                  width: constraints.maxWidth,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Progress track
                Container(
                  height: 4,
                  width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Thumb
                Positioned(
                  left: (constraints.maxWidth * progress.clamp(0.0, 1.0)) - 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        alignment: WrapAlignment.start,
        children: [
          if (_dimensions != null)
            _buildInfoChip(
              icon: Icons.aspect_ratio_rounded,
              label: _dimensions!,
            ),
          if (_fileSize != null)
            _buildInfoChip(
              icon: Icons.storage_rounded,
              label: '$_fileSize MB',
            ),
          if (_format != null)
            _buildInfoChip(
              icon: Icons.video_file_rounded,
              label: _format!,
            ),
          if (_duration.inSeconds > 0)
            _buildInfoChip(
              icon: Icons.timer_rounded,
              label: _formatDuration(_duration),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Colors.white.withOpacity(0.8),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Internal class to represent a queued download task
class _DownloadTask {
  final BuildContext context;
  final String url;
  final String? suggestedFileName;
  final String subfolder;
  final void Function(double progress)? onProgress;
  final int maxRetries;
  final Completer<String?> completer;

  _DownloadTask({
    required this.context,
    required this.url,
    this.suggestedFileName,
    required this.subfolder,
    this.onProgress,
    required this.maxRetries,
    required this.completer,
  });
}
