// Shared rules for POST /submit (must match server SubmitRequest + extra=forbid).

import 'package:flutter/foundation.dart';

import 'package:kala_ai_create_images_videos_with_ai/core/services/media_upload_service.dart';

/// Allowed top-level JSON keys besides those set explicitly (model, params, fcm_token).
const Set<String> kAllowedSubmitRootKeys = {
  'prompt',
  'enhance_prompt',
  'variations',
  'on_device',
  'is_bulk',
  'bulk_outpaint_configs',
  'input_image_r2_keys',
  'mask_image_r2_key',
  'bulk_mask_r2_keys',
  'input_video_r2_key',
};

/// Server rejects these inside `params` when they hold embedded media (use *_r2_key / body fields).
const Set<String> kForbiddenMediaParamKeys = {
  'init_image',
  'image',
  'mask',
  'mask_image',
  'input_video',
  'ref_image',
  'ref_video',
  'init_video',
  'images',
  'control_image',
  'source_image',
  'reference_image',
  'style_image',
  'face_image',
  'input_image',
  'background_image',
  'foreground_image',
  'depth_image',
  'normal_image',
  'first_frame_image',
  'last_frame_image',
};

Map<String, dynamic> filterSubmitRootParams(Map<String, dynamic> rootParams) {
  final out = <String, dynamic>{};
  for (final e in rootParams.entries) {
    if (kAllowedSubmitRootKeys.contains(e.key)) {
      out[e.key] = e.value;
    }
  }
  return out;
}

void stripForbiddenMediaFromParams(Map<String, dynamic> p) {
  for (final k in kForbiddenMediaParamKeys) {
    p.remove(k);
  }
}

/// Top-level submit body with allowlisted root fields (server `extra=forbid`).
Map<String, dynamic> buildSubmitPayload({
  required Object? modelId,
  required Map<String, dynamic> modelParams,
  String? fcmToken,
  required Map<String, dynamic> rootParams,
  bool enhancePrompt = false,
  int variations = 1,
}) {
  final filtered = filterSubmitRootParams(rootParams);
  final mid = modelId?.toString();
  if (mid == null || mid.isEmpty) {
    throw ArgumentError.value(modelId, 'modelId', 'model id is required for submit');
  }
  return {
    ...filtered,
    'model': mid,
    'params': modelParams,
    'fcm_token': fcmToken,
    'enhance_prompt': enhancePrompt,
    'variations': variations,
  };
}

/// R2 upload for Explore / template flows: sets [init_image_r2_key] or
/// [init_image_r2_keys] (never top-level [input_image_r2_keys] for multi-ref).
Future<void> applyExploreMediaR2Upload({
  required List<Uint8List>? images,
  required Uint8List? videoBytes,
  required Map<String, dynamic> modelParams,
  required Map<String, dynamic> payload,
  required String authToken,
}) async {
  if (images != null && images.isNotEmpty) {
    final imageKeys = await MediaUploadService.uploadMediaBatch(
      files: images,
      mediaType: 'image',
      authToken: authToken,
    );
    if (imageKeys == null || imageKeys.length != images.length) {
      throw Exception(
        'Could not upload images to cloud storage. Check your connection and try again.',
      );
    }
    stripForbiddenMediaFromParams(modelParams);
    payload.remove('input_image_r2_keys');
    if (imageKeys.length == 1) {
      modelParams['init_image_r2_key'] = imageKeys.first;
    } else {
      modelParams['init_image_r2_keys'] = imageKeys;
    }
  }

  if (videoBytes != null && videoBytes.isNotEmpty) {
    final videoKeys = await MediaUploadService.uploadMediaBatch(
      files: [videoBytes],
      mediaType: 'video',
      authToken: authToken,
    );
    if (videoKeys == null || videoKeys.isEmpty) {
      throw Exception(
        'Could not upload video to cloud storage. Check your connection and try again.',
      );
    }
    payload['input_video_r2_key'] = videoKeys.first;
    for (final k in ['init_video', 'input_video', 'ref_video']) {
      modelParams.remove(k);
    }
  }
}
