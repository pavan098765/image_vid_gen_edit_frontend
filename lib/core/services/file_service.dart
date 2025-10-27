import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:crypto/crypto.dart';

class FileService {
  static bool _isSaving = false;
  static String? _lastSavedHash; // remembers last image hash

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
      final Directory baseDir = Directory('/storage/emulated/0/Pictures');
      final saveDir = Directory('${baseDir.path}/$subfolder');

      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final filePath =
          '${saveDir.path}/${prefix ?? 'edit'}_$timestamp.$extension';

      final file = File(filePath);
      await file.writeAsBytes(bytes);

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
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
