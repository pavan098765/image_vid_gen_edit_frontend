/// RIFE runs at discrete steps (2×, 4×, 8× output frame count). The backend maps a
/// requested [targetFps] to an exponent and may resample; we send `baseFps * multiplier`
/// so that mapping aligns with user intent (see server `calculate_rife_exp`).

const List<int> kRifeSpeedMultipliers = [2, 4];

/// Normalizes stored UI value to 2, 4, or 8. Handles persisted "target FPS" sliders (legacy).
int migrateLegacyInterpolateStorageValue(int? raw) {
  if (raw == null) return 2;
  if (raw == 2 || raw == 4 || raw == 8) return raw;
  if (raw < 16) return 2;
  if (raw <= 40) return 2;
  if (raw <= 72) return 4;
  return 8;
}

/// Estimated source/output FPS before RIFE (model defaults; upscaler uses a typical upload guess).
int estimatedBaseFpsForRife({
  required String modelId,
  required Map<String, dynamic> modelParams,
  required bool isVideoUpscalerTool,
}) {
  if (isVideoUpscalerTool) return 30;
  final mid = modelId.toLowerCase();
  if (mid == 'dreamid') {
    return (modelParams['sample_fps'] as num?)?.toInt() ?? 24;
  }
  if (mid.contains('hunyan') || mid.contains('hunyuan')) {
    return (modelParams['fps'] as num?)?.toInt() ?? 24;
  }
  if (mid.startsWith('ltx2_3') || mid.startsWith('ltx25_int8')) {
    final fr = modelParams['frame_rate'] ?? modelParams['fps'];
    if (fr is num) return fr.round();
  }
  return (modelParams['fps'] as num?)?.toInt() ?? 24;
}

/// Backend-facing target FPS for RIFE / interpolation.
///
/// [forUpscalerTargetFps]: worker `target_fps` is capped at 60 before RIFE.
int rifeTargetFpsForSubmit({
  required int multiplier,
  required int baseFps,
  required bool forUpscalerTargetFps,
}) {
  final m = kRifeSpeedMultipliers.contains(multiplier) ? multiplier : 2;
  final b = baseFps.clamp(8, 120);
  var t = (b * m).round();
  if (forUpscalerTargetFps) {
    t = t.clamp(17, 60);
  } else {
    t = t.clamp(17, 240);
  }
  return t;
}
