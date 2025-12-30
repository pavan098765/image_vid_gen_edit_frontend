import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_vid_gen_edit_frontend/core/app_state.dart';
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

  static Future<Directory> getTempDir() async => await getTemporaryDirectory();

  /// 🚀 Save raw bytes (image/video) to the gallery.
  static Future<String?> saveFile(
    BuildContext context,
    Uint8List bytes, {
    String? customFileName,
    String subfolder = 'AI_Creative_Studio',
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
      barrierColor: Colors.black.withOpacity(0.95),
      pageBuilder: (_, __, ___) {
        return WillPopScope(
          onWillPop: () async {
            _isPreviewOpen = false;
            return true;
          },
          child: Stack(
            children: [
              // 🖼️ Zoomable Image
              Center(
                child: InteractiveViewer(
                  maxScale: 5,
                  minScale: 0.7,
                  child: Image.file(
                    File(filePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              // ❌ Close button
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: () {
                    _isPreviewOpen = false;
                    Navigator.of(context, rootNavigator: true).pop();
                  },
                ),
              ),
            ],
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
      final cacheKey = uniqueKey ?? url;

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

  /// 🧩 Download file (image/video) from [url] and save to gallery, with progress callback.
  static Future<String?> downloadFromUrl(
    BuildContext context,
    String url, {
    String? suggestedFileName,
    String subfolder = 'AI_Creative_Studio',
    void Function(double progress)? onProgress, // progress: 0.0 → 1.0
  }) async {
    try {
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

      final client = http.Client();
      final request = http.Request('GET', uri);
      final response = await client.send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('Server responded ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      final bytes = <int>[];
      int downloaded = 0;

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        downloaded += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(downloaded / totalBytes);
        }
      }

      final uuid = const Uuid().v4();
      final baseName = (suggestedFileName?.trim().isNotEmpty ?? false)
          ? suggestedFileName!
          : uuid;
      final cleanName = _normalizeFileName(baseName, defaultExt: safeExt);
      final fileData = Uint8List.fromList(bytes);
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
      debugPrint('❌ Download failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
      return null;
    }
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

  /// 🪄 Bottom sheet confirmation with preview + open option
  static void _showSavedBottomSheet(
    BuildContext context,
    Uint8List bytes,
    String filePath,
    Uint8List? previewBytes,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isVideo = filePath.toLowerCase().endsWith(".mp4");

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface.withOpacity(0.98),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        minimum: const EdgeInsets.only(bottom: 24),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isVideo
                  ? (previewBytes != null
                      ? Image.memory(
                          previewBytes,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                        )
                      : Container(
                          width: 60,
                          height: 60,
                          color: cs.surfaceContainerHighest.withOpacity(0.10),
                          child: Icon(
                            Icons.videocam,
                            color: cs.onSurface,
                            size: 28,
                          ),
                        ))
                  : Image.memory(
                      bytes,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    ),
            ),
            title: Text(
              '✅ Saved successfully!',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              filePath,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: Icon(Icons.folder_open, color: cs.primary),
              onPressed: () async => await OpenFilex.open(filePath),
            ),
          ),
        ),
      ),
    );
  }
}
