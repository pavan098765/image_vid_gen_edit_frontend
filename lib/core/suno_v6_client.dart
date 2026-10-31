import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:kala_ai_create_images_videos_with_ai/core/api/submit_payload_helpers.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/media_upload_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kSunoV6ControllerUrl = 'https://genedit.mooo.com';
const String _kPersonaPrefsKey = 'suno_v6_personas';

class SunoSubmitResult {
  final String jobId;
  final Map<String, dynamic> raw;

  const SunoSubmitResult({required this.jobId, required this.raw});
}

class SunoStatusResult {
  final String status;
  final String? downloadUrl;
  final String? error;
  final MusicResult? music;
  final Map<String, dynamic> raw;

  const SunoStatusResult({
    required this.status,
    required this.raw,
    this.downloadUrl,
    this.error,
    this.music,
  });
}

class SunoFormException implements Exception {
  final String message;
  const SunoFormException(this.message);

  @override
  String toString() => message;
}

Future<String> _authToken() async {
  final token = await AuthService().getIdToken();
  if (token == null || token.isEmpty) {
    throw const SunoFormException('Sign in to generate music.');
  }
  return token;
}

Future<String?> _fcmToken() async {
  try {
    return await FirebaseMessaging.instance.getToken();
  } catch (_) {
    return null;
  }
}

String _submitErrorMessage(String body, int statusCode) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail.trim();
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map) {
          final msg = first['msg'] ?? first['message'];
          if (msg != null) return msg.toString();
        }
        return first.toString();
      }
      final message = decoded['message'] ?? decoded['error'];
      if (message is String && message.trim().isNotEmpty) return message.trim();
    }
  } catch (_) {}
  return 'Submit failed ($statusCode)';
}

Future<SunoSubmitResult> submitSunoV6({
  required String prompt,
  required Map<String, dynamic> params,
  List<String>? imageR2Keys,
  String? videoR2Key,
}) async {
  final token = await _authToken();
  final cleaned = Map<String, dynamic>.from(params)
    ..removeWhere((key, value) {
      if (value == null) return true;
      if (value is String && value.trim().isEmpty) return true;
      if (value is String && RegExp(r'^\{\{[\w\-]+\}\}$').hasMatch(value.trim())) {
        return true;
      }
      return false;
    });
  stripForbiddenMediaFromParams(cleaned);

  final root = <String, dynamic>{
    'prompt': prompt,
    if (imageR2Keys != null && imageR2Keys.isNotEmpty)
      'input_image_r2_keys': imageR2Keys,
    if (videoR2Key != null && videoR2Key.isNotEmpty)
      'input_video_r2_key': videoR2Key,
  };

  final payload = buildSubmitPayload(
    modelId: kSunoV6ModelId,
    modelParams: cleaned,
    fcmToken: await _fcmToken(),
    rootParams: root,
    enhancePrompt: false,
    variations: 1,
  );

  final resp = await http
      .post(
        Uri.parse('$kSunoV6ControllerUrl/submit'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 60));

  if (resp.statusCode == 400) {
    throw SunoFormException(_submitErrorMessage(resp.body, resp.statusCode));
  }
  if (resp.statusCode != 200) {
    throw SunoFormException(_submitErrorMessage(resp.body, resp.statusCode));
  }

  final data = jsonDecode(resp.body);
  if (data is! Map) {
    throw const SunoFormException('Unexpected submit response.');
  }
  final raw = Map<String, dynamic>.from(data);
  String? jobId;
  if (raw['job_id'] != null) jobId = raw['job_id'].toString();
  if ((jobId == null || jobId.isEmpty) && raw['job_ids'] is List) {
    final ids = raw['job_ids'] as List;
    if (ids.isNotEmpty) jobId = ids.first.toString();
  }
  if (jobId == null || jobId.isEmpty) {
    throw const SunoFormException('No job id returned.');
  }
  return SunoSubmitResult(jobId: jobId, raw: raw);
}

Future<SunoStatusResult> pollSunoV6Job(String jobId) async {
  final token = await _authToken();
  final resp = await http
      .get(
        Uri.parse('$kSunoV6ControllerUrl/job_status?job_id=$jobId'),
        headers: {'Authorization': 'Bearer $token'},
      )
      .timeout(const Duration(seconds: 20));
  if (resp.statusCode != 200) {
    throw SunoFormException('Could not read job status (${resp.statusCode}).');
  }
  final decoded = jsonDecode(resp.body);
  if (decoded is! Map) {
    throw const SunoFormException('Unexpected job status.');
  }
  final raw = Map<String, dynamic>.from(decoded);
  var status = (raw['status'] ?? 'processing').toString().toLowerCase();
  if (status == 'done') status = 'completed';
  final music = musicMapFromStatus(raw['music']);
  return SunoStatusResult(
    status: status,
    downloadUrl: raw['download_url']?.toString() ?? raw['result_url']?.toString(),
    error: raw['error']?.toString() ?? raw['detail']?.toString(),
    music: music == null ? null : MusicResult.fromJson(music),
    raw: raw,
  );
}

