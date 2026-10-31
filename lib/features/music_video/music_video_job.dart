import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kala_ai_create_images_videos_with_ai/core/api/submit_payload_helpers.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_export.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_template.dart';
import 'package:path_provider/path_provider.dart';

const int kOnDeviceMusicVideoGems = 25;
const String _controller = 'https://genedit.mooo.com';

class MusicVideoJobException implements Exception {
  final String message;
  const MusicVideoJobException(this.message);
}

/// Asks the server to charge the on-phone video and returns the job id.
Future<({String jobId, String token})> reserveOnDeviceMusicVideo({
  required String title,
  required String templateId,
  required String aspect,
}) async {
  final token = await AuthService().getIdToken();
  if (token == null || token.isEmpty) {
    throw const MusicVideoJobException('Sign in to make a music video.');
  }
  final payload = buildSubmitPayload(
    modelId: kLocalMusicVideoModelId,
    modelParams: {
      'aspect_ratio': aspect,
      'template': templateId,
      'on_device': true,
    },
    rootParams: {
      'prompt': title.trim().isEmpty ? 'Music video' : title.trim(),
      'on_device': true,
    },
    fcmToken: null,
  );
  final response = await http
      .post(
        Uri.parse('$_controller/submit'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 30));
  if (response.statusCode == 402) {
    throw const MusicVideoJobException('You need 25 gems for a music HD video.');
  }
  if (response.statusCode >= 400) {
    debugPrint('Music video reserve HTTP ${response.statusCode}');
    throw const MusicVideoJobException('The music video could not be started.');
  }
  final body = jsonDecode(response.body);
  final jobId = body is Map ? body['job_id']?.toString() : null;
  if (jobId == null || jobId.isEmpty) {
    throw const MusicVideoJobException('The music video could not be started.');
  }
  try {
    await http
        .post(
          Uri.parse('$_controller/on_device/job_started'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'job_id': jobId}),
        )
        .timeout(const Duration(seconds: 20));
  } catch (error) {
    debugPrint('Music video job_started failed: $error');
  }
  try {
    await UserService().refreshCredits();
  } catch (error) {
    debugPrint('Credit refresh failed: $error');
  }
  return (jobId: jobId, token: token);
}

/// Renders after the screen has closed. Yields between frames so the
/// creations list can keep drawing.
Future<void> finishOnDeviceMusicVideo({
  required String jobId,
  required String token,
  required MusicVideoExportRequest request,
  required JobModel job,
}) async {
  try {
    final rendered = await exportMusicVideo(request);
    final docs = await getApplicationDocumentsDirectory();
    final folder = Directory('${docs.path}/saved_results');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final name = FileService.generateTimestampFilename('music_video', 'mp4');
    final saved = File('${folder.path}/$name');
    await File(rendered).copy(saved.path);
    await addOrUpdateJob(job.copyWith(
      status: 'completed',
      localFilePath: saved.path,
      readyAt: DateTime.now(),
    ));
    await _complete(jobId, token, success: true);
  } catch (error) {
    debugPrint('Music video export failed: $error');
    await addOrUpdateJob(job.copyWith(status: 'failed'));
    await _complete(jobId, token, success: false, error: error.toString());
  }
}

Future<void> _complete(
  String jobId,
  String token, {
  required bool success,
  String? error,
}) async {
  try {
    await http
        .post(
          Uri.parse('$_controller/on_device/job_complete'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'job_id': jobId,
            'success': success,
            if (error != null && error.isNotEmpty) 'error': error,
          }),
        )
        .timeout(const Duration(seconds: 20));
  } catch (failure) {
    debugPrint('Music video job_complete failed: $failure');
  }
}
