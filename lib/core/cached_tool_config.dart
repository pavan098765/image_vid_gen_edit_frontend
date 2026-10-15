import 'dart:convert';

import 'package:kala_ai_create_images_videos_with_ai/core/services/sale_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kCachedToolConfigKey = 'cached_tool_config_v3';

Future<Map<String, dynamic>?> loadCachedToolConfig() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kCachedToolConfigKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

Map<String, dynamic>? capabilityById(
  Map<String, dynamic> config,
  String capabilityId,
) {
  final caps = config['capabilities'];
  if (caps is! List) return null;
  for (final c in caps) {
    if (c is Map && c['id'] == capabilityId) {
      return Map<String, dynamic>.from(c);
    }
  }
  return null;
}

bool capabilityHasEnabledModel(Map<String, dynamic> capability) {
  final models = capability['models'];
  if (models is! List || models.isEmpty) return false;
  return models.whereType<Map>().any((m) {
    final enabled = m['enabled'];
    return enabled == null || enabled == true;
  });
}

Map<String, dynamic>? enabledModelById(
  Map<String, dynamic> capability,
  String? modelId,
) {
  final models = capability['models'];
  if (models is! List) return null;
  final enabled = models.whereType<Map>().where((m) {
    final e = m['enabled'];
    return e == null || e == true;
  }).toList();
  if (enabled.isEmpty) return null;
  if (modelId != null) {
    for (final m in enabled) {
      if (m['id'] == modelId) return Map<String, dynamic>.from(m);
    }
  }
  final defaultId = capability['defaultModel'] as String?;
  for (final m in enabled) {
    if (m['id'] == defaultId) return Map<String, dynamic>.from(m);
  }
  return Map<String, dynamic>.from(enabled.first);
}

Map<String, dynamic>? capabilityContainingModel(
  Map<String, dynamic> config,
  String modelId,
) {
  final caps = config['capabilities'];
  if (caps is! List) return null;
  for (final c in caps) {
    if (c is! Map) continue;
    final cap = Map<String, dynamic>.from(c);
    if (enabledModelById(cap, modelId)?['id'] == modelId) return cap;
  }
  return null;
}

int liveModelCost(Map<String, dynamic> model, {bool upscaleEnabled = false}) {
  final cost = (model['cost'] as num?)?.toInt() ?? 10;
  final modelOffer = (model['offer'] as num?)?.toInt() ?? 0;
  final sale = SaleService().state.value;
  final offer = (sale.isActive && sale.discountPercent > 0)
      ? sale.discountPercent
      : modelOffer;
  var base = cost;
  if (offer > 0) {
    base = (cost * (1 - offer / 100)).round();
  }
  var extra = 0;
  if (upscaleEnabled && !isUpscaleFree()) {
    extra = (model['costUpscale'] as num?)?.toInt() ?? 0;
  }
  return base + extra;
}

int? liveCapabilityCost(
  Map<String, dynamic> config,
  String capabilityId, {
  String? modelId,
  bool upscaleEnabled = false,
}) {
  final cap = capabilityById(config, capabilityId);
  if (cap == null || !capabilityHasEnabledModel(cap)) return null;
  final model = enabledModelById(cap, modelId);
  if (model == null) return null;
  return liveModelCost(model, upscaleEnabled: upscaleEnabled);
}
