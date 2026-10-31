/// Maps the id stored on a job to the name shown in the app.
///
/// Submit uses the ids in tool_config (`flux2_klein_9b`). Kie and Runware
/// often echo their own ids back (`runware:400@2`). Those aliases live on
/// the model in tool_config so a new provider id does not need a code change.
library;

const Map<String, String> kFallbackModelDisplayNames = {
  'ace_step_music': 'Kala SongFlow',
  'alibaba:qwen@3-tts-1.7b-base': 'Kala Speech Clone',
  'alibaba:qwen@3-tts-1.7b-voicedesign': 'Kala Speech',
  'basic_utils': 'Object Eraser',
  'dreamid': 'RefMotion',
  'fastwan_21_1b': 'Cinemotion',
  'flux2_klein_9b': 'Kala Flash',
  'flux2_klein_9b_edit': 'Kala Flash',
  'gemini_ocr': 'TextScan',
  'gemini_tts': 'Kala Voice',
  'grok_imagine_edit': 'Kala Dream',
  'grok_imagine_t2i': 'Kala Dream',
  'hunyan15_480p_i2v_step_distilled': 'AnimateFlow',
  'hunyan15_480p_t2v_distilled': 'MotionFlow',
  'juggernaut_lightning': 'Kala Vista',
  'juggernaut_lightning_expand': 'Kala Vista',
  'krea2_turbo': 'Kala Palette',
  'krea2_turbo_edit': 'Kala Palette',
  'krea:krea@2-turbo': 'Kala Palette',
  'ltx25_int8': 'CineReal',
  'ltx25_int8_flf2v': 'CineReal',
  'ltx25_int8_i2v': 'CineReal',
  'ltx25_int8_t2v': 'CineReal',
  'ltx2_3_cinereal': 'CineReal',
  'ltx2_3_t2v': 'CineReal',
  'meta:muse@image': 'Kala Canvas',
  'minimax:music@2.6': 'Kala BeatWave',
  'minimax_h3': 'Cinemotion Pro',
  'minimax_music_26': 'Kala BeatWave',
  'muse_image': 'Kala Canvas',
  'muse_image_edit': 'Kala Canvas',
  'p_image_upscale': 'Fine Upscale',
  'qwen2_1_i2i': 'Kala Imagine',
  'qwen2_1_t2i': 'Kala Imagine',
  'qwen_voice_clone': 'Kala Speech Clone',
  'qwen_voice_design': 'Kala Speech',
  'realesrgan_upscale': 'General Upscale',
  'recraft:v4.1@flash': 'Kala Poster',
  'recraft_crisp_upscale': 'Crisp Upscale',
  'recraft_remove_background': 'Background Remover',
  'recraft_v41_flash': 'Kala Poster',
  'rundiffusion:110@101': 'Kala Vista',
  'runware:400@2': 'Kala Flash',
  'runware:ace-step@v1.5-xl-sft': 'Kala SongFlow',
  'runware:twinflow-z-image-turbo@0': 'Kala Glimpse',
  'runware:z-image@turbo': 'Kala Touch',
  'sdxl_inpaint': 'Imagia Inpaint',
  'suno_music': 'Kala Song',
  'suno_sfx': 'Kala Sound',
  'kala_music_video': 'Kala HitMaker',
  'suno_v6': 'Kala HitMaker',
  'twinflow_z_image': 'Kala Glimpse',
  'video_upscaler': 'Video Enhancer',
  'wan_22_fp8_lightx2v_i2v': 'Cinemotion Pro',
  'wan_22_fp8_lightx2v_t2v': 'Cinemotion Pro',
  'xai:tts@0': 'Kala Voice',
  'xai_tts': 'Kala Voice',
  'z_image_turbo_edit': 'Kala Touch',
  'z_image_turbo_expand': 'Kala Touch',
  'z_image_turbo_inpaint': 'Kala Touch',
};

final Map<String, String> modelDisplayNameCache = {};

bool looksLikeProviderModelId(String? id) {
  if (id == null || id.isEmpty || id == 'unknown') return true;
  return id.contains(':') || id.contains('/');
}

/// Keep the app id (`flux2_klein_9b`) when a status ping brings a provider id.
String preferInternalModelId(String? first, String? second) {
  if (!looksLikeProviderModelId(first)) return first!;
  if (!looksLikeProviderModelId(second)) return second!;
  if (first != null && first.isNotEmpty) return first;
  if (second != null && second.isNotEmpty) return second;
  return 'unknown';
}

void indexModelDisplayNames(Map<String, dynamic> config) {
  final capabilities = config['capabilities'];
  if (capabilities is! List) return;
  for (final cap in capabilities) {
    if (cap is! Map) continue;
    final models = cap['models'];
    if (models is! List) continue;
    for (final model in models) {
      if (model is! Map) continue;
      final id = model['id']?.toString();
      final name = model['name']?.toString();
      if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
      modelDisplayNameCache.putIfAbsent(id, () => name);
      final aliases = model['aliases'];
      if (aliases is List) {
        for (final alias in aliases) {
          final key = alias.toString().trim();
          if (key.isEmpty) continue;
          modelDisplayNameCache.putIfAbsent(key, () => name);
        }
      }
    }
  }
}

String displayNameForModel(String? modelId) {
  if (modelId == null || modelId.isEmpty || modelId == 'unknown') {
    return modelId ?? '';
  }
  final mapped = kFallbackModelDisplayNames[modelId];
  if (mapped != null && mapped.isNotEmpty) return mapped;
  final cached = modelDisplayNameCache[modelId];
  if (cached != null && cached.isNotEmpty && cached != modelId) return cached;
  return modelId;
}

/// Catalogue name for a model id. Null when the id has no separate name.
String? friendlyModelName(String? modelId) {
  final id = modelId?.trim() ?? '';
  if (id.isEmpty) return null;
  final name = displayNameForModel(id).trim();
  if (name.isEmpty || name == id) return null;
  return name;
}
