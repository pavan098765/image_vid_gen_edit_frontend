import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FileService {
  static bool _isSaving = false;
  static String? _lastSavedHash;
  static bool _cleanupStarted = false;
  static final Map<String, String> _previewCache =
      {}; // jobId/url → local file path

  /// 🚀 Save raw bytes (image/video) to the gallery.
  static Future<String?> saveFile(
    BuildContext context,
    Uint8List bytes, {
    String subfolder = 'AI_Creative_Studio',
    String? prefix,
    String extension = 'png',
    bool showPreview = true,
  }) async {
    final currentHash = sha1.convert(bytes).toString();

    if (currentHash == _lastSavedHash) {
      debugPrint('⚠️ Skipping duplicate save (same content)');
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

      final fileName =
          '${prefix ?? 'file'}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      await Gal.putImageBytes(
        bytes,
        album: subfolder,
        name: fileName,
      );

      final Directory baseDir = Directory('/storage/emulated/0/Pictures');
      final saveDir = Directory('${baseDir.path}/$subfolder');
      final filePath = '${saveDir.path}/$fileName';

      if (context.mounted && showPreview) {
        _showSavedBottomSheet(context, bytes, filePath);
      }

      debugPrint('✅ Saved file: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('❌ Save error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
      return null;
    } finally {
      _isSaving = false;
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

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            // 🖼️ Zoomable image
            InteractiveViewer(
              maxScale: 5.0,
              minScale: 0.8,
              child: Image.file(
                File(filePath),
                fit: BoxFit.contain,
              ),
            ),
            // ❌ Close button
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
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
      final uri = Uri.parse(url);
      final path = uri.path;
      String extension = 'png'; // default

      final segments = path.split('/');
      final lastSegment = segments.isNotEmpty ? segments.last : '';

      if (lastSegment.contains('.')) {
        extension = lastSegment.split('.').last.split('?').first.toLowerCase();
      }
      final hash = sha1.convert(utf8.encode(cacheKey)).toString();
      final fileName = 'preview_$hash.$extension';

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

  /// 🧩 Download file (image/video) from [url] and save to gallery.
  static Future<void> downloadFromUrl(
    BuildContext context,
    String url, {
    String? fileName,
    String subfolder = 'AI_Creative_Studio',
  }) async {
    try {
      final uri = Uri.parse(url);
      final extension = uri.path
          .split('.')
          .last
          .toLowerCase()
          .replaceAll(RegExp(r'\?.*'), '');
      final safeExt = (extension.isEmpty) ? 'png' : extension;

      final request = http.Request('GET', uri);
      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception('Server responded ${response.statusCode}');
      }

      final bytes = await response.stream.toBytes();
      final savedPath = await saveFile(
        context,
        bytes,
        prefix: fileName ?? 'download',
        extension: safeExt,
      );

      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ File saved to: $savedPath'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Download failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  /// Writes bytes to a temporary file (e.g., previews)
  static Future<File> writeTempFile(Uint8List bytes, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
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

  static Future<void> deleteJobFiles(String jobId) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final hash = sha1.convert(utf8.encode(jobId)).toString();
      final previewFile = File('${tempDir.path}/preview_$hash.png');

      if (await previewFile.exists()) {
        await previewFile.delete();
        debugPrint('🗑️ Deleted preview file for job $jobId');
      }

      // remove from in-memory + persisted cache
      _previewCache.remove(jobId);
      await _savePreviewCache();
    } catch (e) {
      debugPrint('⚠️ Failed to delete files for $jobId: $e');
    }
  }

  /// 🪄 Bottom sheet confirmation with preview + open option
  static void _showSavedBottomSheet(
      BuildContext context, Uint8List bytes, String filePath) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.9),
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
              child:
                  Image.memory(bytes, width: 60, height: 60, fit: BoxFit.cover),
            ),
            title: const Text(
              '✅ Saved successfully!',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              filePath,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.folder_open, color: Colors.white),
              onPressed: () async => await OpenFilex.open(filePath),
            ),
          ),
        ),
      ),
    );
  }
}
