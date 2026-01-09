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
        _showSavedBottomSheet(context, bytes, filePath, previewBytes);
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
      final saved = await saveFile(context, bytes);
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
  static Future<void> openLocalPreview(
    BuildContext context,
    String path,
  ) async {
    if (!File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("File not found")),
      );
      return;
    }

    _showImageDialog(context, path);
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
      // MP4 signature: ftyp box at start (bytes 4-8 should contain 'ftyp')
      if (bytes.length < 12) return false;
      final ftyp = String.fromCharCodes(bytes.sublist(4, 8));
      if (ftyp != 'ftyp') {
        // Check for alternative MP4 signatures
        final boxType = String.fromCharCodes(bytes.sublist(4, 8));
        if (boxType != 'ftyp' && boxType != 'moov' && boxType != 'mdat') {
          return false;
        }
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
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  const Color(0xFF1a1a2e),
                  const Color(0xFF0d0d14),
                  Colors.black,
                ],
                stops: const [0.0, 0.6, 1.0],
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
                      // Close button with pill background
                      _buildActionButton(
                        icon: Icons.close_rounded,
                        onTap: widget.onClose,
                        tooltip: 'Close',
                      ),
                      const Spacer(),
                      // Save to gallery button
                      _buildActionButton(
                        icon: Icons.save_alt_rounded,
                        onTap: () => _saveToGallery(context),
                        tooltip: 'Save to Gallery',
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
  
  Future<void> _saveToGallery(BuildContext context) async {
    try {
      final saved = await FileService.saveExistingToGallery(
        context,
        widget.filePath,
      );
      if (saved && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Text('Saved to gallery'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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
