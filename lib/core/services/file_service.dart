import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:gal/gal.dart';

class FileService {
  static bool _isSaving = false;
  static String? _lastSavedHash; // remembers last image hash
  static bool _cleanupStarted = false; // ensures cleanup runs only once per session

  /// Saves [bytes] to gallery via `gal` (refreshes instantly in Gallery app)
  /// and also returns the absolute file path for reference or reuse.
  static Future<String?> saveFile(
    BuildContext context,
    Uint8List bytes, {
    String subfolder = 'AI_Creative_Studio',
    String? prefix,
    String extension = 'png',
    bool showPreview = true,
  }) async {
    // Compute short hash of bytes
    final currentHash = sha1.convert(bytes).toString();

    // 🔒 Skip duplicate content saves (same image)
    if (currentHash == _lastSavedHash) {
      debugPrint('⚠️ Skipping duplicate save: identical image hash.');
      return null;
    }

    if (_isSaving) {
      debugPrint('⚠️ Save already in progress — skipping.');
      return null;
    }

    _isSaving = true;
    _lastSavedHash = currentHash;

    try {
      // ✅ Request permission before saving
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

      // ✅ Save image to Gallery (appears instantly)
      final fileName =
          '${prefix ?? 'edit'}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      await Gal.putImageBytes(
        bytes,
        album: subfolder,
        name: fileName,
      );

      // ✅ Build expected absolute file path (for return)
      final Directory baseDir = Directory('/storage/emulated/0/Pictures');
      final saveDir = Directory('${baseDir.path}/$subfolder');
      final filePath = '${saveDir.path}/$fileName';

      // ✅ Show confirmation bottom sheet
      if (context.mounted && showPreview) {
        _showSavedBottomSheet(context, bytes, filePath);
      }

      debugPrint('✅ Saved file: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('❌ Error saving file: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
      return null;
    } finally {
      _isSaving = false;
    }
  }

  /// Writes bytes to a temporary file for internal use.
  /// Also triggers background cleanup of older temp files (older than 24 hours).
  static Future<File> writeTempFile(Uint8List bytes, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);

    // Start cleanup asynchronously — only runs once per app session.
    if (!_cleanupStarted) {
      _cleanupStarted = true;
      _cleanupOldTempFiles();
    }

    return file;
  }

  /// Background cleanup for temp files older than 1 day (24h).
  static Future<void> _cleanupOldTempFiles() async {
    try {
      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) return;

      final now = DateTime.now();
      final files = dir.listSync();

      int deletedCount = 0;
      for (final entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);
          if (age.inHours > 24) {
            await entity.delete();
            deletedCount++;
          }
        }
      }

      debugPrint('🧹 Temp cleanup complete — deleted $deletedCount old files.');
    } catch (e) {
      debugPrint('⚠️ Temp cleanup failed: $e');
    }
  }

  /// Bottom sheet showing preview + open option
  static void _showSavedBottomSheet(
      BuildContext context, Uint8List bytes, String filePath) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.9),
      isScrollControlled: true,
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
              child: Image.memory(
                bytes,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
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
              onPressed: () async {
                await OpenFilex.open(filePath);
              },
            ),
          ),
        ),
      ),
    );
  }
}
