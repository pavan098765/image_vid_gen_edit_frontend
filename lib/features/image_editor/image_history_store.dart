import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

/// Job-id (or file-hash) keyed ProImageEditor history that survives a second open.
class ImageHistoryStore {
  ImageHistoryStore._();

  static Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/image_histories');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String sanitize(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static String historyIdFor({String? jobId, File? image}) {
    if (jobId != null && jobId.isNotEmpty) return sanitize(jobId);
    if (image != null && image.path.isNotEmpty) {
      final digest = md5.convert(utf8.encode(image.path));
      return digest.toString();
    }
    return 'anon_${DateTime.now().millisecondsSinceEpoch}';
  }

  static Future<File> _file(String historyId) async {
    final dir = await _dir();
    return File('${dir.path}/${sanitize(historyId)}.json');
  }

  static ImportStateHistory? parse(
    String json, {
    Widget Function(String id, {Map<String, dynamic>? meta})? widgetLoader,
  }) {
    try {
      return ImportStateHistory.fromJson(
        json,
        configs: ImportEditorConfigs(widgetLoader: widgetLoader),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<ImportStateHistory?> load(
    String historyId, {
    Widget Function(String id, {Map<String, dynamic>? meta})? widgetLoader,
  }) async {
    try {
      final file = await _file(historyId);
      if (!file.existsSync()) return null;
      return parse(file.readAsStringSync(), widgetLoader: widgetLoader);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String historyId, String json) async {
    final file = await _file(historyId);
    await file.writeAsString(json);
  }

  static Future<void> copyTo(String fromId, String toId) async {
    if (fromId == toId) return;
    final src = await _file(fromId);
    if (!src.existsSync()) return;
    final dst = await _file(toId);
    await dst.writeAsString(src.readAsStringSync());
  }

  static Widget widgetLoader(String id, {Map<String, dynamic>? meta}) {
    final path = (meta?['fileUrl'] as String?) ?? id;
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.contain);
    }
    return const SizedBox(width: 80, height: 80);
  }
}
