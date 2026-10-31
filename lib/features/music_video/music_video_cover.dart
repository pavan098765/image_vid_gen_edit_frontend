import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kala_ai_create_images_videos_with_ai/core/api/submit_payload_helpers.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/polling_service.dart';
import 'package:path_provider/path_provider.dart';

const String kMusicVideoCoverModelId = 'flux2_klein_9b';
const int kMusicVideoCoverGems = 10;

class MusicVideoCoverException implements Exception {
  final String message;
  const MusicVideoCoverException(this.message);
}

/// Album-cover prompt. Style and lyrics only set the scene. The picture
/// itself has no writing, because the video draws the title.
String musicVideoCoverPrompt({
  required String title,
  required String artist,
  required String lyricSheet,
  String style = '',
}) {
  final mood = _coverMood(style: style, lyricSheet: lyricSheet);
  final scene = mood.isEmpty
      ? 'A single cinematic scene with bold color and dramatic light.'
      : 'A single cinematic scene suggested by this mood, with none of these words painted: $mood.';
  return 'Square album-cover painting. $scene '
      'Detailed lighting, sharp focus, one clear subject. '
      'No text, no letters, no words, no numbers, no logo, no watermark, no typography, no signature, no title.';
}

String _coverMood({required String style, required String lyricSheet}) {
  final direction = style.replaceAll(RegExp(r'\[[^\]]*\]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (direction.isNotEmpty) {
    return direction.length > 180 ? direction.substring(0, 180) : direction;
  }
  final lines = <String>[];
  for (final raw in lyricSheet.split(RegExp(r'\r?\n'))) {
    final text = raw.replaceAll(RegExp(r'\[[^\]]*\]'), '').replaceAll(RegExp(r'[()]'), '').trim();
    if (text.isEmpty) continue;
    lines.add(text);
    if (lines.length == 2) break;
  }
  final theme = lines.join(', ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (theme.isEmpty) return '';
  return theme.length > 80 ? theme.substring(0, 80) : theme;
}

/// Submits Kala Flash and waits for the picture. The phone does not call the
/// image host itself.
Future<Uint8List> generateMusicVideoCover({
  required String parentJobId,
  required String title,
  required String artist,
  required String lyricSheet,
  String style = '',
}) async {
  final token = await AuthService().getIdToken();
  if (token == null || token.isEmpty) {
    throw const MusicVideoCoverException('Sign in to make a cover.');
  }
  final prompt = musicVideoCoverPrompt(
    title: title,
    artist: artist,
    lyricSheet: lyricSheet,
    style: style,
  );
  final payload = buildSubmitPayload(
    modelId: kMusicVideoCoverModelId,
    modelParams: const {'aspect_ratio': '1:1'},
    rootParams: {'prompt': prompt},
    fcmToken: null,
  );
  final response = await http
      .post(
        Uri.parse('https://genedit.mooo.com/submit'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 30));
  if (response.statusCode == 402) {
    throw const MusicVideoCoverException('You need more gems for a new cover.');
  }
  if (response.statusCode >= 400) {
    throw const MusicVideoCoverException('The cover could not be started.');
  }
  final body = jsonDecode(response.body);
  final jobId = body is Map ? body['job_id']?.toString() : null;
  if (jobId == null || jobId.isEmpty) {
    throw const MusicVideoCoverException('The cover could not be started.');
  }
  final job = JobModel(
    jobId: jobId,
    title: title.trim().isEmpty ? 'Album cover' : title.trim(),
    model: kMusicVideoCoverModelId,
    outputType: 'image',
    status: 'processing',
    capabilityId: 'create_image',
    originalPrompt: prompt,
    creditsCharged: kMusicVideoCoverGems,
    parentJobId: parentJobId,
    settingsSnapshot: const {'modelId': kMusicVideoCoverModelId, 'aspect_ratio': '1:1'},
  );
  await addOrUpdateJob(job);

  for (var attempt = 0; attempt < 40; attempt++) {
    await Future<void>.delayed(Duration(seconds: attempt == 0 ? 2 : 3));
    final status = await _jobStatus(jobId, token);
    final state = (status?['status'] ?? '').toString().toLowerCase();
    if (state == 'failed') {
      await addOrUpdateJob(job.copyWith(status: 'failed'));
      throw const MusicVideoCoverException('The cover did not finish.');
    }
    if (state != 'completed') continue;
    final bytes = await _downloadCover(jobId, token, status ?? const {});
    if (bytes == null) {
      throw const MusicVideoCoverException('The cover could not be downloaded.');
    }
    final saved = await _storeCover(jobId, bytes);
    await addOrUpdateJob(job.copyWith(
      status: 'completed',
      readyAt: DateTime.now(),
      localFilePath: saved,
    ));
    return bytes;
  }
  throw const MusicVideoCoverException('The cover is still generating. It will show in your library.');
}

/// The newest finished cover made for this song, if the phone already has it.
Future<Uint8List?> savedMusicVideoCover(String parentJobId) async {
  if (parentJobId.isEmpty) return null;
  JobModel? newest;
  for (final job in jobListNotifier.value) {
    if (job.parentJobId != parentJobId || job.model != kMusicVideoCoverModelId) continue;
    if (job.status != 'completed') continue;
    if (newest == null || job.createdAt.isAfter(newest.createdAt)) newest = job;
  }
  if (newest == null) return null;
  final path = newest.localFilePath;
  if (path != null && path.isNotEmpty && File(path).existsSync()) {
    final bytes = await File(path).readAsBytes();
    if (_isImage(bytes)) return bytes;
  }
  final token = await AuthService().getIdToken();
  if (token == null || token.isEmpty) return null;
  final signed = await PollingService.refreshDownloadUrl(newest.jobId);
  final url = signed == null ? null : _urlFromBody(signed);
  if (url == null) return null;
  return _readHttp(url, token);
}

Future<String?> _storeCover(String jobId, Uint8List bytes) async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final folder = Directory('${docs.path}/saved_results');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final file = File('${folder.path}/cover_$jobId.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (error) {
    debugPrint('Cover save failed: $error');
    return null;
  }
}

Future<Map<String, dynamic>?> _jobStatus(String jobId, String token) async {
  final response = await http
      .get(
        Uri.parse('https://genedit.mooo.com/job_status?job_id=$jobId'),
        headers: {'Authorization': 'Bearer $token'},
      )
      .timeout(const Duration(seconds: 20));
  if (response.statusCode != 200) return null;
  final body = jsonDecode(response.body);
  if (body is! Map) return null;
  return Map<String, dynamic>.from(body);
}

Future<Uint8List?> _downloadCover(
  String jobId,
  String token,
  Map<String, dynamic> status,
) async {
  final urls = <String>[
    for (final key in ['result_url', 'download_url', 'output_url', 'url'])
      if (_httpUrl(status[key]) != null) _httpUrl(status[key])!,
  ];
  for (final key in ['result_url', 'download_url']) {
    final nested = status['result'];
    if (nested is Map && _httpUrl(nested[key]) != null) urls.add(_httpUrl(nested[key])!);
  }
  final variations = status['variation_results'];
  if (variations is List) {
    for (final item in variations) {
      if (item is! Map) continue;
      for (final key in ['url', 'download_url', 'result_url']) {
        final found = _httpUrl(item[key]);
        if (found != null) urls.add(found);
      }
    }
  }
  for (var attempt = 0; attempt < 3; attempt++) {
    final signed = await PollingService.refreshDownloadUrl(jobId);
    final parsed = signed == null ? null : _urlFromBody(signed);
    if (parsed != null) urls.add(parsed);
    for (final url in urls.toSet()) {
      final bytes = await _readHttp(url, token);
      if (bytes != null) return bytes;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return null;
}

String? _httpUrl(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  if (text.startsWith('https://') || text.startsWith('http://')) return text;
  return null;
}

String? _urlFromBody(String raw) {
  final text = raw.trim();
  if (text.startsWith('{') || text.startsWith('[')) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        for (final key in ['url', 'download_url', 'result_url', 'signed_url']) {
          final found = _httpUrl(decoded[key]);
          if (found != null) return found;
        }
      }
      if (decoded is String) return _httpUrl(decoded);
    } catch (_) {}
  }
  if (text.startsWith('"')) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is String) return _httpUrl(decoded);
    } catch (_) {}
  }
  return _httpUrl(text);
}

bool _isImage(Uint8List bytes) {
  if (bytes.length < 12) return false;
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;
  final riff = String.fromCharCodes(bytes.sublist(0, 4));
  final webp = String.fromCharCodes(bytes.sublist(8, 12));
  return riff == 'RIFF' && webp == 'WEBP';
}

Future<Uint8List?> _readHttp(String url, String token, {int depth = 0}) async {
  if (depth > 2) return null;
  try {
    final uri = Uri.parse(url);
    final headers = <String, String>{};
    if (uri.host.contains('genedit.mooo.com')) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 40));
    final received = response.statusCode == 200 || response.statusCode == 206;
    if (!received || response.bodyBytes.length <= 32) {
      debugPrint('Cover download HTTP ${response.statusCode} (${response.bodyBytes.length} bytes)');
      return null;
    }
    if (_isImage(response.bodyBytes)) return response.bodyBytes;
    final followed = _httpUrl(utf8.decode(response.bodyBytes, allowMalformed: true).trim());
    if (followed != null && followed != url) {
      return _readHttp(followed, token, depth: depth + 1);
    }
    debugPrint('Cover download was not an image (${response.bodyBytes.length} bytes)');
  } catch (error) {
    debugPrint('Cover download failed: $error');
  }
  return null;
}
