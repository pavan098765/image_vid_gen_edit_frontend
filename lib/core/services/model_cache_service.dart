import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelCacheService {
  static const String _toolConfigCacheKey = 'cached_tool_config_v3';
  static const String _toolConfigUrl =
      'https://pub-67f874d172874988b5754734cc4fcb7e.r2.dev/tool_config.json';

  static const String _defaultLamaUrl =
      'https://pub-67f874d172874988b5754734cc4fcb7e.r2.dev/models/lama_dilated.tflite';
  static const String _defaultLamaFileName = 'lama_dilated.tflite';
  static const String _defaultLamaVersion = 'v1';

  static const String _prefsModelPath = 'on_device_lama_model_path';
  static const String _prefsModelVersion = 'on_device_lama_model_version';
  static const String _prefsModelUrl = 'on_device_lama_model_url';
  static const String _prefsModelSha = 'on_device_lama_model_sha256';
  static Future<String>? _inpaintDownloadFuture;

  static Future<String?> getInpaintModelLocalPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefsModelPath);
    if (path == null || path.isEmpty) return null;
    if (!await File(path).exists()) return null;
    return path;
  }

  static Future<void> prefetchInpaintModelInBackground() async {
    try {
      final path = await ensureInpaintModelDownloaded();
      debugPrint('✅ LaMa model cached at: $path');
    } catch (e, st) {
      debugPrint('⚠️ LaMa model prefetch failed: $e');
      debugPrint('$st');
    }
  }

  static Future<String> ensureInpaintModelDownloaded({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final inflight = _inpaintDownloadFuture;
      if (inflight != null) {
        return inflight;
      }
    }

    final future = _ensureInpaintModelDownloadedInternal(forceRefresh: forceRefresh);
    if (!forceRefresh) {
      _inpaintDownloadFuture = future;
    }
    try {
      return await future;
    } finally {
      if (identical(_inpaintDownloadFuture, future)) {
        _inpaintDownloadFuture = null;
      }
    }
  }

  static Future<String> _ensureInpaintModelDownloadedInternal({
    required bool forceRefresh,
  }) async {
    final meta = await _resolveInpaintModelMeta();
    final prefs = await SharedPreferences.getInstance();
    final modelDir = await _getModelDir();
    final outFile = File('${modelDir.path}/${meta.fileName}');

    final savedVersion = prefs.getString(_prefsModelVersion);
    final savedUrl = prefs.getString(_prefsModelUrl);
    final savedSha = prefs.getString(_prefsModelSha);
    final exists = await outFile.exists();

    final sameIdentity = exists &&
        !forceRefresh &&
        savedVersion == meta.version &&
        savedUrl == meta.url;
    if (sameIdentity) {
      if (meta.sha256 == null || meta.sha256!.isEmpty || savedSha == meta.sha256) {
        return outFile.path;
      }
    }

    await _downloadToFile(meta.url, outFile);
    if (meta.sha256 != null && meta.sha256!.isNotEmpty) {
      final actual = await _fileSha256(outFile);
      if (actual != meta.sha256) {
        throw Exception('LaMa SHA mismatch: expected=${meta.sha256} actual=$actual');
      }
    }

    await prefs.setString(_prefsModelPath, outFile.path);
    await prefs.setString(_prefsModelVersion, meta.version);
    await prefs.setString(_prefsModelUrl, meta.url);
    await prefs.setString(_prefsModelSha, meta.sha256 ?? '');
    return outFile.path;
  }

  static Future<Directory> _getModelDir() async {
    final appDir = await getApplicationSupportDirectory();
    final modelDir = Directory('${appDir.path}/models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir;
  }

  static Future<_InpaintModelMeta> _resolveInpaintModelMeta() async {
    Map<String, dynamic>? parsed;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_toolConfigCacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        parsed = jsonDecode(cached) as Map<String, dynamic>;
      } catch (_) {}
    }

    parsed ??= await _fetchToolConfig();
    final fromConfig = _extractInpaintMeta(parsed);
    if (fromConfig != null) return fromConfig;

    return const _InpaintModelMeta(
      url: _defaultLamaUrl,
      fileName: _defaultLamaFileName,
      version: _defaultLamaVersion,
      sha256: null,
    );
  }

  static Future<Map<String, dynamic>?> _fetchToolConfig() async {
    try {
      final resp = await http
          .get(Uri.parse(_toolConfigUrl))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200 || resp.body.isEmpty) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static _InpaintModelMeta? _extractInpaintMeta(Map<String, dynamic>? cfg) {
    if (cfg == null) return null;
    final caps = cfg['capabilities'];
    if (caps is! List) return null;
    for (final cap in caps) {
      if (cap is! Map) continue;
      if ((cap['id'] ?? '').toString() != 'inpaint') continue;
      final models = cap['models'];
      if (models is! List) continue;
      for (final m in models) {
        if (m is! Map) continue;
        if ((m['id'] ?? '').toString() != 'basic_utils') continue;
        final url = (m['onDeviceModelUrl'] ?? '').toString().trim();
        if (url.isEmpty) return null;
        final fileNameRaw = (m['onDeviceModelFileName'] ?? '').toString().trim();
        final fileName =
            fileNameRaw.isNotEmpty ? fileNameRaw : Uri.parse(url).pathSegments.last;
        final versionRaw = (m['onDeviceModelVersion'] ?? '').toString().trim();
        final version = versionRaw.isNotEmpty ? versionRaw : _defaultLamaVersion;
        final sha = (m['onDeviceModelSha256'] ?? '').toString().trim().toLowerCase();
        return _InpaintModelMeta(
          url: url,
          fileName: fileName,
          version: version,
          sha256: sha.isEmpty ? null : sha,
        );
      }
    }
    return null;
  }

  static Future<void> _downloadToFile(String url, File outFile) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final resp = await client
          .send(request)
          .timeout(const Duration(seconds: 90));
      if (resp.statusCode != 200) {
        throw Exception('Model download failed: HTTP ${resp.statusCode}');
      }

      final parent = outFile.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      final tmp = File(
        '${outFile.path}.part.${DateTime.now().microsecondsSinceEpoch}',
      );
      if (await tmp.exists()) {
        await tmp.delete();
      }
      final sink = tmp.openWrite();
      await resp.stream.pipe(sink);
      await sink.close();

      if (!await tmp.exists()) {
        if (await outFile.exists()) return;
        throw Exception('Temporary model file missing before finalize: ${tmp.path}');
      }

      if (await outFile.exists()) {
        await outFile.delete();
      }
      try {
        await tmp.rename(outFile.path);
      } on FileSystemException {
        // Cross-device or transient rename failure fallback.
        if (await outFile.exists()) return;
        final bytes = await tmp.readAsBytes();
        await outFile.writeAsBytes(bytes, flush: true);
        if (await tmp.exists()) {
          await tmp.delete();
        }
      }
    } finally {
      client.close();
    }
  }

  static Future<String> _fileSha256(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString().toLowerCase();
  }
}

class _InpaintModelMeta {
  final String url;
  final String fileName;
  final String version;
  final String? sha256;

  const _InpaintModelMeta({
    required this.url,
    required this.fileName,
    required this.version,
    required this.sha256,
  });
}
