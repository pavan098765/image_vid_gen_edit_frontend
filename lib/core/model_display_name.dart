/// Maps the id stored on a job to the name shown in the app.
///
/// Submit uses the ids in tool_config (`flux2_klein_9b`). Kie and Runware
/// often echo their own ids back (`runware:400@2`). Those aliases live on
/// the model in tool_config so a new provider id does not need a code change.
library;

const Map<String, String> kFallbackModelDisplayNames = {
  'flux2_klein_9b': 'Kala Flash',
  'flux2_klein_9b_edit': 'Kala Flash',
  'muse_image': 'Kala Canvas',
  'muse_image_edit': 'Kala Canvas',
  'xai_tts': 'Kala Voice',
  'qwen_voice_design': 'Kala Speech',
  'qwen_voice_clone': 'Kala Speech Clone',
  'ace_step_music': 'Kala SongFlow',
  'minimax_music_26': 'Kala BeatWave',
  'recraft_crisp_upscale': 'Crisp Upscale',
  'realesrgan_upscale': 'General Upscale',
  'p_image_upscale': 'Fine Upscale',
  'qwen2_1_t2i': 'Kala Imagine',
  'qwen2_1_i2i': 'Kala Imagine',
  'grok_imagine_t2i': 'Kala Dream',
  'grok_imagine_edit': 'Kala Dream',
  'suno_music': 'Kala Song',
  'suno_sfx': 'Kala Sound',
  'suno_v6': 'Kala HitMaker',
  'gemini_tts': 'Kala Voice',
  'runware:400@2': 'Kala Flash',
  'meta:muse@image': 'Kala Canvas',
  'xai:tts@0': 'Kala Voice',
  'alibaba:qwen@3-tts-1.7b-voicedesign': 'Kala Speech',
  'alibaba:qwen@3-tts-1.7b-base': 'Kala Speech Clone',
  'runware:ace-step@v1.5-xl-sft': 'Kala SongFlow',
  'minimax:music@2.6': 'Kala BeatWave',
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