Future<List<String>> uploadSunoImages(List<Uint8List> files) async {
  if (files.isEmpty) return const [];
  final token = await _authToken();
  final keys = await MediaUploadService.uploadMediaBatch(
    files: files,
    mediaType: 'image',
    authToken: token,
  );
  if (keys == null || keys.length != files.length) {
    throw const SunoFormException('Could not upload photos. Check your connection.');
  }
  return keys;
}

Future<String> uploadSunoVideo(Uint8List bytes) async {
  final token = await _authToken();
  final keys = await MediaUploadService.uploadMediaBatch(
    files: [bytes],
    mediaType: 'video',
    authToken: token,
  );
  if (keys == null || keys.isEmpty) {
    throw const SunoFormException('Could not upload video. Check your connection.');
  }
  return keys.first;
}

Future<String> uploadSunoAudio(Uint8List bytes, {String mime = 'audio/mpeg'}) async {
  final token = await _authToken();
  final urls = await MediaUploadService.getMediaUploadUrls(
    count: 1,
    mediaType: 'image',
    authToken: token,
  );
  if (urls == null || urls.isEmpty) {
    throw const SunoFormException('Could not reserve storage for audio.');
  }
  final ok = await MediaUploadService.uploadToR2(
    urls.first.uploadUrl,
    bytes,
    contentType: mime,
  );
  if (!ok) {
    throw const SunoFormException('Could not upload audio. Check your connection.');
  }
  return urls.first.r2Key;
}

Future<List<MusicPersona>> loadSavedPersonas() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kPersonaPrefsKey);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => MusicPersona.fromJson(Map<String, dynamic>.from(e)))
        .where((p) => p.id.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}

Future<void> savePersonaLocally(MusicPersona persona) async {
  if (persona.id.isEmpty) return;
  final existing = await loadSavedPersonas();
  final next = [
    persona,
    ...existing.where((p) => p.id != persona.id),
  ];
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _kPersonaPrefsKey,
    jsonEncode(next.map((p) => p.toJson()).toList()),
  );
}

String guessAudioMime(String path) {
  final ext = path.split('.').last.toLowerCase();
  switch (ext) {
    case 'wav':
      return 'audio/wav';
    case 'm4a':
      return 'audio/mp4';
    case 'aac':
      return 'audio/aac';
    case 'ogg':
      return 'audio/ogg';
    case 'flac':
      return 'audio/flac';
    default:
      return 'audio/mpeg';
  }
}

Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();

/// Asks the controller to proxy KIE `ai-music-api/timeStamped-lyrics`.
/// The phone never calls KIE. The lookup is not a song charge.
Future<TimestampedLyrics> fetchTimestampedLyrics({
  required String taskId,
  required String audioId,
}) async {
  if (taskId.trim().isEmpty || audioId.trim().isEmpty) {
    throw const SunoFormException('This version has no timed lyrics yet.');
  }
  final submitted = await submitSunoV6(
    prompt: '',
    params: {
      'action': 'timestamped_lyrics',
      'source_task_id': taskId,
      'audio_id': audioId,
    },
  );
  final immediate = timestampedLyricsFromJson(submitted.raw);
  if (immediate != null && immediate.words.isNotEmpty) return immediate;

  Object? lastError;
  for (var attempt = 0; attempt < 10; attempt++) {
    await Future<void>.delayed(
      Duration(milliseconds: attempt == 0 ? 400 : 1000),
    );
    try {
      final status = await pollSunoV6Job(submitted.jobId);
      final parsed = timestampedLyricsFromJson(status.raw) ??
          status.music?.alignedLyricsFor(audioId);
      if (parsed != null && parsed.words.isNotEmpty) return parsed;
      if (status.status == 'failed') {
        throw SunoFormException(
          status.error ?? 'Timed lyrics are not available for this version.',
        );
      }
      if (status.status == 'completed') break;
    } on SunoFormException catch (error) {
      lastError = error;
      if (error.message.contains('not available') ||
          error.message.contains('Timed lyrics')) {
        rethrow;
      }
    } catch (error) {
      lastError = error;
    }
  }
  if (lastError is SunoFormException) throw lastError;
  throw const SunoFormException(
    'Timed lyrics are not available for this version.',
  );
}
