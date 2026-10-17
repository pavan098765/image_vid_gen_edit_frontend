import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:kala_ai_create_images_videos_with_ai/core/api/submit_payload_helpers.dart';

import 'workflow_models.dart';

const _submitUrl = 'https://genedit.mooo.com/submit';

typedef SubmitCall = Future<String> Function({
  required String model,
  required String prompt,
  Map<String, dynamic> params,
});

class StudioSubmit {
  StudioSubmit({http.Client? client, this.submitOverride}) : _client = client ?? http.Client();
  final http.Client _client;
  final SubmitCall? submitOverride;

  Future<String> submit({
    required String model,
    required String prompt,
    Map<String, dynamic> params = const {},
  }) async {
    if (submitOverride != null) {
      return submitOverride!(model: model, prompt: prompt, params: params);
    }
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in to make this film.');
    }
    final payload = buildSubmitPayload(
      modelId: model,
      modelParams: Map<String, dynamic>.from(params),
      rootParams: {'prompt': prompt},
      fcmToken: null,
    );
    final resp = await _client.post(
      Uri.parse(_submitUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );
    if (resp.statusCode == 402) {
      throw StateError('You need more gems for this shot.');
    }
    if (resp.statusCode >= 400) {
      throw StateError('That shot could not be started. Try it again.');
    }
    final body = jsonDecode(resp.body);
    final id = (body is Map ? body['job_id'] : null)?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('That shot could not be started. Try it again.');
    }
    return id;
  }

  Future<String> submitPicture(ShotCard shot, {required String aspect, List<String> guides = const []}) {
    final posed = (shot.keyframeR2Key ?? '').trim();
    final brought = (shot.referenceR2Key ?? '').trim();
    final opening = posed.isNotEmpty
        ? posed
        : (shot.model.startsWith('ltx') || shot.makeKeyframe ? brought : '');
    final end = (shot.endFrameR2Key ?? '').trim();
    final hasRef = opening.isNotEmpty;
    final hasEnd = end.isNotEmpty;
    final sheets = guides.map((key) => key.trim()).where((key) => key.isNotEmpty).take(4).toList();
    final latent = (shot.continuationLatentR2Key ?? '').trim();
    if (shot.kind == 'video') {
      final chained = shot.model.startsWith('ltx');
      final String model;
      final String mode;
      if (chained && hasRef && hasEnd) {
        model = 'ltx25_int8_flf2v';
        mode = 'flf2v';
      } else if (chained && (hasRef || hasEnd)) {
        model = 'ltx25_int8_i2v';
        mode = 'i2v';
      } else if (chained) {
        model = 'ltx25_int8_t2v';
        mode = 't2v';
      } else {
        model = 'minimax_h3';
        mode = hasRef || hasEnd ? 'i2v' : 't2v';
      }
      final seconds = shot.durationSeconds.clamp(1, chained ? 20 : 15);
      return submit(
        model: model,
        prompt: shot.videoPrompt ?? shot.action,
        params: {
          'seconds': seconds,
          'duration': seconds,
          'duration_seconds': seconds,
          'aspect_ratio': aspect,
          'mode': mode,
          'quality': shot.quality,
          'studio_shot': true,
          if (hasRef) 'init_image_r2_key': opening,
          if (!hasRef && hasEnd) 'init_image_r2_key': end,
          if (hasRef && hasEnd) 'last_frame_image_r2_key': end,
          if (!chained && sheets.isNotEmpty) 'reference_image_r2_keys': sheets,
          if (latent.isNotEmpty) 'continuation_latent_r2_key': latent,
          if (chained && (shot.audioInSeconds > 0 || latent.isNotEmpty)) 'audio_in_seconds': shot.audioInSeconds,
        },
      );
    }
    final secondsStill = shot.durationSeconds;
    final keys = guides.map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
    final stillStart = opening.isNotEmpty ? opening : (shot.referenceR2Key ?? '').trim();
    if (keys.isEmpty && stillStart.isNotEmpty) keys.add(stillStart);
    return submit(
      model: keys.isNotEmpty ? 'qwen2_1_i2i' : 'qwen2_1_t2i',
      prompt: shot.stillPrompt ?? shot.action,
      params: {
        'aspect_ratio': aspect,
        'studio_shot': true,
        if (keys.length == 1) 'init_image_r2_key': keys.first,
        if (keys.length > 1) 'init_image_r2_keys': keys,
        'duration': secondsStill,
      },
    );
  }
}
